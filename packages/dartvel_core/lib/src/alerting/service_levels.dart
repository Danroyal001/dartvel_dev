/// Service levels: an objective, its error budget, and how fast it burns.
///
/// What is alerted on is the burn rate, not the instantaneous success rate. A
/// 99.9% monthly objective allows 43.2 minutes of failure, and an alert on the
/// rate dipping below 99.9% fires on every blip while the month is nowhere
/// near danger. The burn rate says how many times faster than the objective
/// can afford the budget is going.
///
/// Nothing here collects anything. A level reads cumulative request and
/// failure counts from a source that already exists -- a counter, a span
/// exporter, the backend runtime -- and samples them over time.
library;

import 'alert_diagnostics.dart';

/// What a service level promises.
class DVObjective {
  /// [target] of requests succeed, measured over the trailing [over].
  const DVObjective.successRate(this.target, {required this.over});

  final double target;
  final Duration over;

  /// The share of requests allowed to fail.
  double get budget => 1 - target;

  /// How long total failure the window allows: 43.2 minutes for 99.9% over
  /// thirty days.
  Duration get budgetTime =>
      Duration(microseconds: (over.inMicroseconds * budget).round());
}

enum DVAppliesToKind { backendFunction, page, kioskFleet }

/// What an objective is declared against.
class DVAppliesTo {
  const DVAppliesTo.backendFunction(this.name)
      : kind = DVAppliesToKind.backendFunction;
  const DVAppliesTo.page(this.name) : kind = DVAppliesToKind.page;
  const DVAppliesTo.kioskFleet(this.name) : kind = DVAppliesToKind.kioskFleet;

  final DVAppliesToKind kind;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is DVAppliesTo && other.kind == kind && other.name == name;

  @override
  int get hashCode => Object.hash(kind, name);

  @override
  String toString() => '${kind.name}($name)';
}

/// A promise with a budget attached.
class DVServiceLevel {
  const DVServiceLevel({
    required this.name,
    required this.objective,
    required this.applies,
  });

  final String name;
  final DVObjective objective;
  final DVAppliesTo applies;
}

/// Cumulative counts as a source reports them: everything since the source
/// started, which is how a counter reads.
class DVServiceLevelCounts {
  const DVServiceLevelCounts({required this.total, required this.failed});

  final num total;
  final num failed;
}

/// Reads the current cumulative counts, or null when they cannot be read.
typedef DVServiceLevelSource = DVServiceLevelCounts? Function();

/// Where a service level stands.
class DVServiceLevelStatus {
  const DVServiceLevelStatus({
    required this.level,
    this.errorRate,
    this.budgetConsumed,
    this.coverage,
    this.requests,
  });

  final DVServiceLevel level;

  /// Failed over total, across the observed part of the window. Null when no
  /// request was observed.
  final double? errorRate;

  /// The share of the window's budget used so far. Above 1 is past it.
  ///
  /// Null when there is nothing to read -- no source, fewer than two samples,
  /// or samples with no request between them -- because an unknown is not a
  /// clean month. The last is the one that looks like one: a service that
  /// stopped answering sends nothing to count, and 0 consumed would show its
  /// budget full for exactly the outage the budget is there to catch.
  final double? budgetConsumed;

  /// The share of the objective's window the samples span, at most 1.
  final double? coverage;

  /// Requests observed across the window; 0 when samples were read and none
  /// arrived, null when fewer than two samples were read.
  final double? requests;

  /// Whether the budget was measured. False for each of the unknowns
  /// [budgetConsumed] describes; [requests] says which one it is.
  bool get hasData => budgetConsumed != null;

  double? get budgetRemaining =>
      budgetConsumed == null ? null : 1 - budgetConsumed!;

  bool get exhausted => budgetConsumed != null && budgetConsumed! >= 1;
}

class _Sample {
  _Sample(this.at, this.rawTotal, this.rawFailed, this.total, this.failed);

  final DateTime at;

  /// What the source said.
  final double rawTotal;
  final double rawFailed;

  /// Increases accumulated since the first sample, across restarts.
  final double total;
  final double failed;
}

class _Window {
  const _Window(this.total, this.failed, this.span);

  final double total;
  final double failed;
  final Duration span;
}

