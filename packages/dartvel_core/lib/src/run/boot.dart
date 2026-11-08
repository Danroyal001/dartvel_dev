import 'dart:async';

import '../lifecycle/lifecycle.dart';
import '../observability/log.dart';
import 'entry.dart';

/// One `@DVBoot` function as the generator wires it into an entry: the
/// entries it runs in, empty for every entry its code can run in, and the
/// function itself.
class const DVBootStep({
  final Set<DVEntryKind> entries = const <DVEntryKind>{},
  required final FutureOr<void> Function(DVBoot boot) run,
});

bool _booted = false;

/// Runs the application's boot steps for the entry that started this
/// process: the Flutter app, a web server, a worker or cron process, a
/// command. Steps run in the order given (path order, then declaration
/// order) and each is awaited; a step whose entries leave this entry out is
/// skipped. A process boots once, however many times it is asked.
///
/// [onStep] is told the index of each step before it runs, so an entry whose
/// boot fails can name the function that threw (DV-RUN-004).
Future<void> dvRunBoot(
  List<DVBootStep> steps,
  DVBoot boot, {
  void Function(int index)? onStep,
}) async {
  if (_booted) return;
  _booted = true;
  final DVEntryKind kind = boot.entry.kind;
  for (int index = 0; index < steps.length; index++) {
    final DVBootStep step = steps[index];
    if (step.entries.isEmpty || step.entries.contains(kind)) {
      onStep?.call(index);
      await step.run(boot);
    }
  }
}

/// Lets the process boot again: the app entry's retry after a failed boot.
void dvResetBoot() => _booted = false;

/// Lets a test boot again in the same isolate.
void dvResetBootForTest() => dvResetBoot();

/// A boot phase that threw: DV-RUN-004, naming the phase (the boot sequence
/// table in NEW_SPEC.md, Application Entry) and, in phase 4, the `@DVBoot`
/// function that was running.
class DVBootFailure implements Exception {
  DVBootFailure({
    required this.entry,
    required this.phase,
    required this.phaseName,
    required this.error,
    required this.stackTrace,
    this.bootStep,
  });

  /// The entry that was booting.
  final DVEntry entry;

  /// The phase number, 1 to 5.
  final int phase;

  /// The phase's name.
  final String phaseName;

  /// The index of the `@DVBoot` function that threw, in phase 4 only.
  final int? bootStep;

  /// What the phase threw.
  final Object error;
  final StackTrace stackTrace;

  /// Where start-up stopped, in words: the line a server prints before it
  /// exits non-zero.
  String get where => 'phase $phase, $phaseName'
      '${bootStep == null ? '' : ' (@DVBoot function ${bootStep! + 1})'}';

  @override
  String toString() =>
      'DV-RUN-004: the ${dvEntryLabel(entry)} entry failed to boot in $where: $error';
}

/// `app`, `server (web)`, `homeWidget`: how a diagnostic names an entry.
String dvEntryLabel(DVEntry entry) => switch (entry) {
      DVServerEntry(:final DVServerRole role) => 'server (${role.name})',
      _ => entry.kind.name,
    };

/// Walks one entry through the boot sequence: each phase moves
/// `DV.lifecycle.app` (1-2 `initializing`, 3-5 `booting`), and a phase that
/// throws becomes a [DVBootFailure] reported once as DV-RUN-004. The app
/// entry, the server's web, worker and cron processes all boot through it,
/// so they name a failed phase in the same words.
class DVBootTracker {
  DVBootTracker(this.entry,
      {DVLifecycleRegistry? lifecycle, DateTime Function()? clock})
      : _lifecycle = lifecycle ?? dvLifecycle,
        _clock = clock ?? DateTime.now;

  final DVEntry entry;
  final DVLifecycleRegistry _lifecycle;
  final DateTime Function() _clock;

  // When boot, the running phase and the running @DVBoot function began, and
  // how long each finished one took: what DV-RUN-003 names.
  DateTime? _bootStarted;
  DateTime? _phaseStarted;
  DateTime? _stepStarted;
  final Map<int, ({String name, Duration took})> _phaseTimes =
      <int, ({String name, Duration took})>{};
  final Map<int, Duration> _stepTimes = <int, Duration>{};

  int _phase = 0;
  String _phaseName = 'uninitialized';
  int? _bootStep;

  /// The phase being run.
  int get phase => _phase;

  /// Whether the entry reached phase 6.
  bool get booted => _phase >= 6;
  String get phaseName => _phaseName;

