import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// The queue and job dashboard: what is waiting, what has died, and the two
/// things an operator can do about a dead letter.
///
/// A failed job is not an error log entry — it is work that did not happen.
/// Seeing why it failed and either retrying or dropping it is the whole
/// reason the dead-letter list exists.
class DVQueueAdmin extends StatefulWidget {
  /// Queues to show. Jobs are stored per queue, so there is nothing to
  /// enumerate them with — an application names the ones it uses.
  final List<String> queues;

  const DVQueueAdmin({super.key, this.queues = const <String>['default']});

  @override
  State<DVQueueAdmin> createState() => _DVQueueAdminState();
}

class _DVQueueAdminState extends State<DVQueueAdmin> {
  static const DVQueues _queues = DVQueues();

  final Map<String, List<DVJobEnvelope<DVJobPayload>>> _pending =
      <String, List<DVJobEnvelope<DVJobPayload>>>{};
  final Map<String, List<DVJobEnvelope<DVJobPayload>>> _dead =
      <String, List<DVJobEnvelope<DVJobPayload>>>{};

  String? _error;
  String? _notice;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final pending = <String, List<DVJobEnvelope<DVJobPayload>>>{};
      final dead = <String, List<DVJobEnvelope<DVJobPayload>>>{};
      for (final queue in widget.queues) {
        pending[queue] = await _queues.pending(queue);
        dead[queue] = await _queues.deadLetters(queue);
      }
      if (!mounted) return;
      setState(() {
        _pending
          ..clear()
          ..addAll(pending);
        _dead
          ..clear()
          ..addAll(dead);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      // A queue with no table yet is a fresh app, not an empty queue.
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _act(
    String label,
    Future<bool> Function() action,
  ) async {
    try {
      final applied = await action();
      if (!mounted) return;
      // Reporting success for a job the adapter did not find would leave an
      // operator believing a dead letter was dealt with.
      setState(() => _notice = applied ? label : 'No such job.');
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const DVText('Loading queues…');
    return DVBox.list(<Widget>[
      const DVText('Queues and Jobs')
          .modifier(const DVModifier().fontSize(24).fontWeight(FontWeight.bold)),
      if (_error != null) DVText('Could not read queues: $_error'),
      if (_notice != null) DVText(_notice!),
      for (final queue in widget.queues) _queueSection(queue),
    ]);
  }

  Widget _queueSection(String queue) {
    final pending = _pending[queue] ?? const <DVJobEnvelope<DVJobPayload>>[];
    final dead = _dead[queue] ?? const <DVJobEnvelope<DVJobPayload>>[];
    return DVBox.list(<Widget>[
      DVText(queue)
          .modifier(const DVModifier().fontSize(18).fontWeight(FontWeight.bold)),
      DVText('${pending.length} pending, ${dead.length} failed'),
      for (final job in pending)
        DVText('${job.id} · attempt ${job.attempts}/${job.maxAttempts}'),
      if (pending.isEmpty) const DVText('Nothing pending.'),
      for (final job in dead) _deadLetter(job),
      if (dead.isEmpty) const DVText('No failed jobs.'),
    ]).modifier(const DVModifier().card().padding(16));
  }

  Widget _deadLetter(DVJobEnvelope<DVJobPayload> job) {
    return DVBox.list(<Widget>[
      DVText(job.id),
      // The error is why an operator is here at all; retrying blind is
      // guessing.
      DVText(job.lastError ?? 'failed with no recorded error'),
      DVText('gave up after ${job.attempts} of ${job.maxAttempts}'),
      DVBox.wrapLine(<Widget>[
        GestureDetector(
          key: ValueKey<String>('dv-queue-retry-${job.id}'),
          onTap: () => _act('Retried ${job.id}.', () => _queues.retry(job.id)),
          child: const DVText('Retry'),
        ),
        GestureDetector(
          key: ValueKey<String>('dv-queue-discard-${job.id}'),
          onTap: () =>
              _act('Discarded ${job.id}.', () => _queues.discard(job.id)),
          child: const DVText('Discard'),
        ),
      ]),
    ]);
  }
}
