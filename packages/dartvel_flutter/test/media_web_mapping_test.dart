// The browser player and camera, in the parts that do not need a browser:
// what the page document says about a player, how element events become the
// player's reports, how lock-screen actions become commands, and where a
// recording lives on a target with no files.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/media/web_media_mapping.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVWebMediaSnapshot snap({
  double duration = double.nan,
  double time = 0,
  int width = 0,
  int height = 0,
  List<(double, double)> buffered = const <(double, double)>[],
  String? error,
}) =>
    DVWebMediaSnapshot(
      duration: duration,
      currentTime: time,
      videoWidth: width,
      videoHeight: height,
      buffered: buffered,
      error: error,
    );

void main() {
  group('the identifier the page document reads', () {
    Map<String, Object?> payload(String identifier) {
      expect(identifier, startsWith('dartvel:'));
      final int bar = identifier.indexOf('|');
      return (jsonDecode(identifier.substring(bar + 1)) as Map)
          .cast<String, Object?>();
    }

    test('a video names its source, poster and caption tracks', () {
      final String id = dvMediaSemanticsIdentifier(
        kind: DVMediaKind.video,
        source: const DVMediaSource.url('https://cdn.test/a.mp4'),
        poster: const DVImage.network('https://cdn.test/a.jpg'),
        captions: DVCaptions(<DVCaptionTrack>[
          DVCaptionTrack.source(
              'en', const DVMediaSource.asset('captions/a.en.vtt'),
              label: 'English'),
          DVCaptionTrack.cues('fr', const <DVCaptionCue>[]),
        ]),
      );
      expect(id, startsWith('dartvel:video|'));
      final Map<String, Object?> media = payload(id);
      expect(media['src'], 'https://cdn.test/a.mp4');
      expect(media['poster'], 'https://cdn.test/a.jpg');
      // A track the application holds in memory has no address to give.
      expect(media['tracks'], <Object?>[
        <String, Object?>{
          'srclang': 'en',
          'label': 'English',
          'src': 'assets/captions/a.en.vtt',
        },
      ]);
    });

    test('an asset is addressed where the web build serves it', () {
      expect(
          payload(dvMediaSemanticsIdentifier(
              kind: DVMediaKind.audio,
              source: const DVMediaSource.asset('audio/chime.mp3')))['src'],
          'assets/audio/chime.mp3');
    });

    test('a file on the device has no address', () {
      expect(
          payload(dvMediaSemanticsIdentifier(
                  kind: DVMediaKind.video,
                  source: const DVMediaSource.file('/data/a.mp4')))
              .containsKey('src'),
          isFalse);
    });

    test('an adaptive stream is offered as its progressive rendition', () {
      // A browser without HLS would show a <video> that never plays.
      expect(
          payload(dvMediaSemanticsIdentifier(
              kind: DVMediaKind.video,
              source: const DVMediaSource.url('https://cdn.test/live.m3u8',
                  progressive: 'https://cdn.test/live.mp4')))['src'],
          'https://cdn.test/live.mp4');
    });

    test('the camera says only that it is one', () {
      expect(dvCameraSemanticsIdentifier, 'dartvel:camera|{}');
    });
  });

  group('element events', () {
    late DVWebMediaEventMapper mapper;
    setUp(() => mapper = DVWebMediaEventMapper());

    test('loadedmetadata is ready with the duration and the picture size', () {
      final List<DVMediaBackendEvent> events = mapper.map('loadedmetadata',
          snap(duration: 125.5, width: 1920, height: 1080));
      expect(events, hasLength(2));
      expect((events[0] as DVMediaReady).duration,
          const Duration(milliseconds: 125500));
      expect(events[1], isA<DVMediaVideoSize>());
      expect((events[1] as DVMediaVideoSize).width, 1920);
    });

    test('a live stream has no duration rather than an infinite one', () {
      final DVMediaReady ready = mapper
          .map('loadedmetadata', snap(duration: double.infinity))
          .single as DVMediaReady;
      expect(ready.duration, Duration.zero);
    });

    test('audio has no picture size', () {
      expect(mapper.map('loadedmetadata', snap(duration: 3)), hasLength(1));
    });

    test('playing, pause, waiting and ended', () {
      expect(mapper.map('playing', snap()).single, isA<DVMediaPlaying>());
      expect(mapper.map('pause', snap()).single, isA<DVMediaPaused>());
      expect(mapper.map('waiting', snap()).single, isA<DVMediaBuffering>());
      expect(mapper.map('ended', snap()).single, isA<DVMediaCompleted>());
    });

    test('a position measured before a seek completed carries the old '
        'generation', () {
      mapper.seekIssued(3);
      final DVMediaPosition before =
          mapper.map('timeupdate', snap(time: 1)).single as DVMediaPosition;
      expect(before.seek, 0);
      final DVMediaSeekCompleted done = mapper
          .map('seeked', snap(time: 30))
          .single as DVMediaSeekCompleted;
      expect(done.generation, 3);
      expect(done.position, const Duration(seconds: 30));
      final DVMediaPosition after =
          mapper.map('timeupdate', snap(time: 30.25)).single as DVMediaPosition;
      expect(after.seek, 3);
      expect(after.position, const Duration(milliseconds: 30250));
    });

    test('progress reports buffered ranges', () {
      final DVMediaBuffered buffered = mapper
          .map('progress', snap(buffered: <(double, double)>[(0, 12.5)]))
          .single as DVMediaBuffered;
      expect(buffered.ranges.single,
          const DVRange(Duration.zero, Duration(milliseconds: 12500)));
    });

    test('an error is a failure with the browser\'s reason', () {
      final DVMediaFailed failed = mapper
          .map('error', snap(error: 'MEDIA_ERR_SRC_NOT_SUPPORTED'))
          .single as DVMediaFailed;
      expect(failed.message, contains('MEDIA_ERR_SRC_NOT_SUPPORTED'));
    });

    test('picture-in-picture follows the browser', () {
      expect((mapper.map('enterpictureinpicture', snap()).single
              as DVMediaPictureInPictureChanged)
          .active, isTrue);
      expect((mapper.map('leavepictureinpicture', snap()).single
              as DVMediaPictureInPictureChanged)
          .active, isFalse);
    });

    test('events nobody reads map to nothing', () {
      expect(mapper.map('volumechange', snap()), isEmpty);
    });
  });

  group('media session actions', () {
    test('map to transport commands', () {
      expect(dvMediaSessionCommand('play'),
          const DVMediaCommand(DVTransportAction.play));
      expect(dvMediaSessionCommand('pause'),
          const DVMediaCommand(DVTransportAction.pause));
      expect(dvMediaSessionCommand('stop'),
          const DVMediaCommand(DVTransportAction.stop));
      expect(dvMediaSessionCommand('seekforward'),
          const DVMediaCommand(DVTransportAction.seekForward));
      expect(dvMediaSessionCommand('seekbackward'),
          const DVMediaCommand(DVTransportAction.seekBackward));
      expect(dvMediaSessionCommand('seekto', seekTime: 42.5),
          const DVMediaCommand(DVTransportAction.seekTo,
              position: Duration(milliseconds: 42500)));
    });

    test('a seek with no time, and unknown actions, are nothing', () {
      expect(dvMediaSessionCommand('seekto'), isNull);
      expect(dvMediaSessionCommand('nexttrack'), isNull);
    });

    test('the actions a session registers are the ones it maps', () {
      for (final String action in dvMediaSessionActions) {
        expect(dvMediaSessionCommand(action, seekTime: 1), isNotNull,
            reason: action);
      }
    });
  });

  group('recordings with no filesystem', () {
    test('a reserved key holds the bytes the device writes', () async {
      final DVWebCaptureStore store = DVWebCaptureStore();
      final String path = await store.reserve('webm');
      expect(path, startsWith('dvcapture:'));
      expect(path, endsWith('.webm'));
      store.write(path, Uint8List.fromList(<int>[1, 2, 3]));
      expect(await store.seal(path), 3);
      expect(store.bytesOf(path), <int>[1, 2, 3]);
    });

    test('sealing a recording the device never wrote fails', () async {
      final DVWebCaptureStore store = DVWebCaptureStore();
      final String path = await store.reserve('jpg');
      await expectLater(store.seal(path), throwsStateError);
    });

    test('a discarded recording is gone', () async {
      final DVWebCaptureStore store = DVWebCaptureStore();
      final String path = await store.reserve('jpg');
      store.write(path, Uint8List(4));
      await store.discard(path);
      expect(store.bytesOf(path), isNull);
    });

    test('keys are never reused', () async {
      final DVWebCaptureStore store = DVWebCaptureStore();
      final Set<String> keys = <String>{
        for (int i = 0; i < 20; i++) await store.reserve('jpg'),
      };
      expect(keys, hasLength(20));
    });

    test('a write to a key that was not reserved is refused', () {
      expect(() => DVWebCaptureStore().write('dvcapture:x.jpg', Uint8List(1)),
          throwsStateError);
    });
  });

  group('the boxes carry it', () {
    tearDown(DVMediaBackends.reset);

    Iterable<String> identifiers(WidgetTester tester) => tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((Semantics s) => s.properties.identifier)
        .whereType<String>();

    testWidgets('a video box', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
          home: DVBox.video(const DVMediaSource.url('https://cdn.test/a.mp4'))));
      expect(
          identifiers(tester),
          contains(dvMediaSemanticsIdentifier(
              kind: DVMediaKind.video,
              source: const DVMediaSource.url('https://cdn.test/a.mp4'))));
    });

    testWidgets('a camera box', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: DVBox.camera()));
      await tester.pump();
      expect(identifiers(tester), contains(dvCameraSemanticsIdentifier));
    });
  });
}