/// The declared service levels, their sources, and their sampled history.
class DVServiceLevels {
  DVServiceLevels({void Function(String code, String message)? onDiagnostic})
      : _diagnose = onDiagnostic ?? dvLogAlertDiagnostic;

  final void Function(String code, String message) _diagnose;
  final Map<String, DVServiceLevel> _levels = <String, DVServiceLevel>{};
  final Map<DVAppliesTo, DVServiceLevelSource> _sources =
      <DVAppliesTo, DVServiceLevelSource>{};
  final Map<String, List<_Sample>> _history = <String, List<_Sample>>{};
  final Set<String> _exhausted = <String>{};

  /// The declared levels, in the order they were added.
  List<DVServiceLevel> get levels => List<DVServiceLevel>.unmodifiable(
      _levels.values);

  bool has(String name) => _levels.containsKey(name);

  void add(DVServiceLevel level) {
    final double target = level.objective.target;
    // 1 leaves no budget, so every burn rate divides by zero; 0 promises
    // nothing and every failure rate reads as within budget.
    if (!(target > 0 && target < 1)) {
      throw ArgumentError.value(target, 'target',
          'a success-rate objective is between 0 and 1, exclusive');
    }
    if (level.objective.over <= Duration.zero) {
      throw ArgumentError.value(level.objective.over, 'over',
          'an objective is measured over a positive window');
    }
    if (_levels.containsKey(level.name)) {
      throw ArgumentError.value(level.name, 'name',
          'a service level with this name is already declared');
    }
    _levels[level.name] = level;
    _history[level.name] = <_Sample>[];
  }

  /// Where the counts for [applies] come from.
  void source(DVAppliesTo applies, DVServiceLevelSource source) {
    _sources[applies] = source;
  }

  void removeSource(DVAppliesTo applies) => _sources.remove(applies);

  /// Reads every source once and records the counts as of [now].
  ///
  /// Reports `DV-ALERT-003` when a budget becomes exhausted: once, and again
  /// only after it has recovered and been exhausted a second time.
  void sample(DateTime now) {
    for (final DVServiceLevel level in _levels.values) {
      final DVServiceLevelSource? source = _sources[level.applies];
      final DVServiceLevelCounts? counts = source?.call();
      if (counts == null) continue;

      final List<_Sample> history = _history[level.name]!;
      final double rawTotal = counts.total.toDouble();
      final double rawFailed = counts.failed.toDouble();
      final _Sample? last = history.isEmpty ? null : history.last;
      if (last != null && !now.isAfter(last.at)) continue;

      if (last == null) {
        history.add(_Sample(now, rawTotal, rawFailed, 0, 0));
      } else {
        // One source, one process: if either count went down, both started
        // again. Deciding per counter misses the restart whenever the failure
        // count comes back higher than it was -- 10 failures, restart, 50 more
        // reads as 40 -- and undercounts exactly the outage that restarted it.
        final bool restarted =
            rawTotal < last.rawTotal || rawFailed < last.rawFailed;
        history.add(_Sample(
          now,
          rawTotal,
          rawFailed,
          last.total + (restarted ? rawTotal : rawTotal - last.rawTotal),
          last.failed + (restarted ? rawFailed : rawFailed - last.rawFailed),
        ));
      }
      _prune(history, now.subtract(level.objective.over));

      final DVServiceLevelStatus current = status(level.name, now: now);
      if (current.exhausted) {
        if (_exhausted.add(level.name)) {
          _diagnose(
            'DV-ALERT-003',
            'service level ${level.name} has used '
            '${(current.budgetConsumed! * 100).toStringAsFixed(1)}% of its '
            'error budget for the trailing ${_describe(level.objective.over)}',
          );
        }
      } else {
        _exhausted.remove(level.name);
      }
    }
  }

  /// How many times faster than the objective allows the budget is being
  /// spent, over the trailing [window].
  ///
  /// Null for an unknown level and for a window with no requests in it: no
  /// traffic is not a perfect score, and reading it as 0 would resolve a
  /// burn alert on a service that stopped answering altogether.
  double? burnRate(String name, Duration window, {required DateTime now}) {
    final DVServiceLevel? level = _levels[name];
    if (level == null) return null;
    final _Window? observed = _window(_history[name]!, window, now);
    if (observed == null || observed.total <= 0) return null;
    return observed.failed / observed.total / level.objective.budget;
  }

