// A worker process: what DARTVEL_ROLE=worker runs.
//
// The quiet failures: a worker on the process-local default queue, which no
// other process can dispatch to, sitting idle forever while the web
// instances' jobs pile up somewhere else; a worker with no handler
// registered, dead-lettering every job it reserves; and a worker that stops
// after the first empty poll, so a job dispatched a second later waits for a
// restart.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class Welcome {
  const Welcome(this.userId);
  final String userId;
}

void main() {
  // First, before anything in this isolate configures DVQueues.
  test('a worker on the unconfigured default queue refuses to start', () async {
    const DVQueues().register<Welcome>((Welcome job) async {});
    await expectLater(
      DVQueueWorker(queues: const <String>['default']).run(),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('no queue adapter'),
        ),
      ),
    );
  });

  group('configured', () {
    late DVInMemoryQueueAdapter adapter;
    late List<String> handled;

    setUp(() {
      adapter = const DVTestHarness().fakeQueue();
      handled = <String>[];
    });

    test('with no handler registered it refuses to start', () async {
      await expectLater(
        DVQueueWorker(queues: const <String>['default']).run(),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('@DVJob.handler'),
          ),
        ),
      );
    });

    test('it works each named queue and keeps polling until stopped', () async {
      const DVQueues().register<Welcome>((Welcome job) async {
        handled.add(job.userId);
      });
      await const DVQueues().dispatch(const Welcome('ada'));
      await const DVQueues().dispatch(const Welcome('grace'), queue: 'mail');
      await const DVQueues().dispatch(const Welcome('unwatched'), queue: 'sms');

      final Completer<void> stop = Completer<void>();
      final Future<void> running = DVQueueWorker(
        queues: const <String>['default', 'mail'],
        idle: const Duration(milliseconds: 5),
      ).run(until: stop.future);

      // Idle polls happen first; a job dispatched after them is still run.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await const DVQueues().dispatch(const Welcome('late'), queue: 'mail');
      await Future<void>.delayed(const Duration(milliseconds: 40));

      stop.complete();
      await running.timeout(const Duration(seconds: 5));

      expect(handled, unorderedEquals(<String>['ada', 'grace', 'late']));
      // A queue it was not told to work is left for the worker that was.
      expect(await adapter.pending('sms'), hasLength(1));
    });

    test('a job that throws does not stop the worker', () async {
      const DVQueues().register<Welcome>((Welcome job) async {
        if (job.userId == 'bad') throw StateError('boom');
        handled.add(job.userId);
      });
      await const DVQueues().dispatch(const Welcome('bad'));
      await const DVQueues().dispatch(const Welcome('good'));

      final Completer<void> stop = Completer<void>();
      final Future<void> running = DVQueueWorker(
        queues: const <String>['default'],
        idle: const Duration(milliseconds: 5),
      ).run(until: stop.future);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      stop.complete();
      await running.timeout(const Duration(seconds: 5));

      expect(handled, <String>['good']);
    });

    test('no queues is refused', () {
      expect(
        () => DVQueueWorker(queues: const <String>[]),
        throwsArgumentError,
      );
    });
  });
}
