/// A durable queue on Google Cloud Pub/Sub.
library dartvel_core.queues.pubsub_queue;

import 'dart:convert';

import '../../dartvel.dart';

/// What this adapter needs from the Pub/Sub REST API.
///
/// An interface rather than an HTTP client, so the protocol is testable
/// without a network and so authentication stays with whatever holds the
/// credentials. Pub/Sub uses OAuth bearer tokens against the real service and
/// nothing at all against the emulator.
abstract class DVPubSubTransport {
  /// POST to [path] with [body], returning the decoded JSON object.
  Future<Map<String, Object?>> post(String path, Map<String, Object?> body);
}

/// `DV.Queues` on Pub/Sub.
///
/// Pub/Sub separates the thing you publish to from the thing you read from: a
/// topic fans out to any number of subscriptions, and a message is delivered
/// to every one of them. A Dartvel queue is one topic and one subscription,
/// named the same, because a queue that fanned out would run every job as many
/// times as there were subscribers.
///
/// Like SQS it has no priority and no readable backlog, and like SQS this
/// adapter refuses those rather than answering with an empty list.
class DVPubSubQueueAdapter implements DVQueueAdapter {
  DVPubSubQueueAdapter(
    this.transport, {
    required this.project,
    this.subscriptionSuffix = '-sub',
    this.ackDeadline = const Duration(seconds: 30),
  });

  final DVPubSubTransport transport;

  /// The Google Cloud project these topics live in.
  final String project;

  /// How a queue's subscription is named from the queue.
  final String subscriptionSuffix;

  final Duration ackDeadline;

  /// Ack ids are per-delivery, like an SQS receipt: a new one every pull, and
  /// only the current one acknowledges.
  final Map<String, String> _ackIds = <String, String>{};
  final Map<String, Duration> _backoffs = <String, Duration>{};
  final Map<String, String> _queues = <String, String>{};

  String topicPath(String queue) => 'projects/$project/topics/$queue';

  String subscriptionPath(String queue) =>
      'projects/$project/subscriptions/$queue$subscriptionSuffix';

  /// The ack id that will acknowledge [jobId].
  String? ackIdFor(String jobId) => _ackIds[jobId];

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
        'Pub/Sub has no message priority. Accepting one would promise an '
        'ordering the service does not provide; use a topic per priority.',
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

    // Base64 because Pub/Sub carries bytes, not text, and sends them as
    // base64 in JSON either way -- doing it here rather than letting a
    // transport guess keeps the encoding in one place.
    final String data = base64Encode(utf8.encode(jsonEncode(<String, Object?>{
      'type': name,
      'payload': codecs.encodeFor<TPayload>(payload),
      'maxAttempts': maxAttempts,
    })));

    _backoffs[queue] = backoff;
    await transport.post('${topicPath(queue)}:publish', <String, Object?>{
      'messages': <Object?>[
        <String, Object?>{'data': data},
      ],
    });

    return DVJobEnvelope<TPayload>(
      id: 'pubsub-${DateTime.now().microsecondsSinceEpoch}',
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
    final Map<String, Object?> response = await transport.post(
      '${subscriptionPath(queue)}:pull',
      <String, Object?>{'maxMessages': 1, 'returnImmediately': true},
    );

    final Object? received = response['receivedMessages'];
    if (received is! List || received.isEmpty) return null;
    final Object? first = received.first;
    if (first is! Map) return null;

    final Object? envelope = first['message'];
    if (envelope is! Map) return null;

    final String id = '${envelope['messageId']}';
    _ackIds[id] = '${first['ackId']}';
    _queues[id] = queue;

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(base64Decode('${envelope['data']}')));
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map) {
      // Unreadable. Acknowledged rather than left to redeliver, because
      // redelivering it hands the same broken message back forever.
      await _acknowledge(id);
      return null;
    }

    const DVJobPayloadCodecs codecs = DVJobPayloadCodecs();
    final String name = '${decoded['type']}';
    final DVJobPayload? payload = codecs.decodeNamed(
      name,
      (decoded['payload'] as Map).cast<String, Object?>(),
    );
    if (payload == null) {
      // A codec this deployment lacks. Released rather than acknowledged:
      // another deployment may be able to run it.
      await _release(id, Duration.zero);
      return null;
    }

    return DVJobEnvelope<DVJobPayload>(
      id: id,
      queue: queue,
      // The registered type, not the wrapper's: handlers are routed by this,
      // and a decoded payload is a wrapper around the real value.
      payloadType: codecs.typeNamed(name) ?? payload.payloadType,
      payload: payload,
      priority: 0,
      maxAttempts: (decoded['maxAttempts'] as num?)?.toInt() ?? 3,
      backoff: _backoffs[queue] ?? ackDeadline,
      attempts: 1,
      state: DVJobState.running,
      createdAt: DateTime.now(),
    );
  }

  Future<void> _acknowledge(String id) async {
    final String? ackId = _ackIds.remove(id);
    if (ackId == null) return;
    final String queue = _queues.remove(id) ?? '';
    await transport.post(
      '${subscriptionPath(queue)}:acknowledge',
      <String, Object?>{
        'ackIds': <String>[ackId],
      },
    );
  }

  /// Hand a message back after [after].
  Future<void> _release(String id, Duration after) async {
    final String? ackId = _ackIds.remove(id);
    if (ackId == null) return;
    final String queue = _queues.remove(id) ?? '';
    await transport.post(
      '${subscriptionPath(queue)}:modifyAckDeadline',
      <String, Object?>{
        'ackIds': <String>[ackId],
        // The deadline is when it comes back, so the backoff belongs here.
        'ackDeadlineSeconds': after.inSeconds.clamp(0, 600),
      },
    );
  }

  @override
  Future<void> complete(String id) => _acknowledge(id);

  @override
  Future<void> fail(String id, String error, StackTrace stackTrace) async {
    final Duration backoff = _backoffs[_queues[id]] ?? Duration.zero;
    await _release(id, backoff);
  }

  @override
  Future<List<DVJobEnvelope<DVJobPayload>>> pending(String queue) async =>
      throw UnsupportedError(
        'Pub/Sub cannot list a backlog without pulling it, and pulling is '
        'consuming. An empty list here would read as "there is nothing" when '
        'the truth is "I cannot see".',
      );

  @override
  Future<List<DVJobEnvelope<DVJobPayload>>> deadLetters(String queue) async =>
      throw UnsupportedError(
        'Dead letters go to the dead-letter topic configured on the '
        'subscription. Point an adapter at that topic to read them.',
      );

  @override
  Future<bool> retry(String id) async => throw UnsupportedError(
        'A dead-lettered Pub/Sub message is republished from its dead-letter '
        'topic, not retried through this one.',
      );

  @override
  Future<bool> discard(String id) async => throw UnsupportedError(
        'A dead-lettered Pub/Sub message is acknowledged on the dead-letter '
        'subscription, not through this one.',
      );

  @override
  Future<int> flush(String queue) async {
    // Seek to now: every message published before this instant is considered
    // acknowledged. Pub/Sub reports no count, and inventing one would be a
    // number nobody could act on.
    await transport.post('${subscriptionPath(queue)}:seek', <String, Object?>{
      'time': DateTime.now().toUtc().toIso8601String(),
    });
    return 0;
  }
}
