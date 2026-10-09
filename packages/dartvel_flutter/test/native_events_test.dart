// The JSON a native player or camera queues, read into the events the
// controllers act on.
//
// The quiet failures: a position read as seconds where it was milliseconds,
// a seek generation dropped so a stale report moves the scrubber back, an
// unknown event crashing the poll loop and freezing every player, and a
// capability report read as "has a camera" when the device said nothing.
@TestOn('vm')
library;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/media/native_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('player events', () {
    test('every shape', () {
      final List<DVMediaBackendEvent> events = dvParseMediaEvents('['
          '{"type":"ready","durationMs":125000},'
          '{"type":"playing"},{"type":"paused"},{"type":"buffering"},'
          '{"type":"completed"},'
          '{"type":"position","ms":1500,"seek":3},'
          '{"type":"buffered","ms":9000},'
          '{"type":"seekCompleted","gen":3,"ms":1400},'
          '{"type":"videoSize","width":1920,"height":1080},'
          '{"type":"pip","active":true},'
          '{"type":"failed","message":"ERROR_CODE_IO_NETWORK: gone"}'
          ']');
      expect(events, hasLength(11));
      expect((events[0] as DVMediaReady).duration,
          const Duration(seconds: 125));
      expect(events[1], isA<DVMediaPlaying>());
      expect(events[2], isA<DVMediaPaused>());
      expect(events[3], isA<DVMediaBuffering>());
      expect(events[4], isA<DVMediaCompleted>());
      final DVMediaPosition position = events[5] as DVMediaPosition;
      expect(position.position, const Duration(milliseconds: 1500));
      expect(position.seek, 3);
      expect((events[6] as DVMediaBuffered).ranges,
          const <DVRange>[DVRange(Duration.zero, Duration(seconds: 9))]);
      final DVMediaSeekCompleted seek = events[7] as DVMediaSeekCompleted;
      expect(seek.generation, 3);
      expect(seek.position, const Duration(milliseconds: 1400));
      final DVMediaVideoSize size = events[8] as DVMediaVideoSize;
      expect((size.width, size.height), (1920, 1080));
      expect((events[9] as DVMediaPictureInPictureChanged).active, isTrue);
      expect((events[10] as DVMediaFailed).message, contains('gone'));
    });

    test('nothing, garbage and unknown events give nothing, not a throw', () {
      expect(dvParseMediaEvents(null), isEmpty);
      expect(dvParseMediaEvents(''), isEmpty);
      expect(dvParseMediaEvents('not json'), isEmpty);
      expect(dvParseMediaEvents('[{"type":"somethingNew"},{"type":"playing"}]'),
          <Matcher>[isA<DVMediaPlaying>()]);
      expect(dvParseMediaEvent('{"type":"position"}'), isNull);
    });
  });

  group('camera events', () {
    test('every shape', () {
      final List<DVCameraEvent> events = dvParseCameraEvents('['
          '{"type":"opened","lens":"front","width":720,"height":1280,"rotation":90},'
          '{"type":"closed"},'
          '{"type":"photo","path":"/data/x.jpg"},'
          '{"type":"recordingStarted"},'
          '{"type":"recordingStopped","ms":3200},'
          '{"type":"disconnected"},'
          '{"type":"failed","message":"busy"}'
          ']');
      final DVCameraOpened opened = events[0] as DVCameraOpened;
      expect(opened.lens, DVCameraLens.front);
      expect((opened.width, opened.height), (720, 1280));
      expect(events[1], isA<DVCameraClosed>());
      expect((events[2] as DVCameraPhotoTaken).path, '/data/x.jpg');
      expect(events[3], isA<DVCameraRecordingStarted>());
      expect((events[4] as DVCameraRecordingStopped).duration,
          const Duration(milliseconds: 3200));
      expect(events[5], isA<DVCameraDisconnected>());
      expect((events[6] as DVCameraFailed).message, 'busy');
    });

    test('a lens name the runtime does not know is not guessed', () {
      expect(dvParseCameraEvent('{"type":"opened","lens":"periscope"}'), isNull);
    });
  });

  group('lock-screen commands', () {
    test('every action, and seekTo carries its position', () {
      expect(dvParseMediaCommands('[{"action":"play"},{"action":"pause"},'
              '{"action":"togglePlay"},{"action":"stop"},'
              '{"action":"seekForward"},{"action":"seekBackward"},'
              '{"action":"seekTo","ms":42000}]'),
          const <DVMediaCommand>[
            DVMediaCommand(DVTransportAction.play),
            DVMediaCommand(DVTransportAction.pause),
            DVMediaCommand(DVTransportAction.togglePlay),
            DVMediaCommand(DVTransportAction.stop),
            DVMediaCommand(DVTransportAction.seekForward),
            DVMediaCommand(DVTransportAction.seekBackward),
            DVMediaCommand(DVTransportAction.seekTo,
                position: Duration(seconds: 42)),
          ]);
    });

    test('a seekTo with no position is dropped', () {
      expect(dvParseMediaCommand('{"action":"seekTo"}'), isNull);
    });
  });

  group('camera capabilities', () {
    test('what the device reported', () {
      final DVCameraCapabilities can = dvParseCameraCapabilities(
          '{"lenses":["back","front"],"flash":true,"torch":true,'
          '"qualities":["sd480","hd720"]}');
      expect(can.lenses, <DVCameraLens>{DVCameraLens.back, DVCameraLens.front});
      expect(can.flash, isTrue);
      expect(can.torch, isTrue);
      expect(can.photo, isTrue);
      expect(can.preview, isTrue);
      expect(can.video, isTrue);
      expect(can.videoQualities,
          <DVVideoQuality>{DVVideoQuality.sd480, DVVideoQuality.hd720});
    });

    test('no lenses, an error or nothing is no camera', () {
      expect(dvParseCameraCapabilities('{"lenses":[]}').available, isFalse);
      expect(dvParseCameraCapabilities('{"error":"denied"}').available, isFalse);
      expect(dvParseCameraCapabilities(null).available, isFalse);
      expect(dvParseCameraCapabilities('{}').photo, isFalse);
    });

    test('no recording profiles means no video', () {
      expect(
          dvParseCameraCapabilities('{"lenses":["back"],"qualities":[]}').video,
          isFalse);
    });
  });
}
