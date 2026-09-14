// DV.Workers is the application's pool, reachable from a page the way every
// other namespace is, and the work it is handed leaves the UI isolate.
import 'dart:isolate';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

String _whereAmI(void _, DVWorkerReporter reporter) =>
    Isolate.current.debugName ?? '';

void main() {
  tearDown(() => DVWorkers.configure(DVWorkers()));

  test('DV.Workers is the pool DVWorkers.configure installed', () async {
    final DVWorkers pool = DVWorkers(profile: const DVWorkerProfile(cores: 2));
    addTearDown(pool.close);
    DVWorkers.configure(pool);

    expect(identical(DV.Workers, pool), isTrue);
    expect(DV.Workers.poolSize, 1);
  });

  test('a task run through DV.Workers does not run on the UI isolate',
      () async {
    final DVWorkerResult<String> result =
        await DV.Workers.run(_whereAmI, input: null);

    expect(result.outcome, DVWorkerOutcome.completed);
    expect(result.mechanism, DVWorkerMechanism.isolate);
    expect(result.value, isNot(Isolate.current.debugName ?? ''));
  });
}
