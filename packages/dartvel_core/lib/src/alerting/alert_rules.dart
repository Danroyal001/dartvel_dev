/// Alert rules: typed configuration over a measured signal, with state,
/// deduplication, and delivery through the notification channels an
/// application already has.
library;

import 'dart:async';
import 'dart:convert';

import '../../dartvel.dart';
import 'alert_diagnostics.dart';

/// When a reading breaches.
///
/// The threshold is a number, or a [Duration] for a trace signal. The two are
/// never compared with each other: 800 against a latency in microseconds is a
/// rule that never fires, and one in seconds a rule that always does.
class DVAlertWhen {
  const DVAlertWhen.above(this.threshold) : above = true;
  const DVAlertWhen.below(this.threshold) : above = false;

  final Object threshold;
  final bool above;

  bool _breached(DVSignalReading reading) {
    final Object limit = threshold;
    if (limit is Duration) {
      final Duration? value = reading.duration;
      if (value == null) return false;
      return above ? value > limit : value < limit;
    }
    final num? value = reading.value;
    if (value == null || limit is! num) return false;
    return above ? value > limit : value < limit;
  }

  String _describe() {
    final Object limit = threshold;
    final String text =
        limit is Duration ? '${limit.inMilliseconds}ms' : '$limit';
    return '${above ? 'above' : 'below'} $text';
  }
}

enum DVAlertTargetKind { user, team, pager }

/// Who hears about it.
class DVAlertTarget {
  /// A recipient id, delivered through `DV.Notifications`.
  const DVAlertTarget.user(this.name) : kind = DVAlertTargetKind.user;

  /// A team, resolved to recipient ids by the application's team resolver.
  const DVAlertTarget.team(this.name) : kind = DVAlertTargetKind.team;

  /// A registered pager adapter -- PagerDuty and its kind own the rota.
  const DVAlertTarget.pager(this.name) : kind = DVAlertTargetKind.pager;

  final DVAlertTargetKind kind;
  final String name;

  @override
  String toString() => '${kind.name}:$name';
}

/// A rule.
class DVAlertRule {
  const DVAlertRule({
    required this.name,
    required this.signal,
    required this.condition,
    required this.forDuration,
    this.notify = const <DVAlertTarget>[],
    this.resolveAfter,
    this.repeatEvery,
    this.channels = const <DVNotificationChannel>[
      DVNotificationChannel.email,
      DVNotificationChannel.push,
      DVNotificationChannel.inApp,
    ],
  });

  final String name;
  final DVSignalRef signal;
  final DVAlertWhen condition;

  /// How long the condition must hold before the rule fires. Required and
  /// positive: a rule that fires on one sample fires on a garbage-collection
  /// pause, and gets muted.
  final Duration forDuration;
  final List<DVAlertTarget> notify;

  /// How long the condition must stay clear before the alert resolves.
  ///
  /// Defaults to [forDuration] or five minutes, whichever is longer. Resolving
  /// the moment a reading dips under the threshold turns a signal hovering at
  /// it into a page on every crossing.
  final Duration? resolveAfter;

  /// Re-notify while still firing, at this interval. Off by default.
  final Duration? repeatEvery;

  /// The channels recipients are notified on.
  final List<DVNotificationChannel> channels;

  Duration get effectiveResolveAfter {
    final Duration? explicit = resolveAfter;
    if (explicit != null) return explicit;
    const Duration floor = Duration(minutes: 5);
    return forDuration > floor ? forDuration : floor;
  }
}

enum DVAlertStatus { inactive, pending, firing }

/// A rule's state, as of the last evaluation.
class DVAlertState {
  const DVAlertState({
    required this.status,
    this.pendingSince,
    this.firingSince,
    this.delivered = false,
    this.incidentId,
    this.dedupKey,
    this.resolvingSince,
    this.deliveredTo = const <String>{},
    this.missed = const <String, String>{},
    this.lastNotifiedAt,
  });

  final DVAlertStatus status;
  final DateTime? pendingSince;
  final DateTime? firingSince;

