// What a player adds on top of play/pause: the lock screen, picture-in-
// picture, captions and the disk cache.
//
// The quiet failures: a lock screen still showing a player that was
// disposed, its buttons driving a player that lost focus to another, a
// captions line that stays on screen after a seek, a "cached" player that
// still opened the origin URL, and picture-in-picture claimed on a target that
// has none.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Future<void> pump() => Future<void>.delayed(.zero);

final class _FakeNowPlaying implements DVNowPlayingBackend {
  final List<(DVMediaSession, DVNowPlayingState)> published =
      <(DVMediaSession, DVNowPlayingState)>[];
  int clears = 0;
  final StreamController<DVMediaCommand> _commands =
      StreamController<DVMediaCommand>.broadcast();

  void press(DVMediaCommand command) => _commands.add(command);

  @override
  Future<void> publish(DVMediaSession session, DVNowPlayingState state) async =>
      published.add((session, state));

  @override
  Future<void> clear() async => clears++;

  @override
  Stream<DVMediaCommand> get commands => _commands.stream;
}

final class _PipBackend implements DVMediaPictureInPictureBackend {
  final DVFakeMediaPlayerBackend inner = DVFakeMediaPlayerBackend();
  int enters = 0;

  void emit(DVMediaBackendEvent event) => inner.emit(event);

  @override
  DVMediaBackendCapabilities get capabilities =>
      const DVMediaBackendCapabilities(pictureInPicture: true);

  @override
  Stream<DVMediaBackendEvent> get events => inner.events;

  @override
  Future<void> open(DVMediaSource source, {Object? license}) =>
      inner.open(source, license: license);

  @override
  Future<void> play() => inner.play();

  @override
  Future<void> pause() => inner.pause();

  @override
  Future<void> seek(Duration position, int generation) =>
      inner.seek(position, generation);

  @override
  Future<void> setVolume(double volume) => inner.setVolume(volume);

  @override
  Future<void> dispose() => inner.dispose();

  @override
  Future<bool> enterPictureInPicture() async {
    enters++;
    return true;
  }

  @override
  Future<void> exitPictureInPicture() async {}
}

final class _FakeCache implements DVMediaCache {
  final List<String> asked = <String>[];

  @override
  Future<String> playbackAddress(String url) async {
    asked.add(url);
    return 'http://127.0.0.1:1/${url.hashCode}';
  }

  @override
  Future<void> precache(String url, {int? bytes}) async {}

  @override
  Future<bool> contains(String url, {int? bytes}) async => false;

  @override
  Future<int> size() async => 0;

  @override
  Future<void> clear() async {}

  @override
  Future<void> close() async {}
}

