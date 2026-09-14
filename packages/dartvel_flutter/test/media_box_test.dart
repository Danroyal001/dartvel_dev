// `DVBox.video` and `DVBox.audio`: a player as a box mode.
//
// What these guard is ownership. The box mounts a player and the box's
// element owns it, so leaving the page releases the decoder and audio focus
// without the application remembering to; a parent rebuilding the box does not
// start a second player behind the first; and a target with nothing to play
// through says so instead of drawing an empty rectangle.
@TestOn('vm')
library;

import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const DVMediaSource launch = DVMediaSource.url('https://cdn.test/launch.mp4');
const DVMediaSource trailer = DVMediaSource.url('https://cdn.test/trailer.mp4');

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late List<DVFakeMediaPlayerBackend> created;
  late DVFakeAudioFocusBackend focusBackend;
  late DVAudioFocus focus;
  late DVMutableLifecycleSignal<DVAppLifecycle> app;

  void registerFakes() {
    DVMediaBackends.environment = () => DVMediaEnvironment(
          lifecycle: app,
          focus: focus,
          timers: DVFakeMediaTimers(),
          diagnostics: (String code, String message) {},
        );
    DVMediaBackends.registerPlayer((DVMediaSource source, DVMediaKind kind) {
      final DVFakeMediaPlayerBackend backend = DVFakeMediaPlayerBackend();
      created.add(backend);
      return backend;
    });
  }

  setUp(() {
    created = <DVFakeMediaPlayerBackend>[];
    focusBackend = DVFakeAudioFocusBackend();
    focus = DVAudioFocus(focusBackend);
    app = DVMutableLifecycleSignal<DVAppLifecycle>(DVAppLifecycle.ready);
    DVMediaBackends.reset();
    registerFakes();
  });

  tearDown(() {
    DVMediaBackends.reset();
    DV.Platform.useRenderSurface(null);
  });

  test('the controller is the box\'s, through every modifier', () {
    final DVBox<Object?> box = DVBox.video(launch);
    expect(box.controller, isA<DVMediaController>());
    expect(box.aspectRatio(16 / 9).controller, same(box.controller));
    expect(box.scrollable().controller, same(box.controller));
    expect(box.controller.source, launch);
  });

  test('a box that is not a player has no controller', () {
    expect(() => const DVBox(Text('x')).controller, throwsStateError);
  });

  testWidgets('mounting attaches one player, and the controls read its state',
      (WidgetTester tester) async {
    final DVBox<Object?> box = DVBox.video(launch);
    await tester.pumpWidget(host(box));

    expect(created, hasLength(1));
    expect(created.single.opened.single, launch);
    expect(box.controller.state.value, DVPlaybackState.loading);

    created.single.emit(const DVMediaReady(duration: Duration(minutes: 2)));
    await tester.pump();
    expect(find.byTooltip('Play'), findsOneWidget);

    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    expect(created.single.calls, contains('play'));
    // Asked, not playing: the button does not flip until the backend says.
    expect(find.byTooltip('Play'), findsOneWidget);

    created.single.emit(const DVMediaPlaying());
    await tester.pump();
    expect(find.byTooltip('Pause'), findsOneWidget);
  });

  testWidgets('leaving the page releases the player and audio focus',
      (WidgetTester tester) async {
    final DVBox<Object?> box = DVBox.video(launch);
    await tester.pumpWidget(host(box));
    created.single.emit(const DVMediaReady(duration: Duration(minutes: 2)));
    await tester.pump();
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    expect(focusBackend.held, isTrue);

    await tester.pumpWidget(host(const SizedBox()));
    await tester.pump();

    expect(created.single.disposed, isTrue);
    expect(focusBackend.held, isFalse);
    expect(focus.holder, isNull);
    expect(box.controller.state.value, DVPlaybackState.disposed);
  });

  testWidgets('a parent rebuilding the box does not start a second player',
      (WidgetTester tester) async {
    final List<DVMediaController> handles = <DVMediaController>[];
    late StateSetter rebuild;
    await tester.pumpWidget(host(StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        rebuild = setState;
        final DVBox<Object?> box = DVBox.video(launch);
        handles.add(box.controller);
        return box;
      },
    )));
    created.single.emit(const DVMediaReady(duration: Duration(minutes: 2)));
    await tester.pump();

    rebuild(() {});
    await tester.pump();

    expect(handles, hasLength(2));
    expect(created, hasLength(1));
    // The new handle reads, and drives, the player already running.
    expect(handles.last.state.value, DVPlaybackState.paused);
    await handles.last.play();
    expect(created.single.calls, contains('play'));
    // And the old one still does.
    expect(handles.first.state.value, DVPlaybackState.paused);
  });

  testWidgets('a new source replaces the player rather than adding one',
      (WidgetTester tester) async {
    DVMediaSource source = launch;
    late StateSetter rebuild;
    await tester.pumpWidget(host(StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        rebuild = setState;
        return DVBox.video(source);
      },
    )));
    rebuild(() => source = trailer);
    await tester.pump();

    expect(created, hasLength(2));
    expect(created.first.disposed, isTrue);
    expect(created.last.opened.single, trailer);
    expect(created.last.disposed, isFalse);
  });

  testWidgets('a controller the application made is played, not disposed',
      (WidgetTester tester) async {
    final DVMediaController mine =
        DVMediaController(launch, environment: DVMediaBackends.environment());
    addTearDown(mine.dispose);
    await tester.pumpWidget(host(DVBox.video(launch, controller: mine)));
    expect(created, hasLength(1));
    expect(mine.isAttached, isTrue);

    await tester.pumpWidget(host(const SizedBox()));
    // The page went; the application's player did not. A "now playing" bar
    // elsewhere keeps working.
    expect(created.single.disposed, isFalse);
    expect(mine.state.value, isNot(DVPlaybackState.disposed));
  });

  testWidgets('a target with no player bound fails where it can be read',
      (WidgetTester tester) async {
    DVMediaBackends.reset();
    registerFakes();
    DVMediaBackends.unregisterPlayer();
    final DVBox<Object?> box =
        DVBox.video(launch, poster: const DVImage.stored('posters/launch.jpg'));
    await tester.pumpWidget(host(box));
    await tester.pump();

    expect(box.controller.state.value, DVPlaybackState.failed);
    expect(box.controller.error.value, contains('no media player'));
    expect(find.byType(DVImageView), findsOneWidget);
    expect(find.byTooltip('Play'), findsNothing);
  });

  testWidgets('the terminal shows the poster and opens no player',
      (WidgetTester tester) async {
    DV.Platform.useRenderSurface(DVRenderSurface.terminal);
    final DVBox<Object?> box =
        DVBox.video(launch, poster: const DVImage.stored('posters/launch.jpg'));
    await tester.pumpWidget(host(box));
    await tester.pump();

    expect(created, isEmpty);
    expect(find.byType(DVImageView), findsOneWidget);
    expect(box.controller.state.value, DVPlaybackState.failed);
  });

  testWidgets('the audio box plays without drawing a surface',
      (WidgetTester tester) async {
    DVMediaKind? kind;
    DVMediaBackends.registerPlayer((DVMediaSource source, DVMediaKind k) {
      kind = k;
      final DVFakeMediaPlayerBackend backend = DVFakeMediaPlayerBackend();
      created.add(backend);
      return backend;
    });
    await tester.pumpWidget(host(DVBox.audio(
        const DVMediaSource.asset('assets/audio/chime.ogg'))));
    expect(kind, DVMediaKind.audio);
    expect(created, hasLength(1));
  });

  testWidgets('a widget reading a player signal rebuilds when it moves',
      (WidgetTester tester) async {
    final DVBox<Object?> box = DVBox.video(launch);
    await tester.pumpWidget(host(Column(children: <Widget>[
      SizedBox(height: 200, child: box),
      Builder(
        builder: (BuildContext context) =>
            Text('now: ${box.controller.state.watch(context).name}'),
      ),
    ])));
    expect(find.text('now: loading'), findsOneWidget);

    created.single.emit(const DVMediaReady(duration: Duration(minutes: 1)));
    await tester.pump();
    expect(find.text('now: paused'), findsOneWidget);
  });

  group('remote-control keys', () {
    test('media keys map everywhere; select and arrows only on a television',
        () {
      expect(
          DVMediaTransportKeys.actionFor(LogicalKeyboardKey.mediaPlayPause,
              television: false),
          DVTransportAction.togglePlay);
      expect(
          DVMediaTransportKeys.actionFor(LogicalKeyboardKey.mediaFastForward,
              television: false),
          DVTransportAction.seekForward);
      expect(
          DVMediaTransportKeys.actionFor(LogicalKeyboardKey.arrowRight,
              television: false),
          isNull);
      expect(
          DVMediaTransportKeys.actionFor(LogicalKeyboardKey.arrowRight,
              television: true),
          DVTransportAction.seekForward);
      expect(
          DVMediaTransportKeys.actionFor(LogicalKeyboardKey.select,
              television: true),
          DVTransportAction.togglePlay);
    });

    testWidgets('play/pause on the remote reaches the mounted player',
        (WidgetTester tester) async {
      await tester.pumpWidget(host(DVBox.video(launch)));
      created.single.emit(const DVMediaReady(duration: Duration(minutes: 2)));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pump();
      expect(created.single.calls, contains('play'));

      created.single.emit(const DVMediaPlaying());
      await tester.pump();
      created.single.calls.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
      await tester.pump();
      expect(created.single.seeks.single.$1, const Duration(seconds: 10));
    });

    testWidgets('the key goes to the player that is playing, not the newest',
        (WidgetTester tester) async {
      await tester.pumpWidget(host(Column(children: <Widget>[
        SizedBox(height: 100, child: DVBox.video(launch)),
        SizedBox(height: 100, child: DVBox.video(trailer)),
      ])));
      for (final DVFakeMediaPlayerBackend b in created) {
        b.emit(const DVMediaReady(duration: Duration(minutes: 2)));
      }
      await tester.pump();
      await tester.tap(find.byTooltip('Play').first);
      await tester.pump();
      created.first.emit(const DVMediaPlaying());
      await tester.pump();
      created.first.calls.clear();

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pump();
      expect(created.first.calls, contains('pause'));
      expect(created.last.calls, isNot(contains('play')));
    });

    testWidgets('an unmounted player stops listening for keys',
        (WidgetTester tester) async {
      await tester.pumpWidget(host(DVBox.video(launch)));
      await tester.pumpWidget(host(const SizedBox()));
      created.single.calls.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      expect(created.single.calls, isEmpty);
    });
  });

  group('DV.Platform.Media', () {
    tearDown(() {
      DVNativeBridge.unregister('permissions.request');
    });

    test('refuses capture on a target with no capture binding', () async {
      final DVCaptureSession session = DV.Platform.Media.recordAudio();
      await expectLater(session, throwsA(isA<DVCaptureUnsupported>()));
      expect(DV.Platform.Media.captureCapabilities.microphone, isFalse);
    });

    test('records through the bound backend, asking the platform permission '
        'flow', () async {
      final Directory dir = Directory.systemTemp.createTempSync('dv-media-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final List<String> asked = <String>[];
      DVNativeBridge.register('permissions.request', (Object? arguments) {
        asked.add('${(arguments as Map<Object?, Object?>)['permission']}');
        return true;
      });
      final DVFakeCaptureBackend device = DVFakeCaptureBackend();
      DVMediaBackends.registerCapture(
        capabilities: device.capabilities,
        backend: () => device,
        directory: dir.path,
      );

      final DVCaptureSession session =
          DV.Platform.Media.recordAudio(format: DVAudioFormat.opus);
      addTearDown(session.dispose);
      for (int i = 0; i < 5 && device.starts.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(asked, <String>['microphone']);
      expect(device.starts.single.$2, startsWith(dir.path));
    });
  });
}