  /// While firing: since when the condition has been clear. The alert
  /// resolves once that has lasted the rule's resolve delay; null while the
  /// breach holds.
  final DateTime? resolvingSince;

  /// Whether this firing reached at least one target.
  ///
  /// At least one, not all: [missed] names the rest.
  final bool delivered;

  /// The `user:<id>` and `pager:<name>` keys this firing reached.
  final Set<String> deliveredTo;

  /// The targets this firing has not reached, keyed `user:<id>`,
  /// `pager:<name>` or `team:<name>` (a team that could not be resolved to
  /// anyone), with the reason from the latest attempt. Each is tried again at
  /// the next evaluation while the alert fires.
  final Map<String, String> missed;

  /// When this firing last reached somebody, or was first attempted.
  final DateTime? lastNotifiedAt;
  final String? incidentId;

  /// The key this firing is known by to pagers.
  final String? dedupKey;
}

/// What a pager is told.
class DVAlertEvent {
  const DVAlertEvent({
    required this.rule,
    required this.dedupKey,
    required this.summary,
    required this.at,
  });

  final String rule;

  /// One per firing episode, shared by its trigger, its repeats and its
  /// resolve. A resolve under any other key leaves the pager's incident open.
  final String dedupKey;
  final String summary;
  final DateTime at;
}

/// A PagerDuty-class service.
abstract class DVAlertPager {
  Future<void> trigger(DVAlertEvent event);
  Future<void> resolve(DVAlertEvent event);
}

/// A pager refused or could not be reached.
class DVAlertDeliveryException implements Exception {
  const DVAlertDeliveryException(this.message);
  final String message;

  @override
  String toString() => 'DVAlertDeliveryException: $message';
}

/// PagerDuty, through its Events API v2.
class DVPagerDutyPager implements DVAlertPager {
  DVPagerDutyPager({
    required this.routingKey,
    this.source = 'dartvel',
    this.severity = 'critical',
    DVHttpSend? send,
  }) : _send = send ?? dvSendHttpRequest;

  /// The integration's routing key. A credential: it is never put in an
  /// exception message, which is where log lines come from.
  final String routingKey;
  final String source;

  /// `critical`, `error`, `warning` or `info`.
  final String severity;
  final DVHttpSend _send;

  static final Uri endpoint =
      Uri.parse('https://events.pagerduty.com/v2/enqueue');

  @override
  Future<void> trigger(DVAlertEvent event) => _post('trigger', event,
      <String, Object?>{
        'payload': <String, Object?>{
          // The API rejects a summary past 1024 characters, and a rejected
          // trigger is a page that never happened.
          'summary': event.summary.length > 1024
              ? event.summary.substring(0, 1024)
              : event.summary,
          'source': source,
          'severity': severity,
          'timestamp': event.at.toUtc().toIso8601String(),
        },
      });

  @override
  Future<void> resolve(DVAlertEvent event) =>
      _post('resolve', event, const <String, Object?>{});

  Future<void> _post(
    String action,
    DVAlertEvent event,
    Map<String, Object?> extra,
  ) async {
    final DVHttpResponse response = await _send(DVHttpRequest(
      url: endpoint,
      method: 'POST',
      headers: const <String, String>{'content-type': 'application/json'},
      body: utf8.encode(jsonEncode(<String, Object?>{
        'routing_key': routingKey,
        'event_action': action,
        'dedup_key': event.dedupKey,
        ...extra,
      })),
    ));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Status only: the body of a rejection can quote the request back.
      throw DVAlertDeliveryException(
          'PagerDuty refused the $action for ${event.dedupKey}: '
          'HTTP ${response.statusCode}');
    }
  }
}

/// Resolves a team name to recipient ids.
typedef DVAlertTeamResolver = Future<List<String>> Function(String team);

/// One firing of a rule, from fire to resolve, and what people did about it.
class DVAlertEpisode {
  DVAlertEpisode({
    required this.rule,
    required this.firedAt,
    this.resolvedAt,
    this.acknowledgedAt,
    this.action,
  });

  final String rule;
  final DateTime firedAt;
  DateTime? resolvedAt;
  DateTime? acknowledgedAt;