void main() {
  late DVFakeMediaTimers timers;
  late DVMutableLifecycleSignal<DVAppLifecycle> app;
  late DVAudioFocus focus;
  late _FakeNowPlaying platform;
  late DVNowPlaying nowPlaying;

  DVMediaEnvironment env({
    DVMediaCache? cache,
    Future<String> Function(DVMediaSource)? captionLoader,
  }) =>
      DVMediaEnvironment(
        lifecycle: app,
        focus: focus,
        timers: timers,
        nowPlaying: nowPlaying,
        cache: cache,
        captionLoader: captionLoader,
        diagnostics: (String code, String message) {},
      );

  setUp(() {
    timers = DVFakeMediaTimers();
    app = DVMutableLifecycleSignal<DVAppLifecycle>(DVAppLifecycle.ready);
    focus = DVAudioFocus(DVFakeAudioFocusBackend());
    platform = _FakeNowPlaying();
    nowPlaying = DVNowPlaying(platform);
  });

  Future<DVMediaController> ready(
      DVMediaController c, DVMediaPlayerBackend backend) async {
    addTearDown(c.dispose);
    await c.attach(backend);
    switch (backend) {
      case final DVFakeMediaPlayerBackend b:
        b.emit(const DVMediaReady(duration: Duration(minutes: 3)));
      case final _PipBackend b:
        b.emit(const DVMediaReady(duration: Duration(minutes: 3)));
    }
    await pump();
    return c;
  }

  group('now playing', () {
    const DVMediaSession episode = DVMediaSession(title: 'Episode 4');

    test('a player with a session is published when it starts', () async {
      final DVFakeMediaPlayerBackend backend = DVFakeMediaPlayerBackend();
      final DVMediaController c = await ready(
          DVMediaController(const DVMediaSource.url('https://x/a.mp3'),
              session: episode, environment: env()),
          backend);
      expect(platform.published, isEmpty);

      await c.play();
      backend.emit(const DVMediaPlaying());
      await pump();
      expect(platform.published.last.$1.title, 'Episode 4');
      expect(platform.published.last.$2.playing, isTrue);
      expect(platform.published.last.$2.duration, const Duration(minutes: 3));

      backend.emit(const DVMediaPaused());
      await pump();
      expect(platform.published.last.$2.playing, isFalse);
    });

    test('a player with no session publishes nothing', () async {
      final DVFakeMediaPlayerBackend backend = DVFakeMediaPlayerBackend();
      final DVMediaController c = await ready(
          DVMediaController(const DVMediaSource.url('https://x/a.mp3'),
              environment: env()),
          backend);
      await c.play();
      backend.emit(const DVMediaPlaying());
      await pump();
      expect(platform.published, isEmpty);
    });

    test('lock-screen buttons drive the player', () async {
      final DVFakeMediaPlayerBackend backend = DVFakeMediaPlayerBackend();
      final DVMediaController c = await ready(
          DVMediaController(const DVMediaSource.url('https://x/a.mp3'),
              session: episode, environment: env()),
          backend);
      await c.play();
      backend.emit(const DVMediaPlaying());
      await pump();

      backend.calls.clear();
      platform.press(const DVMediaCommand(DVTransportAction.pause));
      await pump();
      expect(backend.calls, contains('pause'));

      platform.press(const DVMediaCommand(DVTransportAction.seekTo,
          position: Duration(seconds: 42)));
      await pump();
      expect(backend.seeks.last.$1, const Duration(seconds: 42));

      platform.press(const DVMediaCommand(DVTransportAction.seekForward));
      await pump();
      expect(backend.seeks.last.$1, const Duration(seconds: 52));
    });

    test('the second player takes the surface; the first stops answering',
        () async {
      final DVFakeMediaPlayerBackend one = DVFakeMediaPlayerBackend();
      final DVFakeMediaPlayerBackend two = DVFakeMediaPlayerBackend();
      final DVMediaController a = await ready(
          DVMediaController(const DVMediaSource.url('https://x/a.mp3'),
              session: episode, environment: env()),
          one);
      final DVMediaController b = await ready(
          DVMediaController(const DVMediaSource.url('https://x/b.mp3'),
              session: const DVMediaSession(title: 'Other'),
              environment: env()),
          two);
      await a.play();
      await b.play();
      await pump();
      expect(platform.published.last.$1.title, 'Other');

      one.calls.clear();
      platform.press(const DVMediaCommand(DVTransportAction.play));
      await pump();
      expect(one.calls, isNot(contains('play')));
      expect(two.calls, contains('play'));
    });

    test('disposing clears the surface', () async {
      final DVFakeMediaPlayerBackend backend = DVFakeMediaPlayerBackend();
      final DVMediaController c = await ready(
          DVMediaController(const DVMediaSource.url('https://x/a.mp3'),
              session: episode, environment: env()),
          backend);
      await c.play();
      await pump();
      await c.dispose();
      expect(platform.clears, 1);
      expect(nowPlaying.owner, isNull);
    });
  });

  group('picture-in-picture', () {
    test('is refused with a typed error where the backend has none', () async {
      final DVMediaController c = await ready(
          DVMediaController(const DVMediaSource.url('https://x/a.mp4'),
              environment: env()),
          DVFakeMediaPlayerBackend());
      expect(c.canPictureInPicture, isFalse);
      await expectLater(c.enterPictureInPicture(),
          throwsA(isA<DVMediaPictureInPictureUnavailable>()));
    });

    test('follows what the backend reports, not the request', () async {
      final _PipBackend backend = _PipBackend();
      final DVMediaController c = await ready(
          DVMediaController(const DVMediaSource.url('https://x/a.mp4'),
              environment: env()),
          backend);
      expect(c.canPictureInPicture, isTrue);
      await c.enterPictureInPicture();
      expect(backend.enters, 1);
      expect(c.pictureInPicture.value, isFalse);
      backend.emit(const DVMediaPictureInPictureChanged(true));
      await pump();
      expect(c.pictureInPicture.value, isTrue);
    });
  });

  test('the decoded picture size is a signal', () async {
    final DVFakeMediaPlayerBackend backend = DVFakeMediaPlayerBackend();
    final DVMediaController c = await ready(
        DVMediaController(const DVMediaSource.url('https://x/a.mp4'),
            environment: env()),
        backend);
    expect(c.videoSize.value, isNull);
    backend.emit(const DVMediaVideoSize(1920, 1080));
    await pump();
    expect(c.videoSize.value, (1920, 1080));
  });

  group('cache', () {
    test('a progressive URL is opened through the cache', () async {
      final _FakeCache cache = _FakeCache();
      final DVFakeMediaPlayerBackend backend = DVFakeMediaPlayerBackend();
      await ready(
          DVMediaController(const DVMediaSource.url('https://x/a.mp4'),
              environment: env(cache: cache)),
          backend);
      expect(cache.asked, <String>['https://x/a.mp4']);
      expect(backend.opened.single.reference, startsWith('http://127.0.0.1'));
    });

    test('an adaptive stream, a file and an opted-out source are not',
        () async {
      final _FakeCache cache = _FakeCache();
      for (final DVMediaSource source in <DVMediaSource>[
        const DVMediaSource.url('https://x/live.m3u8'),
        const DVMediaSource.file('/tmp/a.mp4'),
        const DVMediaSource.url('https://x/b.mp4', cache: false),
      ]) {
        final DVFakeMediaPlayerBackend backend = DVFakeMediaPlayerBackend();
        await ready(DVMediaController(source, environment: env(cache: cache)),
            backend);
        expect(backend.opened.single.reference, source.reference);
      }
      expect(cache.asked, isEmpty);
    });
  });

  group('captions', () {
    final DVCaptions captions = DVCaptions(<DVCaptionTrack>[
      DVCaptionTrack.source('en', const DVMediaSource.url('https://x/en.vtt')),
      DVCaptionTrack.cues('fr', const <DVCaptionCue>[
        DVCaptionCue(Duration(seconds: 1), Duration(seconds: 2), 'Bonjour'),
      ]),
    ]);
    const String english =
        'WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHello\n';

    test('the first track loads, and the cue follows the position', () async {
      final List<DVMediaSource> loaded = <DVMediaSource>[];
      final DVFakeMediaPlayerBackend backend = DVFakeMediaPlayerBackend();
      final DVMediaController c = await ready(
          DVMediaController(const DVMediaSource.url('https://x/a.mp4'),
              captions: captions,
              environment: env(captionLoader: (DVMediaSource s) async {
                loaded.add(s);
                return english;
              })),
          backend);
      await pump();
      expect(c.captionTrack.value, 'en');
      expect(loaded.single.reference, 'https://x/en.vtt');

      backend.emit(const DVMediaPosition(Duration(milliseconds: 1500)));
      await pump();
      expect(c.caption.value, 'Hello');

      backend.emit(const DVMediaPosition(Duration(milliseconds: 2500)));
      await pump();
      expect(c.caption.value, isNull);
    });

    test('a seek updates the cue at once', () async {
      final DVFakeMediaPlayerBackend backend = DVFakeMediaPlayerBackend();
      final DVMediaController c = await ready(
          DVMediaController(const DVMediaSource.url('https://x/a.mp4'),
              captions: captions,
              environment: env(captionLoader: (_) async => english)),
          backend);
      await pump();
      unawaited(c.seek(const Duration(milliseconds: 1200)));
      expect(c.caption.value, 'Hello');
    });

    test('switching track, and turning captions off', () async {
      final DVFakeMediaPlayerBackend backend = DVFakeMediaPlayerBackend();
      final DVMediaController c = await ready(
          DVMediaController(const DVMediaSource.url('https://x/a.mp4'),
              captions: captions,
              environment: env(captionLoader: (_) async => english)),
          backend);
      backend.emit(const DVMediaPosition(Duration(milliseconds: 1500)));
      await pump();
      await c.setCaptionTrack('fr');
      expect(c.captionTrack.value, 'fr');
      expect(c.caption.value, 'Bonjour');
      await c.setCaptionTrack(null);
      expect(c.caption.value, isNull);
      expect(() => c.setCaptionTrack('de'), throwsArgumentError);
    });

    test('a track that will not load is reported, not shown empty', () async {
      final DVFakeMediaPlayerBackend backend = DVFakeMediaPlayerBackend();
      final DVMediaController c = await ready(
          DVMediaController(const DVMediaSource.url('https://x/a.mp4'),
              captions: captions,
              environment: env(
                  captionLoader: (_) async => throw StateError('404'))),
          backend);
      await pump();
      expect(c.captionTrack.value, isNull);
      expect(c.captionError.value, contains('404'));
    });
  });
}
