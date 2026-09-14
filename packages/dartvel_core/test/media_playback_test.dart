// The platform-independent half of `DVBox.video` / `DVBox.audio`: the player
// state machine every backend reports into.
//
// The failures that matter here are the quiet ones. A play button that says
// "playing" while the decoder has stalled, a scrubber that jumps back to where
// it was before a seek because a late position report arrived, a video still
// playing after the application went to the background, audio focus still held
// by a player nobody can see -- each of those looks fine in a screenshot.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  late DVFakeMediaPlayerBackend backend;
  late DVFakeMediaTimers timers;
  late DVMutableLifecycleSignal<DVAppLifecycle> app;
  late DVAudioFocus focus;
  late List<String> codes;

  DVMediaController controller(
    DVMediaSource source, {
    DVMediaPlayerBackend? using,
    DVBackgroundPlayback background = DVBackgroundPlayback.none,
    bool backgroundAudioDeclared = false,
    List<DVDrmAdapter> drm = const <DVDrmAdapter>[],
  }) {
    final DVMediaController c = DVMediaController(
      source,
      background: background,
      environment: DVMediaEnvironment(
        lifecycle: app,
        focus: focus,
        timers: timers,
        drmAdapters: drm,
        backgroundAudioDeclared: backgroundAudioDeclared,
        diagnostics: (String code, String message) => codes.add(code),
      ),
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    backend = DVFakeMediaPlayerBackend();
    timers = DVFakeMediaTimers();
    app = DVMutableLifecycleSignal<DVAppLifecycle>(DVAppLifecycle.ready);
    focus = DVAudioFocus(DVFakeAudioFocusBackend());
    codes = <String>[];
  });

  group('state', () {
    test('is idle until attached and loading until the backend is ready',
        () async {
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      expect(c.state.value, DVPlaybackState.idle);

      await c.attach(backend);
      expect(backend.opened.single.reference, 'https://cdn.test/a.mp4');
      expect(c.state.value, DVPlaybackState.loading);

      backend.emit(const DVMediaReady(duration: Duration(minutes: 2)));
      await pump();
      expect(c.state.value, DVPlaybackState.paused);
      expect(c.duration.value, const Duration(minutes: 2));
    });

    test('play is not reported as playing until the backend says so',
        () async {
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      backend.emit(const DVMediaReady(duration: Duration(minutes: 2)));
      await pump();

      await c.play();
      expect(backend.calls, contains('play'));
      // The request went out; nothing has actually started.
      expect(c.state.value, DVPlaybackState.paused);

      backend.emit(const DVMediaPlaying());
      await pump();
      expect(c.state.value, DVPlaybackState.playing);
    });

    test('a decoder that stops advancing while "playing" is reported stalled',
        () async {
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      backend
        ..emit(const DVMediaReady(duration: Duration(minutes: 2)))
        ..emit(const DVMediaPlaying())
        ..emit(const DVMediaPosition(Duration(seconds: 1)));
      await pump();
      expect(c.state.value, DVPlaybackState.playing);

      // The backend never says anything else. Its last word was "playing".
      timers.elapse(c.stallTimeout);
      expect(c.state.value, DVPlaybackState.stalled);

      backend.emit(const DVMediaPosition(Duration(seconds: 2)));
      await pump();
      expect(c.state.value, DVPlaybackState.playing);
    });

    test('a position report that does not move does not count as progress',
        () async {
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      backend
        ..emit(const DVMediaReady(duration: Duration(minutes: 2)))
        ..emit(const DVMediaPlaying())
        ..emit(const DVMediaPosition(Duration(seconds: 4)));
      await pump();

      timers.elapse(c.stallTimeout ~/ 2);
      backend.emit(const DVMediaPosition(Duration(seconds: 4)));
      await pump();
      timers.elapse(c.stallTimeout ~/ 2);
      expect(c.state.value, DVPlaybackState.stalled);
    });

    test('a paused player is never reported stalled', () async {
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      backend
        ..emit(const DVMediaReady(duration: Duration(minutes: 2)))
        ..emit(const DVMediaPaused());
      await pump();
      timers.elapse(c.stallTimeout * 3);
      expect(c.state.value, DVPlaybackState.paused);
    });

    test('backend buffering and completion reach the signal', () async {
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      backend
        ..emit(const DVMediaReady(duration: Duration(seconds: 10)))
        ..emit(const DVMediaPlaying())
        ..emit(const DVMediaBuffering())
        ..emit(const DVMediaBuffered(<DVRange>[
          DVRange(Duration.zero, Duration(seconds: 6)),
        ]));
      await pump();
      expect(c.state.value, DVPlaybackState.buffering);
      expect(c.buffered.value.single.end, const Duration(seconds: 6));

      backend.emit(const DVMediaCompleted());
      await pump();
      expect(c.state.value, DVPlaybackState.completed);
    });

    test('a failed player stays failed when a late report arrives', () async {
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      backend.emit(const DVMediaFailed('Resource not found.'));
      await pump();
      // A backend that says "playing" after it failed -- one answering a play
      // request, or a report already queued -- must not revive the player.
      backend
        ..emit(const DVMediaPlaying())
        ..emit(const DVMediaPosition(Duration(seconds: 3)))
        ..emit(const DVMediaReady(duration: Duration(minutes: 1)));
      await pump();
      expect(c.state.value, DVPlaybackState.failed);
      expect(c.position.value, Duration.zero);
      expect(c.error.value, 'Resource not found.');
    });

    test('a backend error fails the player and says why', () async {
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      backend.emit(const DVMediaFailed('no decoder for video/x-unknown'));
      await pump();
      expect(c.state.value, DVPlaybackState.failed);
      expect(c.error.value, contains('no decoder'));
    });
  });

  group('seek', () {
    test('a position report from before the seek does not move the scrubber '
        'back', () async {
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      backend
        ..emit(const DVMediaReady(duration: Duration(minutes: 2)))
        ..emit(const DVMediaPlaying())
        ..emit(const DVMediaPosition(Duration(seconds: 5)));
      await pump();

      final Future<void> seeking = c.seek(const Duration(seconds: 30));
      expect(c.position.value, const Duration(seconds: 30));
      expect(backend.seeks.single, (const Duration(seconds: 30), 1));

      // Already in flight when the seek was issued.
      backend.emit(const DVMediaPosition(Duration(seconds: 6)));
      await pump();
      expect(c.position.value, const Duration(seconds: 30));

      backend.emit(const DVMediaSeekCompleted(1, Duration(seconds: 30)));
      await seeking;
      expect(c.position.value, const Duration(seconds: 30));

      backend.emit(const DVMediaPosition(Duration(seconds: 31), seek: 1));
      await pump();
      expect(c.position.value, const Duration(seconds: 31));
    });

    test('an earlier seek completing after a later one does not win', () async {
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      backend.emit(const DVMediaReady(duration: Duration(minutes: 2)));
      await pump();

      final Future<void> first = c.seek(const Duration(seconds: 10));
      final Future<void> second = c.seek(const Duration(seconds: 50));
      backend.emit(const DVMediaSeekCompleted(1, Duration(seconds: 10)));
      await first;
      expect(c.position.value, const Duration(seconds: 50));

      backend.emit(const DVMediaSeekCompleted(2, Duration(seconds: 50)));
      await second;
      expect(c.position.value, const Duration(seconds: 50));
    });

    test('a seek past the end is clamped to the duration', () async {
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      backend.emit(const DVMediaReady(duration: Duration(seconds: 20)));
      await pump();
      unawaited(c.seek(const Duration(minutes: 5)));
      expect(backend.seeks.single.$1, const Duration(seconds: 20));
    });
  });

  group('DRM', () {
    const DVMediaSource protected = DVMediaSource.url(
      'https://cdn.test/film.mpd',
      protection: DVDrmProtection(DVDrmScheme.widevine),
    );

    test('protected content with no adapter is refused, not opened', () async {
      final c = controller(protected);
      await expectLater(
        c.attach(backend),
        throwsA(isA<DVMediaDrmUnavailable>()
            .having((e) => e.scheme, 'scheme', DVDrmScheme.widevine)),
      );
      // No black rectangle: the backend was never handed the stream.
      expect(backend.opened, isEmpty);
      expect(c.state.value, DVPlaybackState.failed);
      expect(codes, <String>['DV-MEDIA-102']);
    });

    test('an adapter for another scheme does not count', () async {
      final c = controller(protected,
          drm: <DVDrmAdapter>[DVFakeDrmAdapter(DVDrmScheme.fairPlay)]);
      await expectLater(
          c.attach(backend), throwsA(isA<DVMediaDrmUnavailable>()));
      expect(backend.opened, isEmpty);
    });

    test('a matching adapter licenses the source before it is opened',
        () async {
      final adapter = DVFakeDrmAdapter(DVDrmScheme.widevine);
      final c = controller(protected, drm: <DVDrmAdapter>[adapter]);
      await c.attach(backend);
      expect(adapter.licensed.single.reference, 'https://cdn.test/film.mpd');
      expect(backend.licenses.single, 'licence:widevine');
      expect(codes, isEmpty);
    });
  });

  group('adaptive streaming', () {
    test('is recognised from the manifest extension', () {
      expect(const DVMediaSource.url('https://x/a.m3u8').isAdaptive, isTrue);
      expect(const DVMediaSource.url('https://x/a.mpd?t=1').isAdaptive, isTrue);
      expect(const DVMediaSource.url('https://x/a.mp4').isAdaptive, isFalse);
      expect(const DVMediaSource.file('/tmp/a.m3u8').isAdaptive, isTrue);
    });

    test('falls back to the progressive rendition where streaming is not '
        'supported, and says so', () async {
      final noStreaming = DVFakeMediaPlayerBackend(
          capabilities: const DVMediaBackendCapabilities(
              adaptiveStreaming: false));
      final c = controller(
        const DVMediaSource.url('https://cdn.test/launch.m3u8',
            progressive: 'https://cdn.test/launch-720.mp4'),
      );
      await c.attach(noStreaming);
      expect(noStreaming.opened.single.reference,
          'https://cdn.test/launch-720.mp4');
      expect(codes, <String>['DV-MEDIA-101']);
    });

    test('with no progressive rendition it refuses rather than guessing',
        () async {
      final noStreaming = DVFakeMediaPlayerBackend(
          capabilities: const DVMediaBackendCapabilities(
              adaptiveStreaming: false));
      final c = controller(const DVMediaSource.url('https://cdn.test/launch.m3u8'));
      await expectLater(c.attach(noStreaming),
          throwsA(isA<DVMediaStreamingUnsupported>()));
      expect(noStreaming.opened, isEmpty);
      expect(c.state.value, DVPlaybackState.failed);
    });

    test('a backend that streams gets the manifest itself', () async {
      final c = controller(const DVMediaSource.url('https://cdn.test/launch.m3u8',
          progressive: 'https://cdn.test/launch-720.mp4'));
      await c.attach(backend);
      expect(backend.opened.single.reference, 'https://cdn.test/launch.m3u8');
      expect(codes, isEmpty);
    });
  });

  group('lifecycle', () {
    Future<DVMediaController> playing(
      DVMediaSource source, {
      DVMediaPlayerBackend? using,
      DVBackgroundPlayback background = DVBackgroundPlayback.none,
      bool declared = false,
    }) async {
      final DVFakeMediaPlayerBackend b =
          (using ?? backend) as DVFakeMediaPlayerBackend;
      final c = controller(source,
          background: background, backgroundAudioDeclared: declared);
      await c.attach(b);
      b
        ..emit(const DVMediaReady(duration: Duration(minutes: 3)))
        ..emit(const DVMediaPlaying());
      await pump();
      await c.play();
      return c;
    }

    test('a playing video pauses when the application is backgrounded',
        () async {
      await playing(const DVMediaSource.url('https://cdn.test/a.mp4'));
      backend.calls.clear();

      app.set(DVAppLifecycle.backgrounded);
      await pump();
      expect(backend.calls, contains('pause'));
    });

    test('declared background audio keeps playing', () async {
      final bg = DVFakeMediaPlayerBackend(
          capabilities:
              const DVMediaBackendCapabilities(backgroundAudio: true));
      final c = await playing(const DVMediaSource.url('https://cdn.test/a.aac'),
          using: bg, background: DVBackgroundPlayback.audio, declared: true);
      bg.calls.clear();

      app.set(DVAppLifecycle.backgrounded);
      await pump();
      expect(bg.calls, isNot(contains('pause')));
      expect(c.state.value, DVPlaybackState.playing);
      expect(codes, isEmpty);
    });

    test('background audio requested but not declared warns and pauses',
        () async {
      final bg = DVFakeMediaPlayerBackend(
          capabilities:
              const DVMediaBackendCapabilities(backgroundAudio: true));
      await playing(const DVMediaSource.url('https://cdn.test/a.aac'),
          using: bg, background: DVBackgroundPlayback.audio);
      expect(codes, <String>['DV-MEDIA-103']);
      bg.calls.clear();

      app.set(DVAppLifecycle.backgrounded);
      await pump();
      expect(bg.calls, contains('pause'));
    });

    test('a backend with no background audio pauses even when declared',
        () async {
      await playing(const DVMediaSource.url('https://cdn.test/a.aac'),
          background: DVBackgroundPlayback.audio, declared: true);
      backend.calls.clear();
      app.set(DVAppLifecycle.suspended);
      await pump();
      expect(backend.calls, contains('pause'));
    });
  });

  group('audio focus', () {
    test('playing takes focus, and another player taking it pauses this one',
        () async {
      final first = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await first.attach(backend);
      await first.play();
      expect(focus.holder, same(first));

      final other = DVFakeMediaPlayerBackend();
      final second = controller(const DVMediaSource.url('https://cdn.test/b.mp4'));
      await second.attach(other);
      backend.calls.clear();
      await second.play();

      expect(focus.holder, same(second));
      expect(backend.calls, contains('pause'));
    });

    test('pausing and finishing give focus back to the platform', () async {
      final fb = DVFakeAudioFocusBackend();
      focus = DVAudioFocus(fb);
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      await c.play();
      expect(fb.held, isTrue);

      await c.pause();
      // Held focus keeps the podcast the person paused for from resuming.
      expect(fb.held, isFalse);
      expect(focus.holder, isNull);

      await c.play();
      expect(fb.held, isTrue);
      backend.emit(const DVMediaCompleted());
      await pump();
      expect(fb.held, isFalse);
    });

    test('losing focus to the platform pauses', () async {
      final fb = DVFakeAudioFocusBackend();
      focus = DVAudioFocus(fb);
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      await c.play();
      expect(fb.requests, 1);
      backend.calls.clear();

      fb.loseFocus(); // an incoming call
      await pump();
      expect(backend.calls, contains('pause'));
      expect(focus.holder, isNull);
    });

    test('disposing releases focus with the platform', () async {
      final fb = DVFakeAudioFocusBackend();
      focus = DVAudioFocus(fb);
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      await c.play();

      await c.dispose();
      expect(focus.holder, isNull);
      expect(fb.abandons, 1);
      expect(fb.held, isFalse);
    });

    test('a refused focus request does not start playback', () async {
      final fb = DVFakeAudioFocusBackend(grant: false);
      focus = DVAudioFocus(fb);
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      await expectLater(c.play(), throwsA(isA<DVAudioFocusRefused>()));
      expect(backend.calls, isNot(contains('play')));
    });
  });

  group('disposal', () {
    test('releases the backend and stops observing the application', () async {
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      backend
        ..emit(const DVMediaReady(duration: Duration(minutes: 3)))
        ..emit(const DVMediaPlaying());
      await pump();

      await c.dispose();
      expect(backend.disposed, isTrue);
      expect(c.state.value, DVPlaybackState.disposed);
      expect(backend.hasListener, isFalse);

      backend.calls.clear();
      app.set(DVAppLifecycle.backgrounded);
      await pump();
      expect(backend.calls, isEmpty);
      // A dead player's watchdog does not fire into a released backend.
      expect(timers.pending, 0);
    });

    test('cancels its subscription to the application lifecycle', () async {
      final _CountingLifecycle counted = _CountingLifecycle(app);
      final DVMediaController c = DVMediaController(
        const DVMediaSource.url('https://cdn.test/a.mp4'),
        environment: DVMediaEnvironment(
          lifecycle: counted,
          focus: focus,
          timers: timers,
          diagnostics: (String code, String message) => codes.add(code),
        ),
      );
      await c.attach(backend);
      expect(counted.active, 1);
      await c.dispose();
      // Guarded or not, a live subscription per dead player is a leak.
      expect(counted.active, 0);
    });

    test('a disposed controller refuses to play', () async {
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      await c.dispose();
      await expectLater(c.play(), throwsStateError);
      await expectLater(c.attach(backend), throwsStateError);
    });

    test('disposing twice is harmless', () async {
      final c = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await c.attach(backend);
      await c.dispose();
      await c.dispose();
      expect(backend.disposeCount, 1);
    });
  });

  group('one player, many readers', () {
    test('a controller following another reads the same session, including '
        'signals taken before it followed', () async {
      final owner = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      final reader = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      final DVMediaSignal<DVPlaybackState> earlyState = reader.state;
      final seen = <DVPlaybackState>[];
      earlyState.listen(seen.add);

      await owner.attach(backend);
      reader.follow(owner);
      backend
        ..emit(const DVMediaReady(duration: Duration(minutes: 3)))
        ..emit(const DVMediaPlaying());
      await pump();

      expect(earlyState.value, DVPlaybackState.playing);
      expect(seen.last, DVPlaybackState.playing);

      await reader.pause();
      expect(backend.calls, contains('pause'));
    });

    test('when the owner is disposed its followers report disposed', () async {
      final owner = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      final reader = controller(const DVMediaSource.url('https://cdn.test/a.mp4'));
      await owner.attach(backend);
      reader.follow(owner);
      await owner.dispose();
      await pump();
      expect(reader.state.value, DVPlaybackState.disposed);
      await expectLater(reader.play(), throwsStateError);
    });
  });
}

/// A lifecycle signal that counts the subscriptions still open on it.
final class _CountingLifecycle implements DVLifecycleSignal<DVAppLifecycle> {
  _CountingLifecycle(this._inner);

  final DVLifecycleSignal<DVAppLifecycle> _inner;
  int active = 0;

  @override
  DVAppLifecycle get value => _inner.value;

  @override
  DVAppLifecycle read() => _inner.read();

  @override
  Stream<DVAppLifecycle> get changes => _inner.changes;

  @override
  StreamSubscription<DVAppLifecycle> listen(
      FutureOr<void> Function(DVAppLifecycle state) onState) {
    active++;
    late final StreamController<DVAppLifecycle> relay;
    final StreamSubscription<DVAppLifecycle> inner = _inner.listen(
        (DVAppLifecycle s) => relay.add(s));
    relay = StreamController<DVAppLifecycle>(onCancel: () {
      active--;
      unawaited(relay.close());
      return inner.cancel();
    });
    return relay.stream.listen(onState);
  }
}
