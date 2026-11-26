/// `DV.Timers`: countdowns that ring.
///
/// A cooking timer, a break, a parking meter: several at once, each named,
/// kept across a reload or a restart, and ringing with a sound and a
/// notification -- from the operating system with the app closed where it
/// can (Android), and from the open page everywhere else, in a background
/// tab included.
library dartvel_flutter.timers.timers;

import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'timer.dart';
import 'timer_delivery.dart';
import 'timer_platform_stub.dart'
    if (dart.library.js_interop) 'timer_platform_web.dart'
    if (dart.library.io) 'timer_platform_io.dart' as platform;

/// The timers of this application on this device.
final class DVTimers {
  DVTimers._(this._store, this._delivery, this._now) {
    _timers = dvDecodeTimers(_store.read()).toList()..sort(_soonestFirst);
    _actions = _delivery.actions.listen(_onAction);
    _arm();
  }

  /// A service over [store] and [delivery] with its own clock, for tests.
  factory DVTimers.forTest({
    required DVTimerStore store,
    required DVTimerDelivery delivery,
    required DateTime Function() now,
  }) =>
      DVTimers._(store, delivery, now);

  static DVTimers? _instance;
  static String _app = 'app';
  static DVTimerDelivery Function()? _native;
  static bool _declared = false;

  /// The one service: built on first use, from what the last visit kept.
  static DVTimers get instance {
    final DVTimers? current = _instance;
    if (current != null) return current;
    final DVTimers created = DVTimers._(
      platform.dvPlatformTimerStore(_app),
      _declared && _native != null ? _native!() : platform.dvPlatformTimerDelivery(declared: _declared),
      () => DateTime.now().toUtc(),
    );
    // Another tab of the same app starting or dismissing a timer.
    platform.dvTimerWatchStore(_app, created.reload);
    return _instance = created;
  }

  /// Called by the generated runtime when `dartvel.timers` is on, so timers
  /// that were running before a reload ring on whatever page opens first.
  static void install({required String app}) {
    _app = app;
    _declared = true;
    instance;
  }

  /// Whether the project turned on `dartvel.timers`: then the build wrote the
  /// service worker's and Android's halves.
  static bool get declared => _declared;

  /// The operating system's own delivery, set by a platform binding when it
  /// registers (Android's broadcast receiver). Used only when the project
  /// declared `dartvel.timers`, because only then did the build write the
  /// native half it talks to.
  static set nativeDelivery(DVTimerDelivery Function() create) {
    _native = create;
    final DVTimers? current = _instance;
    if (current != null) {
      current.dispose();
      _instance = null;
    }
  }

  /// Forgets the service, for tests.
  static void resetForTest() {
    _instance?.dispose();
    _instance = null;
    _native = null;
    _declared = false;
  }

  final DVTimerStore _store;
  final DVTimerDelivery _delivery;
  final DateTime Function() _now;
  late List<DVTimer> _timers;
  late final StreamSubscription<DVTimerAction> _actions;
  final StreamController<List<DVTimer>> _changes = StreamController<List<DVTimer>>.broadcast(sync: true);
  Timer? _due;
  Timer? _ticker;
  bool _asked = false;

  static int _soonestFirst(DVTimer a, DVTimer b) {
    final Duration left = a.endsAt == null ? a.pausedWith! : Duration(microseconds: a.endsAt!.microsecondsSinceEpoch);
    final Duration right = b.endsAt == null ? b.pausedWith! : Duration(microseconds: b.endsAt!.microsecondsSinceEpoch);
    // Paused ones after every running one.
    if ((a.endsAt == null) != (b.endsAt == null)) return a.endsAt == null ? 1 : -1;
    return left.compareTo(right);
  }

  /// Every timer, soonest first; paused ones last.
  List<DVTimer> get all => List<DVTimer>.unmodifiable(_timers);

  /// The ones whose time has come.
  List<DVTimer> get ringing => <DVTimer>[
        for (final DVTimer timer in _timers)
          if (timer.stateAt(_now()) == .ringing) timer,
      ];

  /// The clock the service counts against, for a widget drawing a countdown.
  DateTime get now => _now();

  /// Whether a timer here rings with the app closed.
  DVTimerReach get reach => _delivery.reach;

  Future<DVTimerPermission> permission() => _delivery.permission();

  /// Every change, and once a second while a timer counts down.
  Stream<List<DVTimer>> get changes => _changes.stream;

  /// The timers, rebuilding [context] on every change and every second while
  /// one counts down.
  List<DVTimer> watch(BuildContext context) {
    final Element element = context as Element;
    if (_watchers[element] == null) {
      late final StreamSubscription<List<DVTimer>> subscription;
      subscription = changes.listen((List<DVTimer> _) {
        if (element.mounted) {
          element.markNeedsBuild();
          return;
        }
        _watchers[element] = null;
        unawaited(subscription.cancel());
      });
      _watchers[element] = subscription;
    }
    return all;
  }

  static final Expando<StreamSubscription<List<DVTimer>>> _watchers =
      Expando<StreamSubscription<List<DVTimer>>>('DV.Timers');

