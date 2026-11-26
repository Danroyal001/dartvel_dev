/// One countdown, and the words a countdown is read out in.
///
/// Kept as plain values with no Flutter in them: a timer has to be read back
/// from storage after a reload, compared against a clock in a test and shown
/// by a widget, and only the last of those needs a widget.
library dartvel_flutter.timers.timer;

import 'dart:convert';

/// Where a timer is in its life.
enum DVTimerState {
  /// Counting down.
  running,

  /// Stopped with time left; resumes from it.
  paused,

  /// Its time has come and nobody has dismissed or snoozed it.
  ringing,
}

/// One countdown: what it is for and when it ends.
///
/// [endsAt] is a moment, not a number of seconds left, so a timer read back
/// after the tab was closed for ten minutes is ten minutes further on, as a
/// kitchen timer would be. While paused [endsAt] is null and [pausedWith]
/// holds what was left.
final class DVTimer {
  const DVTimer({
    required this.id,
    required this.label,
    required this.duration,
    this.endsAt,
    this.pausedWith,
    this.alertedAt,
    this.route,
  }) : assert(endsAt != null || pausedWith != null, 'a timer either ends at a time or is paused');

  /// Stable for the timer's life. An application that names its own (a
  /// recipe step) gets the running timer back when it starts it twice.
  final String id;

  /// What the timer is for, as the notification and a screen reader say it.
  final String label;

  /// The length it was set to.
  final Duration duration;

  /// When it rings, in UTC. Null while paused.
  final DateTime? endsAt;

  /// What was left when it was paused. Null while running or ringing.
  final Duration? pausedWith;

  /// When it rang, so a reload shows a timer that already rang without
  /// ringing it again. Null until it rings.
  final DateTime? alertedAt;

  /// The page the timer was started from; a click on its notification opens
  /// it. Null opens the application's start page.
  final String? route;

  DVTimerState stateAt(DateTime now) {
    final DateTime? end = endsAt;
    if (end == null) return .paused;
    return now.isBefore(end) ? .running : .ringing;
  }

  /// What is left at [now]; zero once it has rung.
  Duration remainingAt(DateTime now) {
    final DateTime? end = endsAt;
    if (end == null) return pausedWith ?? .zero;
    final Duration left = end.difference(now);
    return left.isNegative ? .zero : left;
  }

  /// How long ago it fell due; zero while it has not.
  Duration overdueAt(DateTime now) {
    final DateTime? end = endsAt;
    if (end == null || now.isBefore(end)) return .zero;
    return now.difference(end);
  }

  DVTimer _running(DateTime end) => DVTimer(id: id, label: label, duration: duration, endsAt: end, route: route);

  DVTimer _paused(Duration left) => DVTimer(id: id, label: label, duration: duration, pausedWith: left, route: route);

  DVTimer _alerted(DateTime at) =>
      DVTimer(id: id, label: label, duration: duration, endsAt: endsAt, pausedWith: pausedWith, alertedAt: at, route: route);

  Map<String, Object?> _json() => <String, Object?>{
        'id': id,
        'label': label,
        'durationMs': duration.inMilliseconds,
        if (endsAt != null) 'endsAt': endsAt!.toUtc().toIso8601String(),
        if (pausedWith != null) 'pausedMs': pausedWith!.inMilliseconds,
        if (alertedAt != null) 'alertedAt': alertedAt!.toUtc().toIso8601String(),
        if (route != null) 'route': route,
      };

  /// One timer read back from storage, or null for anything that is not one.
  /// Storage is written by older and newer builds and can be damaged; a timer
  /// that cannot be read is dropped rather than stopping the others.
  static DVTimer? _fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final Object? id = value['id'];
    final Object? label = value['label'];
    final Object? durationMs = value['durationMs'];
    if (id is! String || id.isEmpty || label is! String || durationMs is! int || durationMs <= 0) return null;
    final DateTime? endsAt = _time(value['endsAt']);
    final Object? pausedMs = value['pausedMs'];
    final Duration? pausedWith = pausedMs is int && pausedMs >= 0 ? Duration(milliseconds: pausedMs) : null;
    if (endsAt == null && pausedWith == null) return null;
    final Object? route = value['route'];
    return DVTimer(
      id: id,
      label: label,
      duration: Duration(milliseconds: durationMs),
      endsAt: pausedWith == null ? endsAt : null,
      pausedWith: pausedWith,
      alertedAt: _time(value['alertedAt']),
      route: route is String && route.startsWith('/') ? route : null,
    );
  }

  static DateTime? _time(Object? value) => value is String ? DateTime.tryParse(value)?.toUtc() : null;

  @override
  String toString() => 'DVTimer($id, $label, ${endsAt ?? 'paused $pausedWith'})';
}

