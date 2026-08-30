/// A durable queue on Amazon SQS.
library dartvel_core.queues.sqs_queue;

import 'dart:convert';

import '../../dartvel.dart';

/// What this adapter needs from the SQS API.
///
/// An interface rather than an HTTP client, so the protocol is testable
/// without a network and so signing, retries and endpoint selection stay the
/// caller's business. SQS request signing is SigV4 and belongs with whatever
/// already holds the credentials.
abstract class DVSqsTransport {
  /// Perform [action] with [body] as form parameters, returning the parsed
  /// response.
  Future<Map<String, Object?>> call(String action, Map<String, String> body);
}

/// `DV.Queues` on SQS.
///
/// SQS is not the same shape as the other adapters, and this one is written
/// around the difference rather than over it.
///
/// It has no priority, no listing of what is waiting, and no dead-letter list
/// this adapter owns — a redrive policy on the queue owns that, configured on
/// the service. The operations that cannot be honoured throw rather than
/// returning an empty list, because an empty list reads as "there is nothing"
/// when the truth is "I cannot see".
///
/// What it does have that the others do not: a received message is invisible
/// for a visibility timeout and returns on its own if nothing deletes it. That
/// is the durability guarantee, and it means failing a job is a matter of
/// handing it back early rather than recording anything.
class DVSqsQueueAdapter implements DVQueueAdapter {
  DVSqsQueueAdapter(
    this.transport, {
    required this.queueUrl,
    this.waitTimeSeconds = 20,
    this.visibilityTimeout = const Duration(seconds: 30),
  });

  final DVSqsTransport transport;

  /// The queue's URL for a Dartvel queue name.
  final String Function(String queue) queueUrl;

  /// Long-polling window. Zero returns immediately and bills more for the
  /// same work.
  final int waitTimeSeconds;

  final Duration visibilityTimeout;

  /// Receipts are per-receive, not per-message: SQS issues a new one every
  /// time a message is handed out, and only the current one can delete it.
  final Map<String, String> _receipts = <String, String>{};

  /// The queue each reserved job came from, so a failure can find its backoff.
  final Map<String, String> _queues = <String, String>{};

  /// The backoff last enqueued for a queue. SQS carries no per-message
  /// retry policy, so this is the only place it can live.
  final Map<String, Duration> _backoffs = <String, Duration>{};

  /// The receipt that will delete [jobId], for tests and for diagnostics.
  String? receiptFor(String jobId) => _receipts[jobId];

