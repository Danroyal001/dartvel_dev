/// Startup, measured.
///
/// An embedded device's startup is a number somebody has to answer for: a
/// kiosk that takes eleven seconds to show its first screen is a fault, and
/// "it feels slow" is not a report. The framework marks the phases it goes
/// through, and the profile is what they took, in the order they happened,
/// from one monotonic clock.
///
/// Deterministic, which is the word the specification uses and the reason
/// this is not a log: the phases are named, the order is the order they
/// happened in, and the report is the same shape every run -- so two runs of
/// the same build are comparable line by line and a regression is visible
/// rather than argued about.
library;

/// One phase of startup: what it was, when it ended, and how long it took.
class DVStartupPhase {
  const DVStartupPhase({required this.name, required this.at, required this.elapsed});

  final String name;

  /// How far into startup this phase ended.
  final Duration at;

  /// How long it took, measured from the phase before it.
  final Duration elapsed;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'atMicros': at.inMicroseconds,
        'elapsedMicros': elapsed.inMicroseconds,
      };
}

/// A phase, or the whole startup, that went over its budget.
class DVStartupFinding {
  const DVStartupFinding({required this.name, required this.took, required this.budget});

  /// The phase's name, or `startup` for the whole of it.
  final String name;
  final Duration took;
  final Duration budget;

  /// How far over it went, which is the number to act on.
  Duration get by => took - budget;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'tookMicros': took.inMicroseconds,
        'budgetMicros': budget.inMicroseconds,
        'byMicros': by.inMicroseconds,
      };
}

class DVStartupProfile {
  DVStartupProfile({int Function()? nowMicros}) : _now = nowMicros ?? _stopwatchMicros;

  /// One monotonic clock, started when this library is first touched --
  /// which is as close to the process starting as Dart can see. A wall
  /// clock would make a profile that changes when the device syncs its time.
  static final Stopwatch _stopwatch = Stopwatch()..start();
  static int _stopwatchMicros() => _stopwatch.elapsedMicroseconds;

  /// The framework's own profile. Startup happens once, so there is one.
  static final DVStartupProfile current = DVStartupProfile();

  final int Function() _now;
  final List<DVStartupPhase> _phases = <DVStartupPhase>[];
  int _last = 0;

  /// The phases so far, in the order they happened.
  List<DVStartupPhase> get phases => List<DVStartupPhase>.unmodifiable(_phases);

  /// From the start to the last mark.
  Duration get total => _phases.isEmpty ? Duration.zero : _phases.last.at;

  /// Records that [name] has just finished.
  ///
  /// A name marked twice replaces the first: a hot restart runs the same
  /// marks again, and two phases of one name is a report nobody can read.
  void mark(String name) {
    final int at = _now();
    final int index = _phases.indexWhere((DVStartupPhase p) => p.name == name);
    // A phase runs from the end of the one before it. For a replacement
    // that is the phase before it in the list, not this phase's own earlier
    // end -- measuring from that would report a hot restart's first phase as
    // the gap since the last run.
    final int since = index < 0
        ? _last
        : index == 0
            ? 0
            : _phases[index - 1].at.inMicroseconds;
    final DVStartupPhase phase = DVStartupPhase(
      name: name,
      at: Duration(microseconds: at),
      elapsed: Duration(microseconds: at - since),
    );
    if (index >= 0) {
      _phases[index] = phase;
    } else {
      _phases.add(phase);
    }
    _last = at;
  }

  /// Everything that went over its budget: each phase over [phaseBudget]
  /// when one is given, and the whole startup over [budget].
  ///
  /// The phases come first, because the phase that went over is what a
  /// developer can act on; a total nobody can attribute is a number people
  /// learn to ignore.
  List<DVStartupFinding> over(Duration budget, {Duration? phaseBudget}) => <DVStartupFinding>[
        if (phaseBudget != null)
          for (final DVStartupPhase phase in _phases)
            if (phase.elapsed > phaseBudget)
              DVStartupFinding(name: phase.name, took: phase.elapsed, budget: phaseBudget),
        if (total > budget) DVStartupFinding(name: 'startup', took: total, budget: budget),
      ];

  /// Forgets every phase. For a hot restart, and for tests.
  void reset() {
    _phases.clear();
    _last = 0;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'totalMicros': total.inMicroseconds,
        'phases': <Map<String, Object?>>[for (final DVStartupPhase p in _phases) p.toJson()],
      };
}