/// The framework's own transitions on a [DVTimer]; not part of the surface an
/// application sees, which goes through `DV.Timers`.
extension DVTimerTransitions on DVTimer {
  DVTimer runningUntil(DateTime end) => _running(end);
  DVTimer pausedWithLeft(Duration left) => _paused(left);
  DVTimer alertedAtTime(DateTime at) => _alerted(at);
}

/// Every timer, as the text one storage key holds.
String dvEncodeTimers(List<DVTimer> timers) =>
    jsonEncode(<String, Object?>{'timers': <Object?>[for (final DVTimer timer in timers) timer._json()]});

/// [text] read back as timers; empty for anything unreadable.
List<DVTimer> dvDecodeTimers(String? text) {
  if (text == null || text.isEmpty) return const <DVTimer>[];
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return const <DVTimer>[];
  }
  if (decoded is! Map<String, Object?>) return const <DVTimer>[];
  final Object? list = decoded['timers'];
  if (list is! List<Object?>) return const <DVTimer>[];
  return <DVTimer>[
    for (final Object? item in list)
      if (DVTimer._fromJson(item) case final DVTimer timer) timer,
  ];
}

/// What a person did to a ringing timer from outside the page: a
/// notification's button, or a notification swiped away.
enum DVTimerActionKind { snooze, dismiss, open }

/// One such action, for the timer [id].
final class DVTimerAction {
  const DVTimerAction(this.id, this.kind, [this.by = .zero]);

  final String id;
  final DVTimerActionKind kind;

  /// How long a snooze is for.
  final Duration by;

  @override
  String toString() => 'DVTimerAction($id, ${kind.name}, $by)';
}

/// The countdown as a clock reads it: `14:05`, `1:02:03`. Rounds up, as a
/// countdown does: with 14.2 seconds left it still says 0:15, and 0:00 is
/// the moment it rings.
String dvTimerClock(Duration left) {
  final int seconds = (left.inMilliseconds / 1000).ceil();
  final int hours = seconds ~/ 3600;
  final int minutes = (seconds % 3600) ~/ 60;
  final String secs = (seconds % 60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:${minutes.toString().padLeft(2, '0')}:$secs';
  return '$minutes:$secs';
}

/// The countdown as a screen reader should hear it.
///
/// It changes once a minute, then at 30 and at 10 seconds, so a polite live
/// region carrying it speaks a handful of times over a fifteen-minute timer
/// instead of every second.
String dvTimerSpoken(Duration left) {
  final int seconds = (left.inMilliseconds / 1000).ceil();
  if (seconds <= 0) return 'Done';
  if (seconds <= 10) return '10 seconds left';
  if (seconds <= 30) return '30 seconds left';
  final int minutes = (seconds / 60).ceil();
  if (minutes < 60) return minutes == 1 ? '1 minute left' : '$minutes minutes left';
  final int hours = minutes ~/ 60;
  final int rest = minutes % 60;
  final String hourWords = hours == 1 ? '1 hour' : '$hours hours';
  if (rest == 0) return '$hourWords left';
  return '$hourWords $rest ${rest == 1 ? 'minute' : 'minutes'} left';
}

/// A length in a few characters, for a button: `15 min`, `1 min 30 s`.
String dvTimerLength(Duration length) {
  final int hours = length.inHours;
  final int minutes = length.inMinutes % 60;
  final int seconds = length.inSeconds % 60;
  return <String>[
    if (hours > 0) '$hours h',
    if (minutes > 0) '$minutes min',
    if (seconds > 0) '$seconds s',
  ].join(' ');
}

/// The action a notification's button or a service worker names, as the
/// framework spells it: `snooze-<minutes>`, `dismiss`, `open`. Null for
/// anything else, so a message from some other code is ignored.
DVTimerAction? dvTimerActionFrom(String id, String action) {
  if (id.isEmpty) return null;
  if (action == 'dismiss') return DVTimerAction(id, .dismiss);
  if (action == 'open' || action.isEmpty) return DVTimerAction(id, .open);
  final RegExpMatch? snooze = RegExp(r'^snooze-(\d{1,3})$').firstMatch(action);
  if (snooze == null) return null;
  final int minutes = int.parse(snooze.group(1)!);
  return minutes <= 0 ? null : DVTimerAction(id, .snooze, Duration(minutes: minutes));
}
