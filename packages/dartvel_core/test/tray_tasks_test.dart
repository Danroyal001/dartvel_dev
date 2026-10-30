// The background tasks a reader is shown.
//
// Error, Empty, and Loading States: "a background-task tray shows uploads,
// exports and imports from the typed progress events" the framework already
// has. DVProgress is the typed event DV.Workers emits; nothing collected the
// runs a reader should see, so there was nothing for a tray to render. A run
// given a label is listed in DVTrayTasks while it runs, with its latest
// progress, and leaves however it ends.
@TestOn('vm')
@Timeout(Duration(seconds: 30))
library;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

int _sum(List<int> input, DVWorkerReporter reporter) {
  var total = 0;
  for (var i = 0; i < input.length; i++) {
    total += input[i];
    reporter.progress((i + 1) / input.length, message: 'row ${i + 1}');
  }
  return total;
}

int _fails(void _, DVWorkerReporter reporter) {
  reporter.progress(0.5);
  throw StateError('bad row');
}

Future<int> _waitsAnHour(void _, DVWorkerReporter reporter) =>
    Future<int>.delayed(const Duration(hours: 1), () => 0);

void main() {
  late DVTrayTasks tasks;

  setUp(() => tasks = DVTrayTasks());

  group('the registry', () {
    test('lists a task from begin until it ends, with its latest progress', () {
      final DVTrayTask task = tasks.begin('Importing customers');
      expect(tasks.active.map((DVTrayTask t) => t.label),
          <String>['Importing customers']);
      expect(task.progress, isNull, reason: 'no progress reported yet');

      task.report(const DVProgress(0.4, message: '400 of 1000'));
      expect(tasks.active.single.progress!.fraction, 0.4);

      task.end();
      expect(tasks.active, isEmpty);
    });

    test('says when what it lists changes', () async {
      final List<int> sizes = <int>[];
      final StreamSubscription<void> sub =
          tasks.changes.listen((_) => sizes.add(tasks.active.length));
      final DVTrayTask task = tasks.begin('Uploading photo');
      task.report(const DVProgress(0.5));
      task.end();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(sizes, <int>[1, 1, 0]);
    });

    test('ending twice ends one task once', () {
      final DVTrayTask a = tasks.begin('Export');
      tasks.begin('Import');
      a.end();
      a.end();
      expect(tasks.active.map((DVTrayTask t) => t.label), <String>['Import']);
    });

    test('a report after the end is dropped rather than bringing it back', () {
      final DVTrayTask task = tasks.begin('Export');
      task.end();
      task.report(const DVProgress(1));
      expect(tasks.active, isEmpty);
    });
  });

  group('a DV.Workers run with a label', () {
    late DVWorkers workers;

    tearDown(() => workers.close());

    test('is listed while it runs and its progress reaches the list', () async {
      workers = DVWorkers(
        profile: const DVWorkerProfile(cores: 4),
        trayTasks: tasks,
      );
      final List<double> seen = <double>[];
      final StreamSubscription<void> sub = tasks.changes.listen((_) {
        for (final DVTrayTask t in tasks.active) {
          if (t.progress != null) seen.add(t.progress!.fraction);
        }
      });
      final DVWorkerResult<int> result = await workers.run(
        _sum,
        input: <int>[1, 2, 3, 4],
        label: 'Summing',
      );
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(result.value, 10);
      expect(seen, <double>[0.25, 0.5, 0.75, 1.0]);
      expect(tasks.active, isEmpty, reason: 'gone once it answered');
    });

    test('leaves the list when it fails', () async {
      workers = DVWorkers(
        profile: const DVWorkerProfile(cores: 4),
        trayTasks: tasks,
      );
      final DVWorkerResult<int> result =
          await workers.run(_fails, input: null, label: 'Parsing');
      expect(result.outcome, DVWorkerOutcome.failed);
      expect(tasks.active, isEmpty);
    });

    test('leaves the list when it is cancelled', () async {
      workers = DVWorkers(
        profile: const DVWorkerProfile(cores: 4),
        trayTasks: tasks,
      );
      final DVCancellation cancel = DVCancellation();
      final Future<DVWorkerResult<int>> running =
          workers.run(_waitsAnHour, input: null, label: 'Waiting', cancellation: cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(tasks.active.map((DVTrayTask t) => t.label), <String>['Waiting']);
      cancel.cancel('reader left');
      expect((await running).outcome, DVWorkerOutcome.cancelled);
      expect(tasks.active, isEmpty);
    });

    test('a run with no label is not the reader\'s business', () async {
      workers = DVWorkers(
        profile: const DVWorkerProfile(cores: 4),
        trayTasks: tasks,
      );
      final List<int> sizes = <int>[];
      final StreamSubscription<void> sub =
          tasks.changes.listen((_) => sizes.add(tasks.active.length));
      await workers.run(_sum, input: <int>[1, 2]);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(sizes, isEmpty);
    });
  });

  test('the process has one registry, which the default pool reports to', () {
    expect(DVTrayTasks.current, same(DVTrayTasks.current));
  });
}
