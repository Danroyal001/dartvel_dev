// Capture: `DV.Platform.Media.recordAudio(...)` / `recordVideo(...)`.
//
// Capture fails quietly in ways that matter more than playback does. A
// microphone still recording after the application went to the background, a
// "recording" indicator that disagrees with what the device is actually doing,
// a session left running after the page that started it was closed, a recording
// written somewhere every other account on the machine can read -- none of
// those throw. These tests are about those.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:test/test.dart';

Future<void> pump() => Future<void>.delayed(Duration.zero);

/// How a real device writes: into the file, or by replacing it.
Future<void> writeRecording(String path, List<int> bytes, bool replace) async {
  final File file = File(path);
  if (replace) file.deleteSync();
  file.writeAsBytesSync(bytes, flush: true);
}

void main() {
  late Directory root;
  late DVFakeCaptureBackend backend;
  late DVFakeCapturePermissions permissions;
  late DVMutableLifecycleSignal<DVAppLifecycle> app;
  late DVFakeMediaTimers timers;
  late List<String> codes;
  late DVMediaCapture capture;

  late int created;

  DVMediaCapture build() => DVMediaCapture(
        capabilities: backend.capabilities,
        backend: () {
          created++;
          return backend;
        },
        permissions: permissions,
        files: DVPrivateCaptureFiles(root.path),
        lifecycle: app,
        timers: timers,
        diagnostics: (String code, String message) => codes.add(code),
      );

  setUp(() {
    root = Directory.systemTemp.createTempSync('dv-capture-');
    backend = DVFakeCaptureBackend(writeFile: writeRecording);
    permissions = DVFakeCapturePermissions(<String>{'microphone', 'camera'});
    app = DVMutableLifecycleSignal<DVAppLifecycle>(DVAppLifecycle.ready);
    timers = DVFakeMediaTimers();
    codes = <String>[];
    created = 0;
    capture = build();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Starts an audio recording and lets the backend confirm it.
  Future<DVCaptureSession> recording({
    Duration maxDuration = const Duration(minutes: 5),
  }) async {
    final DVCaptureSession session = capture.recordAudio(
      format: DVAudioFormat.opus,
      maxDuration: maxDuration,
    );
    addTearDown(session.dispose);
    await pump();
    await pump();
    backend.confirmStarted();
    await pump();
    return session;
  }

  group('permission', () {
    test('a refusal is typed, reported, and never starts the device', () async {
      permissions = DVFakeCapturePermissions(<String>{});
      capture = build();
      final DVCaptureSession session =
          capture.recordAudio(format: DVAudioFormat.opus);
      addTearDown(session.dispose);

      await expectLater(
        session,
        throwsA(isA<DVCapturePermissionRefused>()
            .having((e) => e.permission, 'permission', 'microphone')),
      );
      expect(session.state.value, DVCaptureState.refused);
      expect(session.capturing.value, isFalse);
      expect(backend.starts, isEmpty);
      expect(codes, <String>['DV-MEDIA-104']);
      // The device was not even constructed.
      expect(created, 0);
    });

    test('video asks for the camera and the microphone', () async {
      final DVCaptureSession session =
          capture.recordVideo(quality: DVVideoQuality.hd720);
      addTearDown(session.dispose);
      await pump();
      await pump();
      expect(permissions.asked, <String>['camera', 'microphone']);
    });

    test('a capability the target lacks is refused before anyone is asked',
        () async {
      final DVCaptureSession session =
          capture.recordAudio(format: DVAudioFormat.aac);
      addTearDown(session.dispose);
      await expectLater(session, throwsA(isA<DVCaptureUnsupported>()));
      // No prompt for something that could not have worked.
      expect(permissions.asked, isEmpty);
      expect(backend.starts, isEmpty);
    });

    test('the permission being revoked mid-recording stops the device and '
        'says so', () async {
      final DVCaptureSession session = await recording();
      backend.revokePermission();
      await pump();
      expect(backend.stops, 1);
      await backend.confirmStopped(const Duration(seconds: 4));
      await expectLater(
        session,
        throwsA(isA<DVCaptureInterrupted>().having((e) => e.reason, 'reason',
            DVCaptureInterruption.permissionRevoked)),
      );
      expect(session.capturing.value, isFalse);
    });
  });

  group('the indicator', () {
    test('is off until the device confirms, on while recording, and stays on '
        'until the device confirms it stopped', () async {
      final DVCaptureSession session =
          capture.recordAudio(format: DVAudioFormat.opus);
      addTearDown(session.dispose);
      await pump();
      await pump();
      expect(backend.starts, hasLength(1));
      // Asked to start. Not yet recording.
      expect(session.capturing.value, isFalse);

      backend.confirmStarted();
      await pump();
      expect(session.capturing.value, isTrue);
      expect(session.state.value, DVCaptureState.recording);

      final Future<void> stopping = session.stop();
      await pump();
      // Asked to stop. The microphone is still open until the device says.
      expect(session.capturing.value, isTrue);
      expect(session.state.value, DVCaptureState.stopping);

      await backend.confirmStopped(const Duration(seconds: 3));
      await stopping;
      expect(session.capturing.value, isFalse);
      expect(session.state.value, DVCaptureState.completed);
    });

    test('goes off when the device stops on its own', () async {
      final DVCaptureSession session = await recording();
      backend.loseDevice();
      await pump();
      await backend.confirmStopped(const Duration(seconds: 1));
      await expectLater(
        session,
        throwsA(isA<DVCaptureInterrupted>().having(
            (e) => e.reason, 'reason', DVCaptureInterruption.deviceLost)),
      );
      expect(session.capturing.value, isFalse);
    });

    test('goes off when the device fails', () async {
      final DVCaptureSession session = await recording();
      backend.fail('encoder refused the stream');
      await expectLater(session, throwsA(isA<DVCaptureFailure>()));
      expect(session.capturing.value, isFalse);
      expect(session.state.value, DVCaptureState.failed);
    });
  });

  group('the recording', () {
    test('comes back as a DVFile the application alone can read', () async {
      final DVCaptureSession session = await recording();
      unawaited(session.stop());
      await pump();
      await backend.confirmStopped(const Duration(seconds: 3));
      final DVFile file = await session;

      expect(file.mimeType, 'audio/ogg');
      expect(file.path, endsWith('.ogg'));
      expect(File(file.path).parent.path, root.path);
      expect(file.sizeBytes, backend.bytesWritten);
      expect(file.duration, const Duration(seconds: 3));
      // Finishing released the device; nothing waits for a dispose.
      expect(backend.disposed, isTrue);

      if (!Platform.isWindows) {
        expect(File(file.path).statSync().modeString(), 'rw-------');
        expect(root.statSync().modeString(), 'rwx------');
      }
    }, testOn: '!windows');

    test('stays private when the device replaced the file it was given',
        () async {
      backend =
          DVFakeCaptureBackend(replaceFile: true, writeFile: writeRecording);
      capture = build();
      final DVCaptureSession session = await recording();
      unawaited(session.stop());
      await pump();
      await backend.confirmStopped(const Duration(seconds: 1));
      final DVFile file = await session;
      expect(File(file.path).statSync().modeString(), 'rw-------');
    }, testOn: '!windows');

    test('is reserved private before the device writes a byte', () async {
      final DVCaptureSession session =
          capture.recordAudio(format: DVAudioFormat.opus);
      addTearDown(session.dispose);
      await pump();
      await pump();
      final String path = backend.starts.single.$2;
      expect(File(path).existsSync(), isTrue);
      expect(File(path).statSync().modeString(), 'rw-------');
    }, testOn: '!windows');

    test('stops itself at maxDuration and completes normally', () async {
      final DVCaptureSession session =
          await recording(maxDuration: const Duration(seconds: 30));
      timers.elapse(const Duration(seconds: 29));
      expect(backend.stops, 0);
      timers.elapse(const Duration(seconds: 1));
      expect(backend.stops, 1);
      await backend.confirmStopped(const Duration(seconds: 30));
      final DVFile file = await session;
      expect(file.duration, const Duration(seconds: 30));
      expect(session.state.value, DVCaptureState.completed);
    });
  });

  group('lifecycle', () {
    test('backgrounding stops the device and hands back what was recorded as '
        'an interruption, not a success', () async {
      final DVCaptureSession session = await recording();
      app.set(DVAppLifecycle.backgrounded);
      await pump();
      expect(backend.stops, 1);
      // Still on until confirmed.
      expect(session.capturing.value, isTrue);

      await backend.confirmStopped(const Duration(seconds: 2));
      final DVCaptureInterrupted interrupted =
          await session.then<DVCaptureInterrupted>(
        (_) => fail('an interrupted recording is not a success'),
        onError: (Object e) => e as DVCaptureInterrupted,
      );
      expect(interrupted.reason, DVCaptureInterruption.backgrounded);
      expect(interrupted.partial, isNotNull);
      expect(File(interrupted.partial!.path).existsSync(), isTrue);
      expect(session.capturing.value, isFalse);
      expect(session.state.value, DVCaptureState.interrupted);
    });

    test('an application already in the background never opens the device',
        () async {
      app.set(DVAppLifecycle.backgrounded);
      final DVCaptureSession session =
          capture.recordAudio(format: DVAudioFormat.opus);
      addTearDown(session.dispose);
      await expectLater(session, throwsA(isA<DVCaptureInterrupted>()));
      expect(backend.starts, isEmpty);
    });

    test('disposing mid-recording releases the device, discards the partial '
        'file and stops observing', () async {
      final DVCaptureSession session = await recording();
      final String path = backend.starts.single.$2;
      session.ignore();

      await session.dispose();
      expect(backend.aborts, 1);
      expect(backend.disposed, isTrue);
      expect(session.capturing.value, isFalse);
      expect(session.state.value, DVCaptureState.disposed);
      expect(File(path).existsSync(), isFalse);
      expect(timers.pending, 0);

      app.set(DVAppLifecycle.backgrounded);
      await pump();
      expect(backend.stops, 0);
    });

    test('a second recording while one runs is refused', () async {
      await recording();
      final DVCaptureSession second =
          capture.recordAudio(format: DVAudioFormat.opus);
      addTearDown(second.dispose);
      await expectLater(second, throwsA(isA<DVCaptureBusy>()));
    });

    test('a finished recording frees the device for the next one', () async {
      final DVCaptureSession first = await recording();
      unawaited(first.stop());
      await pump();
      await backend.confirmStopped(const Duration(seconds: 1));
      await first;

      final DVCaptureSession second =
          capture.recordAudio(format: DVAudioFormat.opus);
      addTearDown(second.dispose);
      await pump();
      await pump();
      expect(backend.starts, hasLength(2));
    });
  });

  test('the capability report is the backend\'s, not an assumption', () {
    expect(capture.capabilities.audioFormats, <DVAudioFormat>{
      DVAudioFormat.opus,
      DVAudioFormat.wav,
    });
    expect(capture.capabilities.camera, isTrue);
  });
}
