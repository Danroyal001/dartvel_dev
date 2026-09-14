/// The loop a `DARTVEL_ROLE=worker` process runs.
library;

import 'dart:async';

import '../../dartvel.dart' show DVQueues;

/// Works [queues] through `DVQueues` until told to stop.
///
/// Refuses to start rather than idling when it could never do anything: on
/// the process-local queue a process gets when nothing configured an adapter,
/// no other process can dispatch to it, and with no `@DVJob.handler`
/// registered every job it reserved would be dead-lettered.
final class DVQueueWorker {
  DVQueueWorker({
    required List<String> queues,
    this.idle = const Duration(seconds: 1),
    this.batch = 50,
  }) : queues = List<String>.unmodifiable(queues) {
    if (queues.isEmpty) {
      throw ArgumentError.value(queues, 'queues', 'a worker works some queue');
    }
    if (batch < 1) {
      throw ArgumentError.value(batch, 'batch', 'must be positive');
    }
  }

  final List<String> queues;

  /// How long to wait after a pass that found nothing to do.
  final Duration idle;

  /// The most jobs taken from one queue before the next queue gets a turn,
  /// so a flooded queue does not starve the others.
  final int batch;

  /// Runs until [until] completes, finishing the job in hand first.
  Future<void> run({Future<void>? until}) async {
    const DVQueues queue = DVQueues();
    if (!queue.adapterConfigured) {
      throw StateError(
        'This worker has no queue adapter configured. It would work the '
        'process-local queue, which no other process can dispatch to, and '
        'never receive a job. Configure one with DVQueues().useAdapter before '
        'the worker starts.',
      );
    }
    if (!queue.hasHandlers) {
      throw StateError(
        'No @DVJob.handler is registered in this worker, so every job it '
        'reserved would fail and be dead-lettered. Register the handlers '
        '(registerDartvelJobs) before the worker starts.',
      );
    }

    bool stopped = false;
    final Completer<void> wake = Completer<void>();
    unawaited(
      until?.then((_) {
        stopped = true;
        if (!wake.isCompleted) wake.complete();
      }),
    );

    while (!stopped) {
      int done = 0;
      for (final String name in queues) {
        if (stopped) break;
        done += await queue.work(queue: name, maxJobs: batch);
      }
      if (stopped) break;
      if (done == 0) {
        await Future.any(<Future<void>>[
          Future<void>.delayed(idle),
          wake.future,
        ]);
      }
    }
  }
}
