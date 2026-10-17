import 'dart:async';

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
Future<void> dvRunBoot(List<DVBootStep> steps, DVBoot boot) async {
  if (_booted) return;
  _booted = true;
  final DVEntryKind kind = boot.entry.kind;
  for (final DVBootStep step in steps) {
    if (step.entries.isEmpty || step.entries.contains(kind)) {
      await step.run(boot);
    }
  }
}

/// Lets a test boot again in the same isolate.
void dvResetBootForTest() => _booted = false;