  /// Where [name] stands over its objective's window, as of [now].
  DVServiceLevelStatus status(String name, {required DateTime now}) {
    final DVServiceLevel? level = _levels[name];
    if (level == null) {
      throw ArgumentError.value(name, 'name', 'no service level is declared');
    }
    final Duration over = level.objective.over;
    final _Window? observed = _window(_history[name]!, over, now);
    if (observed == null) return DVServiceLevelStatus(level: level);

    final double coverage =
        (observed.span.inMicroseconds / over.inMicroseconds).clamp(0, 1)
            .toDouble();
    if (observed.total <= 0) {
      return DVServiceLevelStatus(
          level: level, coverage: coverage, requests: 0);
    }
    final double errorRate = observed.failed / observed.total;
    // Scaled by how much of the window was seen. Ten minutes of history read
    // as if it were the whole month turns a ten-minute blip into a month's
    // budget gone; ten minutes of total failure is ten of the 43.2 minutes a
    // 99.9% month allows, whatever came before the process started.
    return DVServiceLevelStatus(
      level: level,
      errorRate: errorRate,
      budgetConsumed: errorRate * coverage / level.objective.budget,
      coverage: coverage,
      requests: observed.total,
    );
  }

  /// Increases between the newest sample at or before [now] and the newest
  /// at or before the start of the window -- or the oldest there is, when the
  /// history does not reach back that far.
  static _Window? _window(List<_Sample> history, Duration window, DateTime now) {
    _Sample? end;
    for (int i = history.length - 1; i >= 0; i--) {
      if (!history[i].at.isAfter(now)) {
        end = history[i];
        break;
      }
    }
    if (end == null) return null;

    final DateTime start = now.subtract(window);
    _Sample base = history.first;
    for (final _Sample sample in history) {
      if (sample.at.isAfter(start)) break;
      base = sample;
    }
    if (identical(base, end)) return null;
    return _Window(
      end.total - base.total,
      end.failed - base.failed,
      end.at.difference(base.at),
    );
  }

  /// Drops samples older than [cutoff], keeping the newest of them as the
  /// baseline the window is measured from.
  static void _prune(List<_Sample> history, DateTime cutoff) {
    int keepFrom = 0;
    for (int i = 0; i < history.length; i++) {
      if (history[i].at.isAfter(cutoff)) break;
      keepFrom = i;
    }
    if (keepFrom > 0) history.removeRange(0, keepFrom);
  }

  static String _describe(Duration window) => window.inHours >= 48
      ? '${window.inDays} days'
      : window.inMinutes >= 120
          ? '${window.inHours} hours'
          : '${window.inMinutes} minutes';
}

/// What the gate decided.
class DVErrorBudgetDecision {
  const DVErrorBudgetDecision({
    required this.hold,
    required this.exhausted,
    this.unmeasured = const <String>[],
  });

  final bool hold;

  /// The levels whose budget is gone, in declaration order.
  final List<String> exhausted;

  /// The levels whose budget could not be read -- no samples, or no request
  /// in the window -- in declaration order.
  ///
  /// They do not hold: this gate holds on a budget known to be spent, and a
  /// quiet service is not one. They are not within budget either, and a
  /// reader that takes "not held" to mean "every budget has room" is told so
  /// here. `DVErrorBudgetReleaseGate` holds a rollout on them.
  final List<String> unmeasured;
}

/// An objective with no budget left, read before a deploy rather than after.
class DVErrorBudgetGate {
  DVErrorBudgetGate(this.levels);

  final DVServiceLevels levels;

  DVErrorBudgetDecision evaluate({required DateTime now}) {
    final List<String> exhausted = <String>[];
    final List<String> unmeasured = <String>[];
    for (final DVServiceLevel level in levels.levels) {
      final DVServiceLevelStatus status = levels.status(level.name, now: now);
      if (status.exhausted) exhausted.add(level.name);
      if (!status.hasData) unmeasured.add(level.name);
    }
    return DVErrorBudgetDecision(
      hold: exhausted.isNotEmpty,
      exhausted: List<String>.unmodifiable(exhausted),
      unmeasured: List<String>.unmodifiable(unmeasured),
    );
  }
}