  @override
  Future<DVJobEnvelope<TPayload>> enqueue<TPayload>(
    String queue,
    TPayload payload, {
    int priority = 0,
    int maxAttempts = 3,
    Duration backoff = const Duration(seconds: 30),
  }) async {
    if (priority != 0) {
      throw UnsupportedError(
        'SQS has no message priority. Accepting one here would promise an '
        'ordering the service does not provide; use a separate queue per '
        'priority instead.',
      );
    }

    const DVJobPayloadCodecs codecs = DVJobPayloadCodecs();
    final String? name = codecs.nameFor<TPayload>();
    if (name == null) {
      throw StateError(
        'No DVJobPayloadCodec registered for $TPayload, so it cannot be '
        'persisted. Register one, or use DVInMemoryQueueAdapter.',
      );
    }

    final Map<String, String> body = <String, String>{
      'QueueUrl': queueUrl(queue),
      'MessageBody': jsonEncode(<String, Object?>{
        'type': name,
        'payload': codecs.encodeFor<TPayload>(payload),
      }),
    };
    // No DelaySeconds. backoff is how long to wait before *retrying*, not how
    // long to hide a job that has not run yet, and sending it here made every
    // job invisible for thirty seconds the moment it was enqueued. The unit
    // test asserted the wrong behaviour and passed; a live broker caught it
    // on the first run.
    //
    // It is remembered instead, and applied where it means something: the
    // visibility timeout on failure.
    _backoffs[queue] = backoff;
    await transport.call('SendMessage', body);
    return DVJobEnvelope<TPayload>(
      id: 'sqs-${DateTime.now().microsecondsSinceEpoch}',
      queue: queue,
      payloadType: TPayload,
      payload: payload,
      priority: 0,
      maxAttempts: maxAttempts,
      backoff: backoff,
      attempts: 0,
      state: DVJobState.queued,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<DVJobEnvelope<DVJobPayload>?> reserve(String queue) async {
    final Map<String, Object?> response =
        await transport.call('ReceiveMessage', <String, String>{
      'QueueUrl': queueUrl(queue),
      'MaxNumberOfMessages': '1',
      'WaitTimeSeconds': '$waitTimeSeconds',
      'VisibilityTimeout': '${visibilityTimeout.inSeconds}',
    });

    final Object? messages = response['Messages'];
    if (messages is! List || messages.isEmpty) return null;
    final Object? first = messages.first;
    if (first is! Map) return null;

    final String id = '${first['MessageId']}';
    _receipts[id] = '${first['ReceiptHandle']}';
    _queues[id] = queue;

    // Wrapped for the same reason as the AMQP adapter: jsonDecode throws on
    // malformed input, so one corrupt message would take down the worker
    // that received it rather than being left to time out and be redriven.
    Object? decoded;
    try {
      decoded = jsonDecode('${first['Body']}');
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map) {
      _receipts.remove(id);
      return null;
    }
    const DVJobPayloadCodecs codecs = DVJobPayloadCodecs();
    final DVJobPayload? payload = codecs.decodeNamed(
      '${decoded['type']}',
      (decoded['payload'] as Map).cast<String, Object?>(),
    );
    // A message this process has no codec for. Deleting it would lose work
    // another deployment can handle, so it is left to time out and return.
    if (payload == null) {
      _receipts.remove(id);
      return null;
    }

    return DVJobEnvelope<DVJobPayload>(
      id: id,
      queue: queue,
      // The registered type, not the wrapper's. Handlers are routed by
      // payloadType, and a decoded payload is a _DVStoredJobPayload<T> --
      // so runtimeType here is the wrapper and no handler ever matches.
      payloadType: codecs.typeNamed('${decoded['type']}') ?? payload.payloadType,
      payload: payload,
      priority: 0,
      maxAttempts: 1,
      backoff: visibilityTimeout,
      // SQS tracks this itself as ApproximateReceiveCount; the adapter does
      // not keep a second count that could disagree with the service's.
      attempts: 1,
      state: DVJobState.running,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> complete(String id) async {
    _queues.remove(id);
    final String? receipt = _receipts.remove(id);
    // Nothing to delete. Calling SQS with a receipt this process never held
    // would be a guess about someone else's message.
    if (receipt == null) return;
    await transport.call('DeleteMessage', <String, String>{
      'ReceiptHandle': receipt,
    });
  }

  @override
  Future<void> fail(String id, String error, StackTrace stackTrace) async {
    final String? receipt = _receipts.remove(id);
    if (receipt == null) return;
    // Handed back after the backoff, which is what a backoff is for. Zero
    // retries a failing job immediately and at full speed; leaving it to the
    // visibility timeout waits an interval chosen for something else.
    final Duration backoff = _backoffs[_queues.remove(id)] ?? Duration.zero;
    final int seconds = backoff.inSeconds.clamp(0, 43200);
    await transport.call('ChangeMessageVisibility', <String, String>{
      'ReceiptHandle': receipt,
      'VisibilityTimeout': '$seconds',
    });
  }

  @override
  Future<List<DVJobEnvelope<DVJobPayload>>> pending(String queue) async =>
      throw UnsupportedError(
        'SQS cannot list the messages waiting in a queue. An empty list here '
        'would read as "there is nothing", which is a different claim from '
        '"I cannot see". ApproximateNumberOfMessages gives a count.',
      );

  @override
  Future<List<DVJobEnvelope<DVJobPayload>>> deadLetters(String queue) async =>
      throw UnsupportedError(
        'Dead letters on SQS belong to the queue\'s redrive policy and land '
        'in a separate queue you configure. Point this adapter at that queue '
        'to read them.',
      );

  @override
  Future<bool> retry(String id) async => throw UnsupportedError(
        'A dead-lettered SQS message is redriven by the service, not by a '
        'client holding an id.',
      );

  @override
  Future<bool> discard(String id) async => throw UnsupportedError(
        'A dead-lettered SQS message is deleted from the dead-letter queue '
        'it landed in, not through this one.',
      );

  @override
  Future<int> flush(String queue) async {
    // PurgeQueue is allowed once a minute and takes up to sixty seconds, so
    // the count it removed is not knowable.
    await transport.call('PurgeQueue', <String, String>{
      'QueueUrl': queueUrl(queue),
    });
    return 0;
  }
}
