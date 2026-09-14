// DV.Workers on the VM: declared offloadable work runs on an isolate from a
// bounded pool, and every way it can end reaches the caller exactly once.
//
// The failures worth testing are the silent ones: work that quietly runs on
// the calling isolate, a worker that dies and leaves its caller waiting, a
// cancellation that answers the caller and leaves the isolate running, a pool
// that grows with demand, and a result delivered after its owner ended.
@TestOn('vm')
@Timeout(Duration(seconds: 30))
library;

import 'dart:async';
import 'dart:isolate';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Tasks. Top-level, because that is what a worker can be handed.
// ---------------------------------------------------------------------------

int _sum(List<int> input, DVWorkerReporter reporter) {
  var total = 0;
  for (var i = 0; i < input.length; i++) {
    total += input[i];
    reporter.progress((i + 1) / input.length);
  }
  return total;
}

String _whereAmI(void _, DVWorkerReporter reporter) =>
    Isolate.current.debugName ?? '';

int _blockFor(int milliseconds, DVWorkerReporter reporter) {
  final Stopwatch clock = Stopwatch()..start();
  var spins = 0;
  while (clock.elapsedMilliseconds < milliseconds) {
    spins++;
  }
  return spins;
}

int _spinForever(void _, DVWorkerReporter reporter) {
  reporter.progress(0);
  var spins = 0;
  while (true) {
    spins++;
    if (spins % 1000000 == 0) reporter.progress(0.5);
  }
}

// Awaits a future nothing can complete. On a worker isolate nothing else is
// pending either, so the isolate's event loop empties and it exits.
Future<int> _neverAnswers(void _, DVWorkerReporter reporter) =>
    Completer<int>().future;

// Really waiting: a timer keeps the isolate alive the whole time.
Future<int> _waitsAnHour(void _, DVWorkerReporter reporter) =>
    Future<int>.delayed(const Duration(hours: 1), () => 0);

int _throws(void _, DVWorkerReporter reporter) =>
    throw const FormatException('ledger row 12 has no amount');

int _exitsWithoutAnswer(void _, DVWorkerReporter reporter) {
  Isolate.exit();
}

Future<int> _uncaughtAsyncError(void _, DVWorkerReporter reporter) {
  // Not awaited: an error nobody is listening for, which kills the isolate
  // rather than failing the task's own future.
  Timer.run(() => throw StateError('lost in a timer'));
  return Completer<int>().future;
}

ReceivePort _unsendableResult(void _, DVWorkerReporter reporter) =>
    ReceivePort();

int _progressThenBlock(int milliseconds, DVWorkerReporter reporter) {
  reporter.progress(0.1);
  return _blockFor(milliseconds, reporter);
}

String _constant(Object? _, DVWorkerReporter reporter) => 'x';

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 50));

List<DVLogRecord> _logged(String code) => DVObservability.recentLogs
    .where((DVLogRecord r) => r.code == code)
    .toList();

