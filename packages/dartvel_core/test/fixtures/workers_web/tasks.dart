// Tasks shared by the page and the worker script, registered under the same
// names on both sides.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dartvel_core/web_worker.dart';

int sum(List<Object?> input, DVWorkerReporter reporter) {
  var total = 0;
  for (var i = 0; i < input.length; i++) {
    total += (input[i]! as num).toInt();
    reporter.progress((i + 1) / input.length);
  }
  return total;
}

/// Which thread ran it: the harness marks the worker's global scope.
String whereAmI(Object? input, DVWorkerReporter reporter) =>
    globalContext.has('__dvWorkerThread') ? 'worker' : 'page';

int boom(Object? input, DVWorkerReporter reporter) =>
    throw StateError('boom in the worker');

int spin(Object? input, DVWorkerReporter reporter) {
  reporter.progress(0);
  var spins = 0;
  while (true) {
    if (++spins % 1000000 == 0) reporter.progress(0.5);
  }
}

Object? echo(Object? input, DVWorkerReporter reporter) => input;

int notRegistered(Object? input, DVWorkerReporter reporter) => 0;

void registerAll() {
  DVWorkerTasks.register('sum', sum);
  DVWorkerTasks.register('whereAmI', whereAmI);
  DVWorkerTasks.register('boom', boom);
  DVWorkerTasks.register('spin', spin);
  DVWorkerTasks.register('echo', echo);
}

String? scriptFromHarness() =>
    (globalContext['__dvWorkerScript'] as JSString?)?.toDart;
