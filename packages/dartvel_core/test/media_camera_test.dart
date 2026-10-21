// The camera behind DVBox.camera.
//
// The failures that matter are the ones people read as spying: the device
// open while the application is in the background, open after the page that
// showed it has gone, or "ready" before the device has confirmed anything.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Future<void> pump() async {
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(.zero);
  }
}

final class _MemoryFiles implements DVCaptureFiles {
  final Set<String> reserved = <String>{};
  final Set<String> discarded = <String>{};
  int _next = 0;

  @override
  Future<String> reserve(String extension) async {
    final String path = '/private/capture-${_next++}.$extension';
    reserved.add(path);
    return path;
  }

  @override
  Future<int> seal(String path) async => 2048;

  @override
  Future<void> discard(String path) async => discarded.add(path);
}

void main() {
  late DVFakeCameraBackend backend;
  late DVMutableLifecycleSignal<DVAppLifecycle> app;
  late _MemoryFiles files;
  late List<String> codes;

  DVCameraController camera({
    Set<String> granted = const <String>{'camera', 'microphone'},
    DVCameraBackend? using,
    DVCameraLens lens = DVCameraLens.back,
    String? device,
  }) {
    final DVCameraController c = DVCameraController(
      using ?? backend,
      lens: lens,
      device: device,
      environment: DVCameraEnvironment(
        permissions: DVFakeCapturePermissions(granted),
        files: files,
        lifecycle: app,
        timers: DVFakeMediaTimers(),
        diagnostics: (String code, String message) => codes.add(code),
      ),
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    backend = DVFakeCameraBackend();
    app = DVMutableLifecycleSignal<DVAppLifecycle>(DVAppLifecycle.ready);
    files = _MemoryFiles();
    codes = <String>[];
  });

  test('is not ready until the device confirms it opened', () async {
    final DVFakeCameraBackend slow = DVFakeCameraBackend(autoConfirm: false);
    final DVCameraController c = camera(using: slow);
    unawaited(c.open());
    await pump();
    expect(slow.opened, <DVCameraLens>[DVCameraLens.back]);
    expect(c.state.value, DVCameraState.opening);
    slow.emit(const DVCameraOpened(DVCameraLens.back, width: 640, height: 480));
    await pump();
    expect(c.state.value, DVCameraState.ready);
    expect(c.previewSize.value, (640, 480));
  });

  test('a refusal is typed, logged, and opens nothing', () async {
    final DVCameraController c = camera(granted: const <String>{});
    await expectLater(c.open(), throwsA(isA<DVCapturePermissionRefused>()));
    expect(c.state.value, DVCameraState.refused);
    expect(backend.opened, isEmpty);
    expect(codes, <String>['DV-MEDIA-104']);
  });

  test('a target with no camera refuses before asking permission', () async {
    final DVCameraController c = camera(
        using: DVFakeCameraBackend(capabilities: DVCameraCapabilities.none));
    await expectLater(c.open(), throwsA(isA<DVCameraUnavailable>()));
    expect(c.state.value, DVCameraState.failed);
  });

  test('backgrounding closes the device; coming back reopens it', () async {
    final DVCameraController c = camera();
    await c.open();
    expect(backend.isOpen, isTrue);

    app.set(DVAppLifecycle.backgrounded);
    await pump();
    expect(backend.isOpen, isFalse);
    expect(c.state.value, DVCameraState.paused);

    app.set(DVAppLifecycle.ready);
    await pump();
    expect(backend.isOpen, isTrue);
    expect(c.state.value, DVCameraState.ready);
  });

  test('switching lens reopens on the other camera', () async {
    final DVCameraController c = camera();
    await c.open();
    await c.switchLens();
    expect(backend.opened, <DVCameraLens>[DVCameraLens.back, DVCameraLens.front]);
    expect(c.lens.value, DVCameraLens.front);
    expect(c.state.value, DVCameraState.ready);
    await expectLater(c.switchLens(DVCameraLens.external),
        throwsA(isA<DVCameraUnavailable>()));
  });

  test('a lens the device lacks falls back to one it has', () async {
    final DVCameraController c = camera(
      using: DVFakeCameraBackend(
          capabilities: const DVCameraCapabilities(
              lenses: <DVCameraLens>{DVCameraLens.front}, photo: true)),
    );
    await c.open();
    expect(c.lens.value, DVCameraLens.front);
  });

  test('a photo is a private JPEG, taken with the chosen flash', () async {
    final DVCameraController c = camera();
    await c.open();
    c.setFlash(DVFlashMode.on);
    final DVFile photo = await c.takePhoto();
    expect(photo.mimeType, 'image/jpeg');
    expect(files.reserved, contains(photo.path));
    expect(backend.flashes, <DVFlashMode>[DVFlashMode.on]);
    expect(c.state.value, DVCameraState.ready);
  });

  test('a failed photo deletes its file and reports the failure', () async {
    final DVFakeCameraBackend manual = DVFakeCameraBackend(autoConfirm: false);
    final DVCameraController c = camera(using: manual);
    unawaited(c.open());
    await pump();
    manual.emit(const DVCameraOpened(DVCameraLens.back));
    await pump();
    final Future<DVFile> photo = c.takePhoto();
    await pump();
    manual.emit(const DVCameraFailed('sensor error'));
    await expectLater(photo, throwsA(isA<DVCaptureFailure>()));
    expect(files.discarded, hasLength(1));
    expect(c.error.value, 'sensor error');
  });

  test('nothing is taken before the camera is ready', () async {
    final DVCameraController c = camera();
    expect(c.takePhoto, throwsA(isA<DVCameraUnavailable>()));
  });

  test('torch and flash refuse on hardware without them', () async {
    final DVCameraController c = camera(
      using: DVFakeCameraBackend(
          capabilities: const DVCameraCapabilities(
              lenses: <DVCameraLens>{DVCameraLens.front}, photo: true)),
    );
    await c.open();
    expect(() => c.setFlash(DVFlashMode.on), throwsA(isA<DVCameraUnavailable>()));
    await expectLater(c.setTorch(true), throwsA(isA<DVCameraUnavailable>()));
  });

  test('a video recording is a capture session with a private file', () async {
    final DVCameraController c = camera();
    await c.open();
    final DVCaptureSession recording = c.recordVideo();
    await pump();
    expect(recording.capturing.value, isTrue);
    expect(c.state.value, DVCameraState.recording);
    await recording.stop();
    final DVFile clip = await recording;
    expect(clip.mimeType, 'video/mp4');
    expect(clip.duration, const Duration(seconds: 3));
    expect(files.reserved, contains(clip.path));
    expect(c.state.value, DVCameraState.ready);
  });

  test('a recording without the microphone permission is refused', () async {
    final DVCameraController c =
        camera(granted: const <String>{'camera'});
    await c.open();
    final DVCaptureSession recording = c.recordVideo();
    await expectLater(recording, throwsA(isA<DVCapturePermissionRefused>()));
    expect(backend.calls, isNot(contains('record')));
  });

  test('disposing closes the device and aborts a recording', () async {
    final DVCameraController c = camera();
    await c.open();
    final DVCaptureSession recording = c.recordVideo();
    await pump();
    await c.dispose();
    expect(backend.isOpen, isFalse);
    expect(backend.disposed, isTrue);
    await expectLater(recording, throwsA(isA<DVCaptureInterrupted>()));
    expect(c.state.value, DVCameraState.disposed);
  });

  group('choosing a device', () {
    test('opens the device it was given, not the first of its lens', () async {
      backend = DVFakeCameraBackend(
        capabilities: const DVCameraCapabilities(
            lenses: <DVCameraLens>{DVCameraLens.external}, preview: true),
        cameras: const <DVCameraDevice>[
          DVCameraDevice(id: '/dev/video0', name: 'Built-in', lens: DVCameraLens.external),
          DVCameraDevice(id: '/dev/video2', name: 'Stage cam', lens: DVCameraLens.external),
        ],
      );
      final DVCameraController c =
          camera(lens: DVCameraLens.external, device: '/dev/video2');
      await c.open();
      expect(backend.calls, contains('open:external@/dev/video2'));
      expect(c.device, '/dev/video2');
    });

    test('lists what the backend reports, in its order', () async {
      backend = DVFakeCameraBackend(cameras: const <DVCameraDevice>[
        DVCameraDevice(id: 'a', name: 'Front', lens: DVCameraLens.front),
        DVCameraDevice(id: 's', name: 'Entire screen', lens: DVCameraLens.screen),
      ]);
      final DVCameraController c = camera();
      expect((await c.devices()).map((DVCameraDevice d) => d.name),
          <String>['Front', 'Entire screen']);
    });

    test('the screen opens like a camera where the target can share it',
        () async {
      backend = DVFakeCameraBackend(
        capabilities: const DVCameraCapabilities(
            lenses: <DVCameraLens>{DVCameraLens.screen}, preview: true, video: true),
      );
      final DVCameraController c =
          camera(lens: DVCameraLens.screen, granted: const <String>{'screen'});
      await c.open();
      expect(c.state.value, DVCameraState.ready);
      expect(backend.calls, contains('open:screen'));
    });

    test('a screen asks for screen permission, not the camera', () async {
      backend = DVFakeCameraBackend(
        capabilities: const DVCameraCapabilities(
            lenses: <DVCameraLens>{DVCameraLens.screen}, preview: true),
      );
      final DVCameraController c =
          camera(lens: DVCameraLens.screen, granted: const <String>{'camera'});
      await expectLater(c.open(), throwsA(isA<DVCapturePermissionRefused>()));
      expect(backend.calls.where((String call) => call.startsWith('open')), isEmpty);
    });
  
    test('switching lens never lands on the screen, and drops the device',
        () async {
      backend = DVFakeCameraBackend(
        capabilities: const DVCameraCapabilities(lenses: <DVCameraLens>{
          DVCameraLens.back,
          DVCameraLens.screen,
          DVCameraLens.front,
        }, preview: true),
      );
      final DVCameraController c = camera(device: 'cam-1');
      await c.open();
      await c.switchLens();
      expect(c.lens.value, DVCameraLens.front);
      expect(c.device, isNull);
      await c.switchLens();
      expect(c.lens.value, DVCameraLens.back);
      expect(backend.calls.where((String call) => call == 'open:screen'), isEmpty);
    });
  });
}
