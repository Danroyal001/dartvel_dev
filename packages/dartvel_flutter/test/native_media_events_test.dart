// The JSON a native player, camera or now-playing surface queues for Dart to
// poll. One shape for every native backend (Apple through FFI, Android
// through JNI), parsed once.
//
// The silent failures: a duration in seconds read as milliseconds, a seek
// generation dropped so a stale position drags the scrubber back, and an
// unknown event turned into a crash instead of being ignored.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/media/native_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('player events', () {
    test('ready carries its duration in milliseconds', () {
      final DVMediaBackendEvent? event =
          dvParseMediaEvent('{"type":"ready","durationMs":125500}');
      expect(event, isA<DVMediaReady>());
      expect((event! as DVMediaReady).duration,
          const Duration(milliseconds: 125500));
    });

    test('a live stream has no duration', () {
      final DVMediaReady ready =
          dvParseMediaEvent('{"type":"ready"}')! as DVMediaReady;
      expect(ready.duration, Duration.zero);
    });

    test('a position keeps the seek generation it was measured under', () {
      final DVMediaPosition p = dvParseMediaEvent(
          '{"type":"position","ms":4000,"seek":3}')! as DVMediaPosition;
      expect(p.position, const Duration(seconds: 4));
      expect(p.seek, 3);
      expect(
          (dvParseMediaEvent('{"type":"position","ms":1}')! as DVMediaPosition)
              .seek,
          0);
    });

    test('every event the contract has', () {
      expect(dvParseMediaEvent('{"type":"playing"}'), isA<DVMediaPlaying>());
      expect(dvParseMediaEvent('{"type":"paused"}'), isA<DVMediaPaused>());
      expect(dvParseMediaEvent('{"type":"buffering"}'), isA<DVMediaBuffering>());
      expect(dvParseMediaEvent('{"type":"completed"}'), isA<DVMediaCompleted>());
      final DVMediaSeekCompleted seek = dvParseMediaEvent(
              '{"type":"seekCompleted","seek":2,"ms":9000}')!
          as DVMediaSeekCompleted;
      expect(seek.generation, 2);
      expect(seek.position, const Duration(seconds: 9));
      final DVMediaBuffered buffered = dvParseMediaEvent(
              '{"type":"buffered","ranges":[[0,1000],[2000,3000]]}')!
          as DVMediaBuffered;
      expect(buffered.ranges, <DVRange>[
        const DVRange(Duration.zero, Duration(seconds: 1)),
        const DVRange(Duration(seconds: 2), Duration(seconds: 3)),
      ]);
      final DVMediaVideoSize size = dvParseMediaEvent(
          '{"type":"videoSize","width":1920,"height":1080}')! as DVMediaVideoSize;
      expect((size.width, size.height), (1920, 1080));
      expect(
          (dvParseMediaEvent('{"type":"pip","active":true}')!
                  as DVMediaPictureInPictureChanged)
              .active,
          isTrue);
      expect(
          (dvParseMediaEvent('{"type":"failed","message":"no codec"}')!
                  as DVMediaFailed)
              .message,
          'no codec');
    });

    test('an unknown or malformed event is ignored, not thrown', () {
      expect(dvParseMediaEvent('{"type":"somethingNew"}'), isNull);
      expect(dvParseMediaEvent('not json'), isNull);
      expect(dvParseMediaEvent('[]'), isNull);
      expect(dvParseMediaEvent('{"type":"ready","durationMs":"soon"}'), isNull);
    });
  });

  group('camera events', () {
    test('opened names the lens and the preview size', () {
      final DVCameraOpened opened = dvParseCameraEvent(
              '{"type":"opened","lens":"front","width":1280,"height":720}')!
          as DVCameraOpened;
      expect(opened.lens, DVCameraLens.front);
      expect((opened.width, opened.height), (1280, 720));
    });

    test('every event the contract has', () {
      expect(dvParseCameraEvent('{"type":"closed"}'), isA<DVCameraClosed>());
      expect(
          (dvParseCameraEvent('{"type":"photo","path":"/p/a.jpg"}')!
                  as DVCameraPhotoTaken)
              .path,
          '/p/a.jpg');
      expect(dvParseCameraEvent('{"type":"recordingStarted"}'),
          isA<DVCameraRecordingStarted>());
      expect(
          (dvParseCameraEvent('{"type":"recordingStopped","durationMs":3000}')!
                  as DVCameraRecordingStopped)
              .duration,
          const Duration(seconds: 3));
      expect(dvParseCameraEvent('{"type":"disconnected"}'),
          isA<DVCameraDisconnected>());
      expect(
          (dvParseCameraEvent('{"type":"failed","message":"busy"}')!
                  as DVCameraFailed)
              .message,
          'busy');
    });

    test('an unknown lens is not guessed', () {
      expect(dvParseCameraEvent('{"type":"opened","lens":"periscope"}'), isNull);
    });
  });

  group('now-playing commands', () {
    test('each action, and seekTo with its position', () {
      expect(dvParseMediaCommand('{"action":"play"}'),
          const DVMediaCommand(DVTransportAction.play));
      expect(dvParseMediaCommand('{"action":"togglePlay"}'),
          const DVMediaCommand(DVTransportAction.togglePlay));
      expect(dvParseMediaCommand('{"action":"seekTo","ms":42000}'),
          const DVMediaCommand(DVTransportAction.seekTo,
              position: Duration(seconds: 42)));
    });

    test('seekTo without a position is dropped', () {
      expect(dvParseMediaCommand('{"action":"seekTo"}'), isNull);
      expect(dvParseMediaCommand('{"action":"eject"}'), isNull);
    });

    test('a session is encoded with its artwork and state for publishing', () {
      final String json = dvEncodeNowPlaying(
        const DVMediaSession(title: 'Ep 4', artist: 'Show', artworkUrl: 'https://a/b.jpg'),
        const DVNowPlayingState(
            playing: true,
            position: Duration(seconds: 5),
            duration: Duration(minutes: 30)),
      );
      expect(json, contains('"title":"Ep 4"'));
      expect(json, contains('"artist":"Show"'));
      expect(json, contains('"positionMs":5000'));
      expect(json, contains('"durationMs":1800000'));
      expect(json, contains('"playing":true'));
      expect(json, contains('"skipMs":10000'));
    });
  });
}
