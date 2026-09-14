/// Crash-free sessions and crash-free users, per release, patch and cohort,
/// and the gate that holds a rollout when they fall.
library;

import 'crash_report.dart';

class _Session {
  _Session(this.installId, this.release, this.patch, this.cohort);

  final String installId;
  final String release;
  final String? patch;
  final String? cohort;
  bool crashed = false;
}

/// The two numbers, and what they were made from.
class DVReleaseHealthNumbers {
  final int sessions;
  final int crashedSessions;
  final int users;
  final int crashedUsers;

  const DVReleaseHealthNumbers({
    required this.sessions,
    required this.crashedSessions,
    required this.users,
    required this.crashedUsers,
  });

  /// Null when no session started: an unknown is not a perfect score.
  double? get crashFreeSessions =>
      sessions == 0 ? null : (sessions - crashedSessions) / sessions;

  double? get crashFreeUsers =>
      users == 0 ? null : (users - crashedUsers) / users;
}

/// Sessions and crashes, as release health counts them.
///
/// The denominator is sessions that **started**. A device a rollout was
/// offered to and that never opened the release is in its cohort — [assign]
/// records that — but not in its health: counting it dilutes a crash on launch
/// into an average that never falls far enough to hold anything.
class DVReleaseHealth {
  final Map<String, _Session> _sessions = <String, _Session>{};
  final Map<String, String?> _cohorts = <String, String?>{};

  /// [installId] was offered [release] in [cohort]. Not a session.
  void assign({
    required String installId,
    required String release,
    String? cohort,
  }) {
    _cohorts['$installId@$release'] = cohort;
  }

  void sessionStarted({
    required String sessionId,
    required String installId,
    required String release,
    String? patch,
    String? cohort,
  }) {
    _sessions[sessionId] = _Session(
      installId,
      release,
      patch,
      cohort ?? _cohorts['$installId@$release'],
    );
  }

  /// The session crashed. A session that never started is not invented.
  void sessionCrashed({required String sessionId}) {
    _sessions[sessionId]?.crashed = true;
  }

  Iterable<_Session> _matching(String release, String? patch, String? cohort) =>
      _sessions.values.where((_Session s) =>
          s.release == release &&
          (patch == null || s.patch == patch) &&
          (cohort == null || s.cohort == cohort));

  DVReleaseHealthNumbers numbers({
    required String release,
    String? patch,
    String? cohort,
  }) {
    final List<_Session> sessions = _matching(release, patch, cohort).toList();
    final Set<String> users = <String>{
      for (final _Session s in sessions) s.installId,
    };
    final Set<String> crashedUsers = <String>{
      for (final _Session s in sessions)
        if (s.crashed) s.installId,
    };
    return DVReleaseHealthNumbers(
      sessions: sessions.length,
      crashedSessions: sessions.where((_Session s) => s.crashed).length,
      users: users.length,
      crashedUsers: crashedUsers.length,
    );
  }

  /// The cohorts [release] has started sessions in, sorted.
  List<String> cohorts({required String release, String? patch}) =>
      <String>{
        for (final _Session s in _matching(release, patch, null))
          if (s.cohort != null) s.cohort!,
      }.toList()
        ..sort();
}

/// What the gate decided.
class DVReleaseHealthDecision {
  final bool hold;

  /// The cohorts below threshold. Empty with [hold] true when it is the
  /// release as a whole.
  final List<String> heldCohorts;

  /// Flags the release staged behind, to turn off when it is held.
  final List<String> flagsToTurnOff;
  final DVReleaseHealthNumbers overall;

  const DVReleaseHealthDecision({
    required this.hold,
    required this.heldCohorts,
    required this.flagsToTurnOff,
    required this.overall,
  });
}

/// Holds a rollout whose health falls below its declared thresholds.
///
/// Read per cohort as well as per release, because a crash that takes only
/// the ten per cent in a rollout disappears into a whole-release average.
class DVReleaseHealthGate {
  DVReleaseHealthGate({
    required this.crashFreeSessions,
    this.crashFreeUsers,
    this.minimumSessions = 1,
    this.stagedFlags = const <String>[],
    void Function(String code, String message)? onDiagnostic,
  }) : _diagnose = onDiagnostic ?? dvLogCrashDiagnostic;

  final double crashFreeSessions;
  final double? crashFreeUsers;

  /// Below this many sessions a number is not read — one crash in one session
  /// is not a rate.
  final int minimumSessions;
  final List<String> stagedFlags;
  final void Function(String code, String message) _diagnose;

  bool _breached(DVReleaseHealthNumbers numbers) {
    if (numbers.sessions < minimumSessions) return false;
    final double sessions = numbers.crashFreeSessions ?? 1;
    if (sessions < crashFreeSessions) return true;
    final double? usersThreshold = crashFreeUsers;
    return usersThreshold != null &&
        (numbers.crashFreeUsers ?? 1) < usersThreshold;
  }

  DVReleaseHealthDecision evaluate(
    DVReleaseHealth health, {
    required String release,
    String? patch,
  }) {
    final DVReleaseHealthNumbers overall =
        health.numbers(release: release, patch: patch);
    final List<String> held = <String>[
      for (final String cohort in health.cohorts(release: release, patch: patch))
        if (_breached(
            health.numbers(release: release, patch: patch, cohort: cohort)))
          cohort,
    ];
    final bool hold = _breached(overall) || held.isNotEmpty;
    if (hold) {
      _diagnose(
        'DV-CRASH-010',
        'release $release${patch == null ? '' : ' patch $patch'} is below its '
        'crash-free threshold'
        '${held.isEmpty ? '' : ' in ${held.join(', ')}'}; the rollout was held',
      );
    }
    return DVReleaseHealthDecision(
      hold: hold,
      heldCohorts: held,
      flagsToTurnOff: hold ? List<String>.unmodifiable(stagedFlags) : const <String>[],
      overall: overall,
    );
  }
}