  /// Enters phase [number], named [name].
  void enter(int number, String name) {
    final DateTime now = _clock();
    _bootStarted ??= now;
    _closeStep(now);
    _closePhase(now);
    _phaseStarted = now;
    _phase = number;
    _phaseName = name;
    _bootStep = null;
    final DVAppLifecycle state =
        number <= 2 ? DVAppLifecycle.initializing : DVAppLifecycle.booting;
    if (_lifecycle.app.value != state) _lifecycle.setApp(state);
  }

  /// The `@DVBoot` function at [index] is about to run: what `dvRunBoot`'s
  /// `onStep` is given.
  void step(int index) {
    final DateTime now = _clock();
    _closeStep(now);
    _bootStep = index;
    _stepStarted = now;
  }

  void _closeStep(DateTime now) {
    final int? index = _bootStep;
    final DateTime? started = _stepStarted;
    if (index != null && started != null) {
      _stepTimes[index] = (_stepTimes[index] ?? Duration.zero) + now.difference(started);
    }
    _stepStarted = null;
  }

  void _closePhase(DateTime now) {
    final DateTime? started = _phaseStarted;
    if (_phase == 0 || started == null) return;
    final Duration before = _phaseTimes[_phase]?.took ?? Duration.zero;
    _phaseTimes[_phase] = (name: _phaseName, took: before + now.difference(started));
    _phaseStarted = null;
  }

  /// DV-RUN-003: when boot so far took longer than [budget]
  /// (`dartvel.run.bootBudget`, phases 1-5 for an app entry), warns once,
  /// naming the slowest phase and the slowest `@DVBoot` function. Returns
  /// how long boot took. Call it where the measured phases end.
  Duration checkBudget(Duration budget) {
    final DateTime now = _clock();
    _closeStep(now);
    _closePhase(now);
    _phaseStarted = now;
    final Duration elapsed = now.difference(_bootStarted ?? now);
    if (elapsed <= budget) return elapsed;
    MapEntry<int, ({String name, Duration took})>? slowestPhase;
    for (final MapEntry<int, ({String name, Duration took})> phase in _phaseTimes.entries) {
      if (slowestPhase == null || phase.value.took > slowestPhase.value.took) slowestPhase = phase;
    }
    MapEntry<int, Duration>? slowestStep;
    for (final MapEntry<int, Duration> step in _stepTimes.entries) {
      if (slowestStep == null || step.value > slowestStep.value) slowestStep = step;
    }
    final String phaseText = slowestPhase == null
        ? ''
        : '; the slowest phase was phase ${slowestPhase.key}, ${slowestPhase.value.name} (${slowestPhase.value.took.inMilliseconds}ms)';
    final String stepText = slowestStep == null
        ? ''
        : ', and the slowest @DVBoot function ${slowestStep.key + 1} (${slowestStep.value.inMilliseconds}ms)';
    const DVLog().warn(
      'Boot of the ${dvEntryLabel(entry)} entry took ${elapsed.inMilliseconds}ms, over its '
      '${budget.inMilliseconds}ms budget$phaseText$stepText.',
      code: 'DV-RUN-003',
      context: <String, Object?>{
        'entry': entry.kind.name,
        'budgetMs': budget.inMilliseconds,
        'elapsedMs': elapsed.inMilliseconds,
        'slowestPhase': slowestPhase?.key,
        'slowestPhaseName': slowestPhase?.value.name,
        'slowestBootStep': slowestStep?.key,
        'slowestBootStepMs': slowestStep?.value.inMilliseconds,
      },
    );
    return elapsed;
  }

  /// Phase 6: the entry is up. A failure after this is not a boot failure,
  /// and [booted] says so.
  void ready() {
    _phase = 6;
    _phaseName = 'ready';
    _bootStep = null;
    _lifecycle.setApp(DVAppLifecycle.ready);
  }

  /// The running phase threw [error]: the lifecycle moves to `failed`, the
  /// failure is logged as DV-RUN-004 and returned for the entry to throw or
  /// exit with.
  DVBootFailure fail(Object error, StackTrace stackTrace) {
    final DVBootFailure failure = DVBootFailure(
      entry: entry,
      phase: _phase,
      phaseName: _phaseName,
      bootStep: _phase == 4 ? _bootStep : null,
      error: error,
      stackTrace: stackTrace,
    );
    _lifecycle.setApp(DVAppLifecycle.failed);
    const DVLog().error(
      'Boot failed in ${failure.where}.',
      code: 'DV-RUN-004',
      context: <String, Object?>{
        'entry': entry.kind.name,
        'phase': failure.phase,
        'phaseName': failure.phaseName,
        'bootStep': failure.bootStep,
      },
      error: error,
      stackTrace: stackTrace,
    );
    return failure;
  }
}
