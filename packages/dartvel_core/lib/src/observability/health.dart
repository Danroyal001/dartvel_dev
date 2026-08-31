/// Health checks, which the built-in endpoint did not have.
///
/// `GET /health` returned the literal `{'status':'ok'}`. It checked nothing,
/// so it could not fail -- and a health check that cannot fail is worse than
/// none at all: a load balancer keeps routing to an instance whose database is
/// gone, and the dashboard stays green through the outage.
library dartvel.observability.health;

import 'dart:async';

enum DVHealthStatus {
  up,

  /// Still serving, but something is wrong. A load balancer should keep
  /// sending traffic; a human should look.
  degraded,

  /// Take this instance out of rotation.
  down,
}

/// What one check found.
class DVHealthResult {
  const DVHealthResult(this.status, [this.detail]);

  factory DVHealthResult.up([String? detail]) =>
      DVHealthResult(DVHealthStatus.up, detail);
  factory DVHealthResult.degraded(String detail) =>
      DVHealthResult(DVHealthStatus.degraded, detail);
  factory DVHealthResult.down(String detail) =>
      DVHealthResult(DVHealthStatus.down, detail);

  final DVHealthStatus status;
  final String? detail;

  Map<String, Object?> toJson() => <String, Object?>{
        'status': status.name,
        if (detail != null) 'detail': detail,
      };
}

/// The whole instance, as of one moment.
class DVHealthReport {
  const DVHealthReport({
    required this.status,
    required this.checks,
    required this.uptime,
    this.buildId,
  });

  final DVHealthStatus status;
  final Map<String, DVHealthResult> checks;
  final Duration uptime;
  final String? buildId;

  /// 200 while serving, 503 when out of rotation.
  ///
  /// Degraded stays 200 deliberately: it means "look at this", not "stop
  /// sending traffic", and a 503 would take a slow cache down as if it were a
  /// dead database.
  int get httpStatus => status == DVHealthStatus.down ? 503 : 200;

  Map<String, Object?> toJson() => <String, Object?>{
        'status': status.name,
        'uptime': uptime.inSeconds,
        if (buildId != null) 'build': buildId,
        if (checks.isNotEmpty)
          'checks': <String, Object?>{
            for (final MapEntry<String, DVHealthResult> entry in checks.entries)
              entry.key: entry.value.toJson(),
          },
      };
}

typedef DVHealthCheck = Future<DVHealthResult> Function();

/// The registered checks.
class DVHealth {
  DVHealth({this.timeout = const Duration(seconds: 2), String? buildId})
      : _startedAt = DateTime.now(),
        _buildId = buildId;

  /// How long a single check may take.
  ///
  /// The failure mode that matters is not a check that refuses, it is one that
  /// waits: a database with a dead connection does not answer, and a health
  /// endpoint that waits with it is the outage rather than the report of it.
  final Duration timeout;

  final DateTime _startedAt;
  final String? _buildId;
  final Map<String, DVHealthCheck> _checks = <String, DVHealthCheck>{};

  void register(String name, DVHealthCheck check) => _checks[name] = check;
  void unregister(String name) => _checks.remove(name);
  void clear() => _checks.clear();

  Duration get uptime => DateTime.now().difference(_startedAt);

  /// The report without running anything, for a liveness probe that only
  /// wants to know the process is answering.
  DVHealthReport report() => DVHealthReport(
        status: DVHealthStatus.up,
        checks: const <String, DVHealthResult>{},
        uptime: uptime,
        buildId: _buildId,
      );

  /// Runs every check and summarises.
  ///
  /// Checks run together rather than in turn: a readiness probe that takes the
  /// sum of every dependency's latency starts failing on timeouts of its own
  /// as soon as there are a few of them.
  Future<DVHealthReport> reportAsync() async {
    final Map<String, DVHealthResult> results = <String, DVHealthResult>{};

    await Future.wait(<Future<void>>[
      for (final MapEntry<String, DVHealthCheck> entry in _checks.entries)
        _run(entry.key, entry.value).then((DVHealthResult result) {
          results[entry.key] = result;
        }),
    ]);

    DVHealthStatus worst = DVHealthStatus.up;
    for (final DVHealthResult result in results.values) {
      if (result.status == DVHealthStatus.down) {
        worst = DVHealthStatus.down;
        break;
      }
      if (result.status == DVHealthStatus.degraded) {
        worst = DVHealthStatus.degraded;
      }
    }

    return DVHealthReport(
      status: worst,
      checks: results,
      uptime: uptime,
      buildId: _buildId,
    );
  }

  Future<DVHealthResult> _run(String name, DVHealthCheck check) async {
    // Not Future.timeout. A check written as `() async => throw ...` has a
    // runtime type of Future<Never>, and timeout dispatches on that: it then
    // demands an onTimeout returning Never and rejects one returning a
    // DVHealthResult. The failure surfaces as a type error about onTimeout
    // rather than as the thrown message -- so a check that throws reported
    // the wrong reason for being down, which is the one thing the detail is
    // for.
    final Completer<DVHealthResult> done = Completer<DVHealthResult>();

    final Timer timer = Timer(timeout, () {
      if (!done.isCompleted) {
        done.complete(DVHealthResult.down(
          'timed out after ${timeout.inMilliseconds}ms',
        ));
      }
    });

    try {
      // Deliberately not awaited: the completer above is what this function
      // waits on, so that the timeout can win the race.
      unawaited(check().then(
        (DVHealthResult result) {
          if (!done.isCompleted) done.complete(result);
        },
        onError: (Object error) {
          if (!done.isCompleted) done.complete(DVHealthResult.down('$error'));
        },
      ));
    } on Object catch (error) {
      // A check that throws before returning a future at all.
      if (!done.isCompleted) done.complete(DVHealthResult.down('$error'));
    }

    final DVHealthResult result = await done.future;
    // Cancelled either way, so a slow check that eventually answers does not
    // leave a timer behind holding this closure.
    timer.cancel();
    return result;
  }

}