  /// What was changed because of it. An episode with none is one somebody
  /// looked at and let pass.
  String? action;
}

/// Something `dartvel analyze` reports about a rule.
class DVAlertFinding {
  const DVAlertFinding({
    required this.code,
    required this.rule,
    required this.message,
  });

  final String code;
  final String rule;
  final String message;

  @override
  String toString() => '$code $rule: $message';
}

class _PendingResolve {
  const _PendingResolve(this.pager, this.event);
  final String pager;
  final DVAlertEvent event;
}

class _RuleState {
  _RuleState(this.rule);

  final DVAlertRule rule;
  DVAlertStatus status = DVAlertStatus.inactive;
  DateTime? pendingSince;
  DateTime? firingSince;
  DateTime? clearSince;
  DateTime? lastNotifiedAt;
  int episodeNumber = 0;
  String? dedupKey;
  String? incidentId;
  String summary = '';

  /// `user:<id>` and `pager:<name>` keys this firing reached.
  final Set<String> delivered = <String>{};

  /// Targets not reached, with why, as of the latest attempt.
  final Map<String, String> missed = <String, String>{};
  bool reportedUndelivered = false;
  bool reportedMissing = false;
}

/// The rule engine.
class DVAlerting {
  DVAlerting({
    required this.readers,
    DVNotificationsService notifications = const DVNotificationsService(),
    Map<String, DVAlertPager> pagers = const <String, DVAlertPager>{},
    DVAlertTeamResolver? teams,
    this.incidents,
    void Function(String code, String message)? onDiagnostic,
  })  : _notifications = notifications,
        _pagers = Map<String, DVAlertPager>.of(pagers),
        _teams = teams,
        _diagnose = onDiagnostic ?? dvLogAlertDiagnostic;

  final DVSignalReaders readers;
  final DVIncidents? incidents;
  final DVNotificationsService _notifications;
  final Map<String, DVAlertPager> _pagers;
  final DVAlertTeamResolver? _teams;
  final void Function(String code, String message) _diagnose;

  final Map<String, _RuleState> _rules = <String, _RuleState>{};
  final Map<String, List<DVAlertEpisode>> _episodes =
      <String, List<DVAlertEpisode>>{};
  final List<_PendingResolve> _pendingResolves = <_PendingResolve>[];
  bool _evaluating = false;
  Timer? _timer;

  /// How long episode history is kept for noise analysis.
  static const Duration episodeRetention = Duration(days: 30);

  List<DVAlertRule> get rules =>
      <DVAlertRule>[for (final _RuleState s in _rules.values) s.rule];

  void registerPager(String name, DVAlertPager pager) => _pagers[name] = pager;

  void addRule(DVAlertRule rule) {
    if (rule.forDuration <= Duration.zero) {
      throw ArgumentError.value(rule.forDuration, 'forDuration',
          'a rule that fires on a single sample fires on a pause; give it a '
          'positive duration');
    }
    final Duration? resolveAfter = rule.resolveAfter;
    if (resolveAfter != null && resolveAfter < Duration.zero) {
      throw ArgumentError.value(resolveAfter, 'resolveAfter', 'is negative');
    }
    final Object threshold = rule.condition.threshold;
    if (rule.signal.measuresDuration ? threshold is! Duration : threshold is! num) {
      throw ArgumentError.value(
        threshold,
        'condition',
        rule.signal.measuresDuration
            ? '${rule.signal} is a duration; give the threshold as a Duration'
            : '${rule.signal} is a number; give the threshold as a number',
      );
    }
    if (_rules.containsKey(rule.name)) {
      throw ArgumentError.value(
          rule.name, 'name', 'a rule with this name is already declared');
    }
    _rules[rule.name] = _RuleState(rule);
    if (rule.notify.isEmpty) {
      _diagnose('DV-ALERT-005',
          'rule ${rule.name} has no target; when it fires nobody hears');
    }
  }

