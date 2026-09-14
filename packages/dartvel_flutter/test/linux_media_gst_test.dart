// The Linux player and recorder: GStreamer over dart:ffi, no platform channel.
//
// These play and record real media through the GStreamer installed on the
// machine running them. The pipelines end in fakesink and start at
// audiotestsrc, because a CI runner has no speaker and no microphone -- but
// everything between is the decoder, the clock, the encoder and the muxer
// the application gets, so a stalled position, a seek that does not land or a
// recording that is not a playable file fails here.
@TestOn('linux')
library;

import 'dart:async';
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_media_gst.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> until(bool Function() condition,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final DateTime end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

const String testSource = 'audiotestsrc is-live=true wave=sine';

void main() {
  final bool available = DVGStreamer.load();
  final String? skip = available ? null : 'GStreamer is not installed here';

  late Directory dir;
  late String tone;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('dv-gst-');
    if (!available) return;
    tone = '${dir.path}/tone.ogg';
    // 130 buffers of 1024 samples at 44.1 kHz: 3.02 seconds.
    await DVGStreamer.runToEos('audiotestsrc num-buffers=130 ! audioconvert ! '
        'vorbisenc ! oggmux ! filesink location=$tone');
  });

  tearDownAll(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  DVMediaController controllerFor(DVMediaSource source) {
    final DVMediaController c = DVMediaController(
      source,
      environment: DVMediaEnvironment(
        lifecycle:
            DVMutableLifecycleSignal<DVAppLifecycle>(DVAppLifecycle.ready),
        focus: DVAudioFocus(),
        diagnostics: (String code, String message) {},
      ),
    );
    addTearDown(c.dispose);
    return c;
  }

  DVGStreamerPlayer player() =>
      DVGStreamerPlayer(audioSink: 'fakesink', videoSink: 'fakesink');

  group('playback', () {
    test('reports what this machine can play, not what it hopes', () {
      final DVMediaBackendCapabilities caps = DVGStreamerPlayer.probe();
      expect(
        caps.adaptiveStreaming,
        (DVGStreamer.hasElement('hlsdemux') ||
                DVGStreamer.hasElement('hlsdemux2')) &&
            (DVGStreamer.hasElement('dashdemux') ||
                DVGStreamer.hasElement('dashdemux2')),
      );
      // Frames are not drawn into Flutter by this backend yet.
      expect(caps.video, isFalse);
    }, skip: skip);

    test('loads with the real duration, plays, advances and completes',
        () async {
      final DVGStreamerPlayer backend = player();
      final DVMediaController c = controllerFor(DVMediaSource.file(tone));
      await c.attach(backend);
      await until(() => c.state.value == DVPlaybackState.paused);
      expect(c.duration.value.inMilliseconds, closeTo(3020, 60));

      await c.play();
      await until(() => c.state.value == DVPlaybackState.playing);
      await until(() => c.position.value > const Duration(milliseconds: 400));
      // Real time, not as fast as the decoder can go.
      expect(c.position.value, lessThan(const Duration(seconds: 2)));

      await until(() => c.state.value == DVPlaybackState.completed);
      await c.dispose();
      expect(backend.isReleased, isTrue);
    }, skip: skip);

    test('a paused player stops advancing', () async {
      final DVMediaController c = controllerFor(DVMediaSource.file(tone));
      await c.attach(player());
      await until(() => c.state.value == DVPlaybackState.paused);
      await c.play();
      await until(() => c.position.value > const Duration(milliseconds: 300));
      await c.pause();
      await until(() => c.state.value == DVPlaybackState.paused);
      final Duration held = c.position.value;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
          (c.position.value - held).inMilliseconds.abs(), lessThan(60));
    }, skip: skip);

    test('a seek lands where it was asked, and nothing earlier drags it back',
        () async {
      final DVMediaController c = controllerFor(DVMediaSource.file(tone));
      await c.attach(player());
      await until(() => c.state.value == DVPlaybackState.paused);
      await c.play();
      await until(() => c.position.value > const Duration(milliseconds: 200));

      final List<Duration> seen = <Duration>[];
      final StreamSubscription<Duration> sub = c.position.listen(seen.add);
      addTearDown(sub.cancel);
      await c.seek(const Duration(seconds: 2));
      expect(c.position.value.inMilliseconds, closeTo(2000, 100));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(seen.where((Duration d) => d < const Duration(milliseconds: 1900)),
          isEmpty,
          reason: 'a report from before the seek moved the position back');
      // And it moves on from there: a scrubber that stopped at the seek
      // target looks exactly like one that landed.
      expect(c.position.value, greaterThan(const Duration(milliseconds: 2150)),
          reason: 'the position stopped updating after the seek');
    }, skip: skip);

    test('a player that failed never reports playing when asked to play',
        () async {
      final DVGStreamerPlayer backend = player();
      final List<DVMediaBackendEvent> events = <DVMediaBackendEvent>[];
      final StreamSubscription<DVMediaBackendEvent> sub =
          backend.events.listen(events.add);
      addTearDown(sub.cancel);
      addTearDown(backend.dispose);
      await backend.open(DVMediaSource.file('${dir.path}/missing.ogg'));
      await until(() => events.any((DVMediaBackendEvent e) => e is DVMediaFailed));
      await backend.play();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(events.whereType<DVMediaPlaying>(), isEmpty);
    }, skip: skip);

    test('a file that is not there fails with the decoder\'s reason', () async {
      final DVMediaController c =
          controllerFor(DVMediaSource.file('${dir.path}/missing.ogg'));
      await c.attach(player());
      await until(() => c.state.value == DVPlaybackState.failed);
      expect(c.error.value, isNotEmpty);
    }, skip: skip);

    test('with no audio output installed it fails instead of playing into '
        'nothing', () async {
      final DVMediaController c = controllerFor(DVMediaSource.file(tone));
      await c.attach(DVGStreamerPlayer(audioSink: 'dvnosuchsink'));
      await until(() => c.state.value == DVPlaybackState.failed);
      expect(c.error.value, contains('dvnosuchsink'));
    }, skip: skip);

    test('disposing stops polling the bus', () async {
      final DVGStreamerPlayer backend = player();
      final DVMediaController c = controllerFor(DVMediaSource.file(tone));
      await c.attach(backend);
      await until(() => c.state.value == DVPlaybackState.paused);
      expect(backend.isPolling, isTrue);
      await c.dispose();
      expect(backend.isPolling, isFalse);
      expect(backend.isReleased, isTrue);
    }, skip: skip);
  });

  group('capture', () {
    DVMediaCapture captureWith({String source = testSource}) => DVMediaCapture(
          capabilities: DVGStreamerCapture.probe(audioSource: source),
          backend: () => DVGStreamerCapture(audioSource: source),
          permissions: DVFakeCapturePermissions(<String>{'microphone'}),
          files: DVPrivateCaptureFiles('${dir.path}/captures'),
          lifecycle:
              DVMutableLifecycleSignal<DVAppLifecycle>(DVAppLifecycle.ready),
          diagnostics: (String code, String message) {},
        );

    test('the microphone report matches the elements installed', () {
      expect(
        DVGStreamerCapture.probe().microphone,
        <String>['pipewiresrc', 'pulsesrc', 'alsasrc', 'autoaudiosrc']
            .any(DVGStreamer.hasElement),
      );
      expect(DVGStreamerCapture.probe().camera, isFalse);
    }, skip: skip);

    test('records a real Opus file, private, that plays back', () async {
      final DVCaptureSession session =
          captureWith().recordAudio(format: DVAudioFormat.opus);
      addTearDown(session.dispose);
      await until(() => session.capturing.value);
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      unawaited(session.stop());
      final DVFile file = await session;

      expect(session.capturing.value, isFalse);
      expect(File(file.path).statSync().modeString(), 'rw-------');
      expect(file.sizeBytes, greaterThan(1000));
      expect(file.duration!.inMilliseconds, closeTo(1000, 400));

      // Finalised, not just stopped: the muxer wrote its last page, flagged
      // end-of-stream. A stream cut off by tearing the pipeline down still
      // decodes -- Ogg is forgiving -- so playing it back cannot tell.
      final List<int> bytes = File(file.path).readAsBytesSync();
      int last = -1;
      for (int i = bytes.length - 27; i >= 0; i--) {
        if (bytes[i] == 0x4F &&
            bytes[i + 1] == 0x67 &&
            bytes[i + 2] == 0x67 &&
            bytes[i + 3] == 0x53) {
          last = i;
          break;
        }
      }
      expect(last, isNonNegative, reason: 'no Ogg page in the recording');
      expect(bytes[last + 5] & 0x04, 0x04,
          reason: 'the last Ogg page is not flagged end-of-stream');

      final DVMediaController c = controllerFor(DVMediaSource.file(file.path));
      await c.attach(player());
      await until(() => c.state.value == DVPlaybackState.paused);
      expect(c.duration.value.inMilliseconds, closeTo(1000, 400));
    }, skip: skip);

    test('maxDuration stops a real recording', () async {
      final DVCaptureSession session = captureWith().recordAudio(
        format: DVAudioFormat.opus,
        maxDuration: const Duration(milliseconds: 700),
      );
      addTearDown(session.dispose);
      final DVFile file = await session.timeout(const Duration(seconds: 10));
      expect(file.duration!.inMilliseconds, closeTo(700, 300));
    }, skip: skip);

    test('disposing mid-recording closes the source and leaves no file',
        () async {
      final DVCaptureSession session =
          captureWith().recordAudio(format: DVAudioFormat.opus);
      await until(() => session.capturing.value);
      final List<File> before = Directory('${dir.path}/captures')
          .listSync()
          .whereType<File>()
          .toList();
      await session.dispose();
      expect(session.capturing.value, isFalse);
      final List<String> after = Directory('${dir.path}/captures')
          .listSync()
          .map((FileSystemEntity e) => e.path)
          .toList();
      for (final File f in before) {
        if (f.path.endsWith('.ogg') && !after.contains(f.path)) return;
      }
      fail('the partial recording was left behind: $after');
    }, skip: skip);

    test('a format this machine cannot encode is refused up front', () async {
      final DVCaptureSession session =
          captureWith().recordAudio(format: DVAudioFormat.aac);
      addTearDown(session.dispose);
      final bool aac = <String>['avenc_aac', 'voaacenc', 'fdkaacenc']
              .any(DVGStreamer.hasElement) &&
          DVGStreamer.hasElement('mp4mux');
      if (aac) return;
      await expectLater(session, throwsA(isA<DVCaptureUnsupported>()));
    }, skip: skip);
  });
}
