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
  DVBootTracker(this.entry, {DVLifecycleRegistry? lifecycle})
      : _lifecycle = lifecycle ?? dvLifecycle;

  final DVEntry entry;
  final DVLifecycleRegistry _lifecycle;

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
    _phase = number;
    _phaseName = name;
    _bootStep = null;
    final DVAppLifecycle state =
        number <= 2 ? DVAppLifecycle.initializing : DVAppLifecycle.booting;
    if (_lifecycle.app.value != state) _lifecycle.setApp(state);
  }

  /// The `@DVBoot` function at [index] is about to run: what `dvRunBoot`'s
  /// `onStep` is given.
  void step(int index) => _bootStep = index;

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
