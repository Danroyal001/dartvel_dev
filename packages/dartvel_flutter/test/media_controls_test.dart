// What a person sees and uses on DVBox.video, DVBox.audio and DVBox.camera:
// captions as real text, controls with labels in Tab order, the keyboard,
// and a camera that closes with its page.
@TestOn('vm')
library;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const DVMediaSource film = DVMediaSource.url('https://cdn.test/film.mp4');

Widget host(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 800, height: 450, child: child)));

final class _Granted implements DVCapturePermissions {
  @override
  Future<bool> request(String permission) async => true;
}

void main() {
  late List<DVFakeMediaPlayerBackend> created;
  late DVMutableLifecycleSignal<DVAppLifecycle> app;

  setUp(() {
    created = <DVFakeMediaPlayerBackend>[];
    app = DVMutableLifecycleSignal<DVAppLifecycle>(DVAppLifecycle.ready);
    DVMediaBackends.reset();
    DVMediaBackends.environment = () => DVMediaEnvironment(
          lifecycle: app,
          focus: DVAudioFocus(DVFakeAudioFocusBackend()),
          timers: DVFakeMediaTimers(),
          captionLoader: (DVMediaSource source) async =>
              'WEBVTT\n\n00:00:01.000 --> 00:00:03.000\nWhere were you?\n',
          diagnostics: (String code, String message) {},
        );
    DVMediaBackends.registerPlayer((DVMediaSource source, DVMediaKind kind) {
      final DVFakeMediaPlayerBackend backend = DVFakeMediaPlayerBackend();
      created.add(backend);
      return backend;
    });
  });

  tearDown(DVMediaBackends.reset);

  Future<DVBox<Object?>> mounted(WidgetTester tester,
      {DVCaptions? captions, DVMediaSession? session}) async {
    final DVBox<Object?> box =
        DVBox.video(film, captions: captions, session: session);
    await tester.pumpWidget(host(box));
    created.single.emit(const DVMediaReady(duration: Duration(minutes: 2)));
    await tester.pump();
    await tester.pump();
    return box;
  }

  testWidgets('captions are text a screen reader is told about',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final DVBox<Object?> box = await mounted(tester,
        captions: DVCaptions.track(
            'en', const DVMediaSource.url('https://cdn.test/film.en.vtt')));
    expect(box.controller.captionTrack.value, 'en');

    created.single.emit(const DVMediaPosition(Duration(seconds: 2)));
    await tester.pump();
    expect(find.text('Where were you?'), findsOneWidget);
    expect(
        tester.getSemantics(find.byType(DVCaptionLine)),
        matchesSemantics(label: 'Where were you?', isLiveRegion: true));

    created.single.emit(const DVMediaPosition(Duration(seconds: 4)));
    await tester.pump();
    expect(find.text('Where were you?'), findsNothing);
    semantics.dispose();
  });

  testWidgets('the captions button turns them off and on',
      (WidgetTester tester) async {
    final DVBox<Object?> box = await mounted(tester,
        captions: DVCaptions.track(
            'en', const DVMediaSource.url('https://cdn.test/film.en.vtt')));
    await tester.tap(find.byTooltip('Captions: en'));
    await tester.pump();
    expect(box.controller.captionTrack.value, isNull);
    await tester.tap(find.byTooltip('Turn captions on'));
    await tester.pump();
    await tester.pump();
    expect(box.controller.captionTrack.value, 'en');
  });

  testWidgets('a player with no captions offers no captions button',
      (WidgetTester tester) async {
    await mounted(tester);
    expect(find.byTooltip('Turn captions on'), findsNothing);
    expect(find.byTooltip('Mute'), findsOneWidget);
  });

  testWidgets('the scrubber says where playback is in words',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await mounted(tester);
    created.single.emit(const DVMediaPosition(Duration(seconds: 65)));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('1:05 / 2:00'), findsOneWidget);
    expect(find.semantics.byValue('1:05 of 2:00'), findsOne);
    semantics.dispose();
  });

  testWidgets('the session title names the player', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await mounted(tester, session: const DVMediaSession(title: 'Launch film'));
    expect(find.bySemanticsLabel('Video: Launch film'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('mute sets the volume to zero and back',
      (WidgetTester tester) async {
    await mounted(tester);
    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    expect(created.single.volumes.last, 0);
    await tester.tap(find.byTooltip('Unmute'));
    await tester.pump();
    expect(created.single.volumes.last, 1);
  });

  testWidgets('keyboard: k plays, l skips, m mutes, while the player is focused',
      (WidgetTester tester) async {
    await mounted(tester);
    final FocusNode node = Focus.of(tester.element(find.byType(Stack).first));
    node.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(created.single.calls, contains('play'));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(created.single.seeks.last.$1, const Duration(seconds: 5));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(created.single.volumes.last, 0);
  });

  testWidgets('picture-in-picture is offered only where the target has it',
      (WidgetTester tester) async {
    await mounted(tester);
    expect(find.byTooltip('Picture-in-picture'), findsNothing);
  });

  group('camera', () {
    late List<DVFakeCameraBackend> cameras;

    setUp(() {
      cameras = <DVFakeCameraBackend>[];
      DVMediaBackends.registerCamera(() {
        final DVFakeCameraBackend camera = DVFakeCameraBackend();
        cameras.add(camera);
        return camera;
      }, capabilities: DVFakeCameraBackend().capabilities);
    });

    Widget cameraHost() => host(DVBox.camera(
        controller: DVCameraController(
          DVMediaBackends.createCamera()!,
          environment: DVCameraEnvironment(
            permissions: _Granted(),
            files: const _NoFiles(),
            lifecycle: app,
          ),
        )));

    testWidgets('a box with no camera bound says so and opens nothing',
        (WidgetTester tester) async {
      DVMediaBackends.reset();
      await tester.pumpWidget(host(DVBox.camera()));
      await tester.pump();
      expect(find.textContaining('No camera'), findsOneWidget);
    });

    testWidgets('mounting opens it and the controls are labelled',
        (WidgetTester tester) async {
      final DVBox<Object?> box = DVBox.camera(
          controller: DVCameraController(DVMediaBackends.createCamera()!,
              environment: DVCameraEnvironment(
                  permissions: _Granted(),
                  files: const _NoFiles(),
                  lifecycle: app)));
      await tester.pumpWidget(host(box));
      await tester.pump();
      await tester.pump();
      expect(box.camera.state.value, DVCameraState.ready);
      expect(find.byTooltip('Take photo'), findsOneWidget);
      expect(find.byTooltip('Record video'), findsOneWidget);
      expect(find.byTooltip('Switch camera (now back)'), findsOneWidget);
      expect(find.byTooltip('Flash: off'), findsOneWidget);
      expect(find.byTooltip('Torch on'), findsOneWidget);

      await tester.tap(find.byTooltip('Flash: off'));
      await tester.pump();
      expect(box.camera.flash.value, DVFlashMode.auto);
    });

    testWidgets('a box the application owns the controller of keeps it open',
        (WidgetTester tester) async {
      await tester.pumpWidget(cameraHost());
      await tester.pump();
      expect(cameras.last.isOpen, isTrue);
      await tester.pumpWidget(host(const SizedBox()));
      // The application passed the controller in, so the box leaves it be.
      expect(cameras.last.disposed, isFalse);
    });

    testWidgets('leaving the page closes the camera the box made',
        (WidgetTester tester) async {
      DVMediaBackends.reset();
      final List<DVFakeCameraBackend> made = <DVFakeCameraBackend>[];
      DVMediaBackends.registerCamera(() {
        final DVFakeCameraBackend camera = DVFakeCameraBackend();
        made.add(camera);
        return camera;
      }, capabilities: DVFakeCameraBackend().capabilities);
      await tester.pumpWidget(host(DVBox.camera()));
      await tester.pump();
      await tester.pumpWidget(host(const SizedBox()));
      await tester.pump();
      expect(made.single.disposed, isTrue);
    });
  });
}

final class _NoFiles implements DVCaptureFiles {
  const _NoFiles();

  @override
  Future<String> reserve(String extension) async => '/tmp/photo.$extension';

  @override
  Future<int> seal(String path) async => 1;

  @override
  Future<void> discard(String path) async {}
}