void main() {
  late DVWorkers workers;

  setUp(() {
    DVObservability.resetLogging();
    DVWorkers.debugResetOnceDiagnostics();
  });

  tearDown(() async {
    await workers.close();
  });

  group('offload', () {
    test('a task runs on a worker isolate, not on the caller', () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 4));
      final DVWorkerResult<String> result =
          await workers.run(_whereAmI, input: null);

      expect(result.outcome, DVWorkerOutcome.completed);
      expect(result.mechanism, DVWorkerMechanism.isolate);
      expect(result.value, startsWith('dv-worker'));
      expect(result.value, isNot(Isolate.current.debugName));
    });

    test('the caller keeps its event loop while the worker is busy', () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 4));
      var ticks = 0;
      final Timer ticker =
          Timer.periodic(const Duration(milliseconds: 20), (_) => ticks++);
      final DVWorkerResult<int> result =
          await workers.run(_blockFor, input: 600);
      ticker.cancel();

      expect(result.outcome, DVWorkerOutcome.completed);
      // Six hundred milliseconds of synchronous work on the caller would be
      // zero ticks. Well over half the period count proves it ran elsewhere.
      expect(ticks, greaterThan(10));
    });

    test('progress reaches the caller as DVProgress and the value arrives',
        () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 4));
      final List<double> seen = <double>[];
      final DVWorkerResult<int> result = await workers.run(
        _sum,
        input: <int>[1, 2, 3, 4],
        onProgress: (DVProgress p) => seen.add(p.fraction),
      );

      expect(result.value, 10);
      expect(seen, <double>[0.25, 0.5, 0.75, 1.0]);
    });
  });

  group('the pool is bounded and sized from the profile', () {
    test('sizing leaves the UI a core and never grows past the ceiling', () {
      expect(const DVWorkerProfile(cores: 1).poolSize, 1);
      expect(const DVWorkerProfile(cores: 2).poolSize, 1);
      expect(const DVWorkerProfile(cores: 4).poolSize, 3);
      expect(const DVWorkerProfile(cores: 64).poolSize,
          DVWorkerProfile.ceiling);
      expect(() => const DVWorkerProfile(cores: 0).poolSize,
          throwsArgumentError);
    });

    test('never more tasks run at once than the pool holds, and saturation '
        'is reported once as DV-WORKER-005', () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 3)); // 2 slots
      expect(workers.poolSize, 2);

      var peak = 0;
      final Timer sampler = Timer.periodic(
        const Duration(milliseconds: 5),
        (_) => peak = workers.running > peak ? workers.running : peak,
      );
      final List<Future<DVWorkerResult<int>>> all =
          <Future<DVWorkerResult<int>>>[
        for (var i = 0; i < 6; i++) workers.run(_blockFor, input: 150),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(workers.queued, greaterThan(0));
      final List<DVWorkerResult<int>> results = await Future.wait(all);
      sampler.cancel();

      expect(results.map((DVWorkerResult<int> r) => r.outcome),
          everyElement(DVWorkerOutcome.completed));
      expect(peak, lessThanOrEqualTo(2));
      expect(peak, greaterThan(0));
      expect(workers.running, 0);
      expect(workers.queued, 0);
      final List<DVLogRecord> saturated = _logged('DV-WORKER-005');
      expect(saturated, hasLength(1));
      expect(saturated.single.level, DVLogLevel.warn);
    });
  });

  group('cancellation', () {
    test('cancelling a running task answers the caller and ends the isolate',
        () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 2)); // 1 slot
      final DVCancellation cancel = DVCancellation();
      var progressAfterCancel = 0;
      var cancelled = false;
      final Future<DVWorkerResult<int>> pending = workers.run(
        _spinForever,
        input: null,
        cancellation: cancel,
        onProgress: (_) {
          if (cancelled) progressAfterCancel++;
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(workers.live, 1);

      cancel.cancel('the user closed the import');
      cancelled = true;
      final DVWorkerResult<int> result = await pending;
      expect(result.outcome, DVWorkerOutcome.cancelled);
      expect(() => result.value, throwsA(isA<DVWorkerFailure>()));

      // The isolate is gone -- not merely forgotten -- and the slot with it,
      // so the next task gets the only slot there is.
      await _settle();
      expect(workers.live, 0);
      final DVWorkerResult<int> next = await workers.run(_blockFor, input: 1);
      expect(next.outcome, DVWorkerOutcome.completed);
      expect(progressAfterCancel, 0);
    });

    test('a task cancelled while queued never starts', () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 2)); // 1 slot
      final Future<DVWorkerResult<int>> first =
          workers.run(_blockFor, input: 200);
      final DVCancellation cancel = DVCancellation();
      var started = false;
      final Future<DVWorkerResult<int>> second = workers.run(
        _progressThenBlock,
        input: 10,
        cancellation: cancel,
        onProgress: (_) => started = true,
      );
      expect(workers.queued, 1);
      cancel.cancel();

      expect((await second).outcome, DVWorkerOutcome.cancelled);
      expect(workers.queued, 0);
      expect((await first).outcome, DVWorkerOutcome.completed);
      await _settle();
      expect(started, isFalse);
    });

    test('an already-cancelled token never spawns anything', () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 2));
      final DVCancellation cancel = DVCancellation()..cancel();
      final DVWorkerResult<int> result =
          await workers.run(_blockFor, input: 5000, cancellation: cancel);
      expect(result.outcome, DVWorkerOutcome.cancelled);
      expect(workers.live, 0);
    });
  });

  group('timeouts', () {
    test('a task that never answers times out and its isolate is ended',
        () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 2));
      final DVWorkerResult<int> result = await workers.run(
        _waitsAnHour,
        input: null,
        timeout: const Duration(milliseconds: 200),
      );
      expect(result.outcome, DVWorkerOutcome.timedOut);
      await _settle();
      expect(workers.live, 0);
    });

    test('a task awaiting what nothing can complete is a crash, not a hang',
        () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 2));
      final DVWorkerResult<int> result =
          await workers.run(_neverAnswers, input: null);
      expect(result.outcome, DVWorkerOutcome.failed);
      expect(result.error, isA<DVWorkerFailure>().having(
          (DVWorkerFailure f) => f.kind, 'kind', DVWorkerFailureKind.crashed));
    });

    test('a busy synchronous task is ended by its timeout too', () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 2));
      final DVWorkerResult<int> result = await workers.run(
        _spinForever,
        input: null,
        timeout: const Duration(milliseconds: 200),
      );
      expect(result.outcome, DVWorkerOutcome.timedOut);
      await _settle();
      expect(workers.live, 0);
    });
  });

  group('failures reach the caller', () {
    test('a thrown error is a failed result carrying what was thrown',
        () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 2));
      final DVWorkerResult<int> result =
          await workers.run(_throws, input: null);
      expect(result.outcome, DVWorkerOutcome.failed);
      expect(result.error, isA<FormatException>());
      expect(result.stackTrace.toString(), contains('_throws'));
      expect(() => result.value, throwsA(isA<FormatException>()));
    });

    test('a worker that exits without answering is a crash, not a hang',
        () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 2));
      final DVWorkerResult<int> result =
          await workers.run(_exitsWithoutAnswer, input: null);
      expect(result.outcome, DVWorkerOutcome.failed);
      expect(result.error, isA<DVWorkerFailure>().having(
          (DVWorkerFailure f) => f.kind, 'kind', DVWorkerFailureKind.crashed));
      expect(workers.live, 0);
    });

    test('an uncaught asynchronous error kills the worker and is reported',
        () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 2));
      final DVWorkerResult<int> result =
          await workers.run(_uncaughtAsyncError, input: null);
      expect(result.outcome, DVWorkerOutcome.failed);
      expect(
          result.error,
          isA<DVWorkerFailure>()
              .having((DVWorkerFailure f) => f.kind, 'kind',
                  DVWorkerFailureKind.crashed)
              .having((DVWorkerFailure f) => f.message, 'message',
                  contains('lost in a timer')));
      await _settle();
      expect(workers.live, 0);
    });

    test('input that cannot cross the boundary fails by name and frees the '
        'slot', () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 2)); // 1 slot
      final ReceivePort port = ReceivePort();
      addTearDown(port.close);
      final DVWorkerResult<String> result =
          await workers.run(_constant, input: port);
      expect(result.outcome, DVWorkerOutcome.failed);
      expect(result.error, isA<DVWorkerFailure>().having(
          (DVWorkerFailure f) => f.kind,
          'kind',
          DVWorkerFailureKind.unsendableInput));
      expect((await workers.run(_blockFor, input: 1)).outcome,
          DVWorkerOutcome.completed);
    });

    test('a task that captured unsendable state fails as DV-WORKER-002',
        () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 2));
      final ReceivePort captured = ReceivePort();
      addTearDown(captured.close);
      final DVWorkerResult<int> result = await workers.run(
        (int input, DVWorkerReporter r) => input + captured.hashCode,
        input: 1,
      );
      expect(
          result.error,
          isA<DVWorkerFailure>()
              .having((DVWorkerFailure f) => f.kind, 'kind',
                  DVWorkerFailureKind.unsendableTask)
              .having((DVWorkerFailure f) => f.code, 'code', 'DV-WORKER-002'));
    });

    test('a result that cannot cross back fails by name instead of hanging',
        () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 2));
      final DVWorkerResult<ReceivePort> result =
          await workers.run(_unsendableResult, input: null);
      expect(result.outcome, DVWorkerOutcome.failed);
      expect(result.error, isA<DVWorkerFailure>().having(
          (DVWorkerFailure f) => f.kind,
          'kind',
          DVWorkerFailureKind.unsendableResult));
      await _settle();
      expect(workers.live, 0);
    });
  });

  group('lifecycle-bound delivery', () {
    test('a result is not delivered after its owner ended', () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 2));
      final DVMutableLifecycleSignal<DVPageLifecycle> page =
          DVMutableLifecycleSignal<DVPageLifecycle>(DVPageLifecycle.active);
      final DVCancellation bound = DVCancellation.until(
        page,
        (DVPageLifecycle s) =>
            s == DVPageLifecycle.disposing || s == DVPageLifecycle.disposed,
      );
      addTearDown(bound.dispose);
      var progressAfterDispose = 0;
      var disposed = false;
      final Future<DVWorkerResult<int>> pending = workers.run(
        _progressThenBlock,
        input: 400,
        cancellation: bound,
        onProgress: (_) {
          if (disposed) progressAfterDispose++;
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      page.set(DVPageLifecycle.disposing);
      disposed = true;

      final DVWorkerResult<int> result = await pending;
      expect(result.outcome, DVWorkerOutcome.cancelled);
      expect(bound.reason, contains('disposing'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(progressAfterDispose, 0);
      expect(workers.live, 0);
    });

    test('an owner that has already ended cancels at once', () async {
      final DVMutableLifecycleSignal<DVPageLifecycle> page =
          DVMutableLifecycleSignal<DVPageLifecycle>(DVPageLifecycle.disposed);
      final DVCancellation bound = DVCancellation.until(
          page, (DVPageLifecycle s) => s == DVPageLifecycle.disposed);
      addTearDown(bound.dispose);
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 2));
      expect(bound.isCancelled, isTrue);
    });
  });

  group('closing the pool', () {
    test('close cancels what is queued and running and ends every isolate',
        () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 2)); // 1 slot
      final Future<DVWorkerResult<int>> running =
          workers.run(_spinForever, input: null);
      final Future<DVWorkerResult<int>> queued =
          workers.run(_blockFor, input: 1);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await workers.close();

      expect((await running).outcome, DVWorkerOutcome.cancelled);
      expect((await queued).outcome, DVWorkerOutcome.cancelled);
      expect(workers.live, 0);
      expect(() => workers.run(_blockFor, input: 1), throwsStateError);
    });
  });

  group('where no threads exist the work runs inline, and says so', () {
    test('inline runs on the caller, reports DV-WORKER-001 once', () async {
      workers = DVWorkers.inline();
      expect(workers.capability.mechanism, DVWorkerMechanism.inline);
      expect(workers.capability.label, 'Unsupported → inline');

      final DVWorkerResult<String> a =
          await workers.run(_whereAmI, input: null);
      final DVWorkerResult<int> b =
          await workers.run(_sum, input: <int>[1, 2]);
      expect(a.mechanism, DVWorkerMechanism.inline);
      expect(a.value, Isolate.current.debugName ?? '');
      expect(b.value, 3);

      final List<DVLogRecord> inline = _logged('DV-WORKER-001');
      expect(inline, hasLength(1));
      expect(inline.single.level, DVLogLevel.info);
    });

    test('the isolate mechanism never logs DV-WORKER-001', () async {
      workers = DVWorkers(profile: const DVWorkerProfile(cores: 2));
      await workers.run(_sum, input: <int>[1]);
      expect(_logged('DV-WORKER-001'), isEmpty);
      expect(workers.capability.label, 'Supported');
      expect(workers.capability.sharedMemory, isFalse);
    });

    test('inline cancellation is cooperative and still answers the caller',
        () async {
      workers = DVWorkers.inline();
      final DVCancellation cancel = DVCancellation();
      final Future<DVWorkerResult<int>> pending = workers.run(
        _neverAnswers,
        input: null,
        cancellation: cancel,
      );
      cancel.cancel();
      expect((await pending).outcome, DVWorkerOutcome.cancelled);
    });
  });
}