  DVAlertState state(String rule) {
    final _RuleState? s = _rules[rule];
    if (s == null) {
      throw ArgumentError.value(rule, 'rule', 'no rule with this name');
    }
    return DVAlertState(
      status: s.status,
      pendingSince: s.pendingSince,
      firingSince: s.firingSince,
      delivered: s.delivered.isNotEmpty,
      incidentId: s.incidentId,
      dedupKey: s.status == DVAlertStatus.firing ? s.dedupKey : null,
      resolvingSince: s.status == DVAlertStatus.firing ? s.clearSince : null,
      deliveredTo: Set<String>.unmodifiable(s.delivered),
      missed: Map<String, String>.unmodifiable(s.missed),
      lastNotifiedAt: s.lastNotifiedAt,
    );
  }

  /// The pagers still owed a resolve for [rule]: each refused it, and it
  /// stays queued until the pager takes it.
  List<String> pendingResolves(String rule) => <String>[
        for (final _PendingResolve item in _pendingResolves)
          if (item.event.rule == rule) item.pager,
      ];

  /// Evaluates every rule on [interval] until [stop].
  void start({Duration interval = const Duration(minutes: 1)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => evaluate(now: DateTime.now()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Samples service levels, reads every rule's signal, and moves each rule
  /// through inactive, pending and firing.
  ///
  /// An evaluation still delivering when the next is due is not overlapped:
  /// two at once would both see a rule as newly firing and page twice.
  Future<void> evaluate({required DateTime now}) async {
    if (_evaluating) return;
    _evaluating = true;
    try {
      readers.serviceLevels?.sample(now);
      await _retryResolves();
      for (final _RuleState s in _rules.values) {
        await _evaluateRule(s, now);
      }
    } finally {
      _evaluating = false;
    }
  }

  Future<void> _evaluateRule(_RuleState s, DateTime now) async {
    final DVAlertRule rule = s.rule;
    final DVSignalReading reading = readers.read(rule.signal, now: now);

    if (reading.status == DVSignalReadingStatus.missing) {
      // Neither a breach nor a recovery. A renamed metric announced as
      // resolved is a lie told at the moment nobody can see the signal.
      if (!s.reportedMissing) {
        s.reportedMissing = true;
        _diagnose('DV-ALERT-006',
            'rule ${rule.name} reads ${rule.signal}, which does not exist'
            '${reading.detail == null ? '' : ': ${reading.detail}'}');
      }
      return;
    }
    s.reportedMissing = false;

    // No data is not a breach. A signal that stopped reporting resolves on
    // the same terms as one that recovered, rather than firing forever.
    final bool breach = reading.status == DVSignalReadingStatus.value &&
        rule.condition._breached(reading);

    switch (s.status) {
      case DVAlertStatus.inactive:
        if (breach) {
          s.status = DVAlertStatus.pending;
          s.pendingSince = now;
        }
      case DVAlertStatus.pending:
        if (!breach) {
          s.status = DVAlertStatus.inactive;
          s.pendingSince = null;
        } else if (now.difference(s.pendingSince!) >= rule.forDuration) {
          await _fire(s, reading, now);
        }
      case DVAlertStatus.firing:
        if (breach) {
          s.clearSince = null;
          await _deliverFiring(s, now, repeat: false);
          final Duration? repeat = rule.repeatEvery;
          if (repeat != null &&
              s.lastNotifiedAt != null &&
              now.difference(s.lastNotifiedAt!) >= repeat) {
            await _deliverFiring(s, now, repeat: true);
          }
        } else {
          s.clearSince ??= now;
          if (now.difference(s.clearSince!) >= rule.effectiveResolveAfter) {
            await _resolve(s, now);
          } else {
            await _deliverFiring(s, now, repeat: false);
          }
        }
    }
  }

  Future<void> _fire(_RuleState s, DVSignalReading reading, DateTime now) async {
    final DVAlertRule rule = s.rule;
    s
      ..status = DVAlertStatus.firing
      ..firingSince = now
      ..clearSince = null
      ..lastNotifiedAt = null
      ..episodeNumber += 1
      ..delivered.clear()
      ..missed.clear()
      ..reportedUndelivered = false;
    s.dedupKey = '${rule.name}#${now.toUtc().microsecondsSinceEpoch}';
    final String value = reading.duration != null
        ? '${reading.duration!.inMilliseconds}ms'
        : '${reading.value}';
    s.summary = '${rule.signal} is $value, ${rule.condition._describe()}, '
        'for ${_describe(rule.forDuration)}';

    _addEpisode(DVAlertEpisode(rule: rule.name, firedAt: now), now);

    final DVIncidents? store = incidents;
    if (store != null) {
      try {
        final DVIncident incident = await store.openIncident(
          title: 'Alert ${rule.name}',
          message: 'alert ${rule.name} fired: ${s.summary}',
          rule: rule.name,
          source: 'alert',
          now: now,
        );
        s.incidentId = incident.id;
      } on Object catch (error) {
        // An incident store that is down must not be what stops the page.
        _diagnose('DV-ALERT-002',
            'rule ${rule.name} could not open an incident: $error');
      }
    }

    await _deliverFiring(s, now, repeat: false);
  }

  /// Delivers the firing notice to every target it has not reached yet, or
  /// to every target again when [repeat].
  Future<void> _deliverFiring(
    _RuleState s,
    DateTime now, {
    required bool repeat,
  }) async {
    final DVAlertRule rule = s.rule;
    if (!repeat && s.lastNotifiedAt != null && _allDelivered(s)) return;

    final DVAlertEvent event = DVAlertEvent(
      rule: rule.name,
      dedupKey: s.dedupKey!,
      summary: '${rule.name}: ${s.summary}',
      at: now,
    );
    final DVNotificationMessage message = DVNotificationMessage(
      title: '[FIRING] ${rule.name}',
      body: s.summary,
      channels: rule.channels,
      data: <String, String>{
        'rule': rule.name,
        'state': 'firing',
        'dedupKey': s.dedupKey!,
        if (s.incidentId != null) 'incident': s.incidentId!,
      },
    );

    final bool hadDelivered = s.delivered.isNotEmpty;
    final List<String> failures = <String>[];
    bool reachedAny = false;

    for (final DVAlertTarget target in rule.notify) {
      switch (target.kind) {
        case DVAlertTargetKind.pager:
          final String key = 'pager:${target.name}';
          if (!repeat && s.delivered.contains(key)) continue;
          final DVAlertPager? pager = _pagers[target.name];
          if (pager == null) {
            failures.add('no pager registered as ${target.name}');
            s.missed[key] = failures.last;
            continue;
          }
          try {
            await pager.trigger(event);
            s.delivered.add(key);
            s.missed.remove(key);
            reachedAny = true;
          } on Object catch (error) {
            failures.add('pager ${target.name}: $error');
            s.missed[key] = failures.last;
          }
        case DVAlertTargetKind.user:
        case DVAlertTargetKind.team:
          final int before = failures.length;
          final List<String> recipients = await _recipients(target, failures);
          if (target.kind == DVAlertTargetKind.team) {
            final String teamKey = 'team:${target.name}';
            if (failures.length > before) {
              s.missed[teamKey] = failures.last;
            } else {
              s.missed.remove(teamKey);
            }
          }
          for (final String recipient in recipients) {
            final String key = 'user:$recipient';
            if (!repeat && s.delivered.contains(key)) continue;
            if (await _notify(recipient, message, failures)) {
              s.delivered.add(key);
              s.missed.remove(key);
              reachedAny = true;
            } else {
              s.missed[key] = failures.last;
            }
          }
      }
    }
    s.lastNotifiedAt = repeat || reachedAny || s.lastNotifiedAt == null
        ? now
        : s.lastNotifiedAt;

    if (!hadDelivered && s.delivered.isNotEmpty) {
      _diagnose('DV-ALERT-001',
          'rule ${rule.name} fired and was delivered: ${s.summary}');
    } else if (s.delivered.isEmpty && !s.reportedUndelivered) {
      s.reportedUndelivered = true;
      _diagnose(
        'DV-ALERT-002',
        'rule ${rule.name} fired and reached nobody'
        '${failures.isEmpty ? '' : ': ${failures.join('; ')}'}',
      );
    }
  }

  bool _allDelivered(_RuleState s) {
    for (final DVAlertTarget target in s.rule.notify) {
      if (target.kind == DVAlertTargetKind.pager) {
        if (!s.delivered.contains('pager:${target.name}')) return false;
      } else if (target.kind == DVAlertTargetKind.user) {
        if (!s.delivered.contains('user:${target.name}')) return false;
      } else {
        // A team's membership is only known by asking; ask again.
        return false;
      }
    }
    return true;
  }

  Future<List<String>> _recipients(
    DVAlertTarget target,
    List<String> failures,
  ) async {
    if (target.kind == DVAlertTargetKind.user) return <String>[target.name];
    final DVAlertTeamResolver? teams = _teams;
    if (teams == null) {
      failures.add('no team resolver for team ${target.name}');
      return const <String>[];
    }
    try {
      final List<String> members = await teams(target.name);
      if (members.isEmpty) failures.add('team ${target.name} has no members');
      return members;
    } on Object catch (error) {
      failures.add('team ${target.name}: $error');
      return const <String>[];
    }
  }

  Future<bool> _notify(
    String recipient,
    DVNotificationMessage message,
    List<String> failures,
  ) async {
    try {
      final DVNotificationDelivery delivery =
          await _notifications.send(recipient, message);
      if (delivery.isSilent) {
        failures.add('$recipient: suppressed on every channel');
        return false;
      }
      return true;
    } on Object catch (error) {
      failures.add('$recipient: $error');
      return false;
    }
  }

  Future<void> _resolve(_RuleState s, DateTime now) async {
    final DVAlertRule rule = s.rule;
    final String dedupKey = s.dedupKey!;
    final DVAlertEvent event = DVAlertEvent(
      rule: rule.name,
      dedupKey: dedupKey,
      summary: '${rule.name}: resolved',
      at: now,
    );
    final DVNotificationMessage message = DVNotificationMessage(
      title: '[RESOLVED] ${rule.name}',
      body: '${rule.signal} has been back within its threshold for '
          '${_describe(rule.effectiveResolveAfter)}',
      channels: rule.channels,
      data: <String, String>{
        'rule': rule.name,
        'state': 'resolved',
        'dedupKey': dedupKey,
      },
    );

    // Only those who heard it fire hear it resolve: a resolve for an alert
    // someone never saw is noise of its own.
    for (final String key in s.delivered) {
      if (key.startsWith('pager:')) {
        _pendingResolves.add(_PendingResolve(key.substring(6), event));
      } else {
        await _notify(key.substring(5), message, <String>[]);
      }
    }
    await _retryResolves();

    final List<DVAlertEpisode>? episodes = _episodes[rule.name];
    if (episodes != null && episodes.isNotEmpty) {
      episodes.last.resolvedAt ??= now;
    }

    final String? incidentId = s.incidentId;
    final DVIncidents? store = incidents;
    if (incidentId != null && store != null) {
      try {
        await store.update(
          incidentId,
          message: 'alert ${rule.name} resolved',
          status: DVIncidentStatus.monitoring,
          source: 'alert',
          now: now,
        );
      } on Object {
        // The alert still resolves; the timeline misses a line.
      }
    }

    s
      ..status = DVAlertStatus.inactive
      ..pendingSince = null
      ..firingSince = null
      ..clearSince = null
      ..incidentId = null
      ..delivered.clear()
      ..missed.clear();
  }

  /// A resolve a pager refused stays queued, across evaluations and whatever
  /// the rule does next, until the pager takes it. Dropping it leaves the
  /// pager's incident open for good.
  Future<void> _retryResolves() async {
    if (_pendingResolves.isEmpty) return;
    final List<_PendingResolve> pending =
        List<_PendingResolve>.of(_pendingResolves);
    _pendingResolves.clear();
    for (final _PendingResolve item in pending) {
      final DVAlertPager? pager = _pagers[item.pager];
      try {
        if (pager == null) throw StateError('pager ${item.pager} is gone');
        await pager.resolve(item.event);
      } on Object {
        _pendingResolves.add(item);
      }
    }
  }

  /// Marks the current or latest episode of [rule] acknowledged, recording
  /// what was done about it.
  void acknowledge(String rule, {String? action, required DateTime now}) {
    final List<DVAlertEpisode>? episodes = _episodes[rule];
    if (episodes == null || episodes.isEmpty) {
      throw StateError('rule $rule has not fired');
    }
    final DVAlertEpisode episode = episodes.last;
    episode.acknowledgedAt ??= now;
    if (action != null) episode.action = action;
  }

  List<DVAlertEpisode> episodes(String rule) =>
      List<DVAlertEpisode>.unmodifiable(
          _episodes[rule] ?? const <DVAlertEpisode>[]);

  /// Records a past episode -- history read back from storage.
  void recordEpisode(
    String rule, {
    required DateTime firedAt,
    DateTime? resolvedAt,
    bool acknowledged = false,
    String? action,
  }) {
    _addEpisode(
      DVAlertEpisode(
        rule: rule,
        firedAt: firedAt,
        resolvedAt: resolvedAt,
        acknowledgedAt: acknowledged ? firedAt : null,
        action: action,
      ),
      firedAt,
    );
  }

  void _addEpisode(DVAlertEpisode episode, DateTime now) {
    final List<DVAlertEpisode> list =
        _episodes.putIfAbsent(episode.rule, () => <DVAlertEpisode>[]);
    list.add(episode);
    final DateTime cutoff = now.subtract(episodeRetention);
    list.removeWhere((DVAlertEpisode e) => e.firedAt.isBefore(cutoff));
  }

  /// What `dartvel analyze` reports: rules with no target and rules that fire
  /// routinely without action (`DV-ALERT-005`), and rules naming a signal that
  /// does not exist (`DV-ALERT-006`).
  ///
  /// Routine means firing on at least [minimumDays] distinct days of the
  /// trailing [window] -- days, not episodes, so one bad afternoon of flapping
  /// is not mistaken for a habit -- with no episode in that window recording
  /// an action.
  Future<List<DVAlertFinding>> analyze({
    required DateTime now,
    Duration window = const Duration(days: 7),
    int minimumDays = 5,
  }) async {
    final List<DVAlertFinding> findings = <DVAlertFinding>[];
    final DateTime from = now.subtract(window);
    for (final _RuleState s in _rules.values) {
      final DVAlertRule rule = s.rule;
      if (rule.notify.isEmpty) {
        findings.add(DVAlertFinding(
          code: 'DV-ALERT-005',
          rule: rule.name,
          message: 'has no target; an alert that fires into nothing makes '
              'the dashboard look covered',
        ));
      }

      final DVSignalReading reading = readers.read(rule.signal, now: now);
      if (reading.status == DVSignalReadingStatus.missing) {
        findings.add(DVAlertFinding(
          code: 'DV-ALERT-006',
          rule: rule.name,
          message: 'reads ${rule.signal}, which does not exist'
              '${reading.detail == null ? '' : ': ${reading.detail}'}',
        ));
      }

      final List<DVAlertEpisode> recent = <DVAlertEpisode>[
        for (final DVAlertEpisode e
            in _episodes[rule.name] ?? const <DVAlertEpisode>[])
          if (e.firedAt.isAfter(from) && !e.firedAt.isAfter(now)) e,
      ];
      final Set<String> days = <String>{
        for (final DVAlertEpisode e in recent)
          e.firedAt.toUtc().toIso8601String().substring(0, 10),
      };
      final bool acted = recent.any((DVAlertEpisode e) => e.action != null);
      if (days.length >= minimumDays && !acted) {
        findings.add(DVAlertFinding(
          code: 'DV-ALERT-005',
          rule: rule.name,
          message: 'fired on ${days.length} of the last ${window.inDays} days '
              'and nothing was changed because of it',
        ));
      }
    }
    return findings;
  }

  static String _describe(Duration d) => d.inHours >= 2
      ? '${d.inHours}h'
      : d.inMinutes >= 1
          ? '${d.inMinutes}m'
          : '${d.inSeconds}s';
}
