/// In-memory media backends, for tests and for targets under test.
///
/// Public, because an application testing its own player UI needs a backend
/// that does what the test says rather than what a decoder happens to do.
library;

import 'dart:async';

import 'audio_focus.dart';
import 'media_signal.dart';
import 'media_source.dart';
import 'player_backend.dart';

/// A player backend that records what it was asked and emits what it is told.
final class DVFakeMediaPlayerBackend implements DVMediaPlayerBackend {
  DVFakeMediaPlayerBackend({
    this.capabilities = const DVMediaBackendCapabilities(),
  });

  @override
  final DVMediaBackendCapabilities capabilities;

  final StreamController<DVMediaBackendEvent> _events =
      StreamController<DVMediaBackendEvent>.broadcast();

  final List<DVMediaSource> opened = <DVMediaSource>[];
  final List<Object?> licenses = <Object?>[];
  final List<String> calls = <String>[];
  final List<(Duration, int)> seeks = <(Duration, int)>[];
  final List<double> volumes = <double>[];
  int disposeCount = 0;

  bool get disposed => disposeCount > 0;

  /// Whether anything is still subscribed to [events].
  bool get hasListener => _events.hasListener;

  void emit(DVMediaBackendEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Stream<DVMediaBackendEvent> get events => _events.stream;

  @override
  Future<void> open(DVMediaSource source, {Object? license}) async {
    calls.add('open');
    opened.add(source);
    if (license != null) licenses.add(license);
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> seek(Duration position, int generation) async {
    calls.add('seek');
    seeks.add((position, generation));
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('volume');
    volumes.add(volume);
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    disposeCount++;
  }
}

/// Audio focus the test grants, refuses and takes away.
final class DVFakeAudioFocusBackend implements DVAudioFocusBackend {
  DVFakeAudioFocusBackend({this.grant = true});

  bool grant;
  int requests = 0;
  int abandons = 0;
  bool held = false;

  final StreamController<void> _losses = StreamController<void>.broadcast();

  /// The platform takes focus away.
  void loseFocus() {
    held = false;
    _losses.add(null);
  }

  @override
  Future<bool> request() async {
    requests++;
    if (grant) held = true;
    return grant;
  }

  @override
  Future<void> abandon() async {
    abandons++;
    held = false;
  }

  @override
  Stream<void> get losses => _losses.stream;
}

/// A DRM adapter that licenses anything in its scheme.
final class DVFakeDrmAdapter implements DVDrmAdapter {
  DVFakeDrmAdapter(DVDrmScheme scheme) : schemes = <DVDrmScheme>{scheme};

  @override
  final Set<DVDrmScheme> schemes;

  final List<DVMediaSource> licensed = <DVMediaSource>[];

  @override
  Future<Object?> license(DVMediaSource source) async {
    licensed.add(source);
    return 'licence:${source.protection!.scheme.name}';
  }
}

/// Timers that fire when the test says time has passed.
final class DVFakeMediaTimers implements DVMediaTimers {
  Duration _now = Duration.zero;
  final List<_DVFakeTimer> _timers = <_DVFakeTimer>[];

  /// How much fake time has passed.
  Duration get now => _now;

  /// Timers scheduled and neither fired nor cancelled.
  int get pending => _timers.where((t) => !t.done).length;

  @override
  DVMediaTimer start(Duration after, void Function() onFire) {
    final _DVFakeTimer timer = _DVFakeTimer(_now + after, onFire);
    _timers.add(timer);
    return timer;
  }

  /// Advances time by [by], firing every timer that falls due, in order.
  void elapse(Duration by) {
    final Duration until = _now + by;
    while (true) {
      final List<_DVFakeTimer> due = _timers
          .where((t) => !t.done && t.due <= until)
          .toList()
        ..sort((a, b) => a.due.compareTo(b.due));
      if (due.isEmpty) break;
      final _DVFakeTimer next = due.first;
      _now = next.due;
      next.done = true;
      next.onFire();
    }
    _now = until;
    _timers.removeWhere((t) => t.done);
  }
}

final class _DVFakeTimer implements DVMediaTimer {
  _DVFakeTimer(this.due, this.onFire);

  final Duration due;
  final void Function() onFire;
  bool done = false;

  @override
  void cancel() => done = true;
}
