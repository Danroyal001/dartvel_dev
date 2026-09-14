// The page: runs each scenario through DV.Workers and prints one line per
// outcome for workers_web_node_test.dart to read.
// ignore_for_file: avoid_print
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';

import 'tasks.dart';

String _kind(DVWorkerResult<Object?> r) {
  final Object? error = r.error;
  return error is DVWorkerFailure ? error.kind.name : '${error.runtimeType}';
}

Future<void> main() async {
  registerAll();
  DVWorkerTasks.script = scriptFromHarness() ?? 'worker.js';
  final DVWorkers workers = DVWorkers(profile: const DVWorkerProfile(cores: 3));
  final DVWorkerCapability capability = workers.capability;
  print('capability ${capability.mechanism.name} | ${capability.label} | '
      'shared=${capability.sharedMemory}');

  final List<double> progress = <double>[];
  final DVWorkerResult<int> summed = await workers.run(sum,
      input: <Object?>[1, 2, 3, 4], onProgress: (DVProgress p) => progress.add(p.fraction));
  print('sum ${summed.outcome.name} ${summed.mechanism.name} '
      '${summed.isCompleted ? summed.value : summed.error} '
      // Fixed precision: JavaScript has one number type and prints 1.0 as 1.
      '${progress.map((double f) => f.toStringAsFixed(2)).join(',')}');

  final DVWorkerResult<String> where = await workers.run(whereAmI, input: null);
  print('where ${where.isCompleted ? where.value : where.error}');

  final DVWorkerResult<int> thrown = await workers.run(boom, input: null);
  print('boom ${thrown.outcome.name} ${_kind(thrown)} ${thrown.error}');

  final DVWorkerResult<int> missing =
      await workers.run(notRegistered, input: null);
  print('unregistered ${missing.outcome.name} ${_kind(missing)}');

  final DVWorkerResult<Object?> unportable =
      await workers.run(echo, input: <Object?>[Object()]);
  print('unportable ${unportable.outcome.name} ${_kind(unportable)}');

  final DVCancellation cancel = DVCancellation();
  final Future<DVWorkerResult<int>> spinning =
      workers.run(spin, input: null, cancellation: cancel);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  cancel.cancel('closed');
  final DVWorkerResult<int> cancelled = await spinning;
  print('cancelled ${cancelled.outcome.name} live=${workers.live}');

  final DVWorkerResult<int> timedOut = await workers.run(spin,
      input: null, timeout: const Duration(milliseconds: 300));
  print('timeout ${timedOut.outcome.name} live=${workers.live}');

  final DVWorkerResult<Object?> bytes =
      await workers.run(echo, input: Uint8List.fromList(<int>[1, 2, 3]));
  final int copied = DVObservability.recentLogs
      .where((DVLogRecord r) => r.code == 'DV-WORKER-004')
      .length;
  print('bytes ${bytes.outcome.name} ${bytes.value} copied-reports=$copied');

  final DVWorkerResult<int> after = await workers.run(sum, input: <Object?>[5]);
  print('after ${after.outcome.name} ${after.isCompleted ? after.value : after.error}');

  DVWorkerTasks.script = 'does-not-exist.js';
  final DVWorkerResult<int> noScript = await workers.run(sum,
      input: <Object?>[1], timeout: const Duration(seconds: 10));
  print('noscript ${noScript.outcome.name} ${_kind(noScript)}');

  await workers.close();
  print('closed live=${workers.live}');
}