  /// Starts a timer of [duration] called [label].
  ///
  /// Call it from the tap that starts it: that gesture is what lets a browser
  /// ask for notifications and play sound later. An [id] the application
  /// chooses (a recipe step) makes a second start of a running timer give the
  /// running one back. [route] is the page a click on its notification opens.
  Future<DVTimer> start(String label, Duration duration, {String? id, String? route}) async {
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', 'a timer needs a length');
    }
    _delivery.prime();
    final DateTime now = _now();
    if (id != null) {
      for (final DVTimer existing in _timers) {
        if (existing.id == id && existing.stateAt(now) != .ringing) return existing;
      }
      _timers.removeWhere((DVTimer timer) => timer.id == id);
    }
    final DVTimer timer = DVTimer(
      id: id ?? _newId(now),
      label: label,
      duration: duration,
      endsAt: now.add(duration),
      route: route,
    );
    _timers.add(timer);
    _changed();
    await _askOnce();
    await _delivery.schedule(timer);
    return timer;
  }

  /// Adds [by]: to a ringing timer from now (a snooze), to a running or
  /// paused one on top of what is left.
  Future<void> snooze(String id, Duration by) async {
    final DVTimer? timer = _find(id);
    if (timer == null) return;
    final DateTime now = _now();
    final DVTimer next = switch (timer.stateAt(now)) {
      .ringing => timer.runningUntil(now.add(by)),
      .running => timer.runningUntil(timer.endsAt!.add(by)),
      .paused => timer.pausedWithLeft(timer.pausedWith! + by),
    };
    _replace(next);
    await _delivery.silence(id);
    if (next.endsAt != null) await _delivery.schedule(next);
  }

  /// Stops [id] for good: silent, its notification gone, forgotten.
  Future<void> dismiss(String id) async {
    if (_find(id) == null) return;
    _timers.removeWhere((DVTimer timer) => timer.id == id);
    _changed();
    await _delivery.silence(id);
    await _delivery.cancel(id);
  }

  Future<void> pause(String id) async {
    final DVTimer? timer = _find(id);
    if (timer == null || timer.stateAt(_now()) != .running) return;
    _replace(timer.pausedWithLeft(timer.remainingAt(_now())));
    await _delivery.cancel(id);
  }

  Future<void> resume(String id) async {
    final DVTimer? timer = _find(id);
    if (timer == null || timer.pausedWith == null) return;
    final DVTimer next = timer.runningUntil(_now().add(timer.pausedWith!));
    _replace(next);
    await _delivery.schedule(next);
  }

  /// Rings every timer that has fallen due and has not rung yet. The service
  /// calls it when the nearest one is due; also safe to call at any time.
  void checkDue() {
    final DateTime now = _now();
    bool changed = false;
    for (final DVTimer timer in List<DVTimer>.of(_timers)) {
      if (timer.stateAt(now) == .ringing && timer.alertedAt == null) {
        final DVTimer rung = timer.alertedAtTime(now);
        _timers[_timers.indexOf(timer)] = rung;
        changed = true;
        unawaited(_delivery.ring(rung));
      }
    }
    if (changed) {
      _changed();
    } else {
      _arm();
    }
  }

  /// Reads the store again: another tab of the same app changed it.
  void reload() {
    _timers = dvDecodeTimers(_store.read()).toList()..sort(_soonestFirst);
    _arm();
    _changes.add(all);
  }

  void dispose() {
    _due?.cancel();
    _ticker?.cancel();
    unawaited(_actions.cancel());
  }

  Future<void> _askOnce() async {
    if (_asked) return;
    _asked = true;
    if (await _delivery.permission() == .notAsked) await _delivery.requestPermission();
  }

  void _onAction(DVTimerAction action) {
    switch (action.kind) {
      case .snooze:
        unawaited(snooze(action.id, action.by));
      case .dismiss:
        unawaited(dismiss(action.id));
      case .open:
        // A click on the notification: the person has seen it. The timer
        // stops ringing and goes, as a kitchen timer's button does.
        unawaited(dismiss(action.id));
    }
  }

  DVTimer? _find(String id) {
    for (final DVTimer timer in _timers) {
      if (timer.id == id) return timer;
    }
    return null;
  }

  void _replace(DVTimer next) {
    final int index = _timers.indexWhere((DVTimer timer) => timer.id == next.id);
    if (index < 0) return;
    _timers[index] = next;
    _changed();
  }

  void _changed() {
    _timers.sort(_soonestFirst);
    _store.write(dvEncodeTimers(_timers));
    _arm();
    _changes.add(all);
  }

  /// One timer for the nearest end, and a one-second ticker while anything
  /// counts down so a countdown on screen moves. Nothing at all when no
  /// timer runs.
  void _arm() {
    _due?.cancel();
    _due = null;
    final DateTime now = _now();
    DateTime? next;
    bool counting = false;
    for (final DVTimer timer in _timers) {
      final DateTime? end = timer.endsAt;
      if (end == null) continue;
      if (timer.alertedAt == null) {
        if (next == null || end.isBefore(next)) next = end;
      }
      if (now.isBefore(end)) counting = true;
    }
    if (next != null) {
      final Duration wait = next.difference(now);
      _due = Timer(wait.isNegative ? Duration.zero : wait, checkDue);
    }
    if (counting) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (Timer _) {
        _changes.add(all);
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  static final Random _random = Random();

  static String _newId(DateTime now) =>
      '${now.microsecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 20).toRadixString(36)}';
}
