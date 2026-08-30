/// A durable queue on RabbitMQ, over AMQP 0-9-1.
library dartvel_core.queues.amqp_queue;

import 'dart:convert';

import '../../dartvel.dart';

/// What this adapter needs from an AMQP connection.
///
/// An interface rather than a socket, for the same reason the Postgres and
/// MySQL adapters abstract theirs: the protocol is then testable without a
/// broker, and connection management, heartbeats and reconnection stay with
/// whatever owns the connection.
abstract class DVAmqpChannel {
  /// Declare a durable queue, creating it if absent.
  Future<void> declareQueue(String name, {required bool durable});

  /// Publish to the default exchange, routed by queue name.
  Future<void> publish(
    String queue,
    List<int> body, {
    required bool persistent,
    int priority,
  });

  /// Take one message without acknowledging it, or null when none is waiting.
  Future<DVAmqpMessage?> get(String queue);

  /// Acknowledge, removing it from the broker.
  Future<void> ack(int deliveryTag);

  /// Reject, and requeue it or send it to the dead-letter exchange.
  Future<void> nack(int deliveryTag, {required bool requeue});

  /// Remove every message, returning how many went.
  Future<int> purge(String queue);
}

/// One delivery.
class DVAmqpMessage {
  const DVAmqpMessage({
    required this.deliveryTag,
    required this.body,
    this.redelivered = false,
  });

  /// The channel-scoped tag that acknowledges this delivery.
  final int deliveryTag;

  final List<int> body;

  /// Whether the broker has handed this out before.
  final bool redelivered;
}

/// `DV.Queues` on RabbitMQ.
///
/// Durability here is the broker's: a queue declared durable and a message
/// published persistent survive a restart. This adapter does not keep its own
/// record of pending work, because a second record is a second source of
/// truth and they disagree the moment one of them is the one that crashed.
///
/// Dead letters are a queue like any other. RabbitMQ moves a rejected message
/// to whatever the `x-dead-letter-exchange` argument names, so this adapter
/// reads them by name rather than pretending to own a list.
class DVAmqpQueueAdapter implements DVQueueAdapter {
  DVAmqpQueueAdapter(
    this.channel, {
    this.deadLetterSuffix = '.dead',
  });

  final DVAmqpChannel channel;

  /// The queue dead letters land in, for a queue of a given name.
  final String deadLetterSuffix;

  final Map<String, int> _tags = <String, int>{};
  final Set<String> _declared = <String>{};
  int _sequence = 0;

  /// The delivery tag that will acknowledge [jobId].
  int? tagFor(String jobId) => _tags[jobId];

  String deadLetterQueue(String queue) => '$queue$deadLetterSuffix';

  Future<void> _ensure(String queue) async {
    if (!_declared.add(queue)) return;
    await channel.declareQueue(queue, durable: true);
  }

  @override
  Future<DVJobEnvelope<TPayload>> enqueue<TPayload>(
    String queue,
    TPayload payload, {
    int priority = 0,
    int maxAttempts = 3,
    Duration backoff = const Duration(seconds: 30),
  }) async {
    const DVJobPayloadCodecs codecs = DVJobPayloadCodecs();
    final String? name = codecs.nameFor<TPayload>();
    if (name == null) {
      throw StateError(
        'No DVJobPayloadCodec registered for $TPayload, so it cannot be '
        'persisted. Register one, or use DVInMemoryQueueAdapter.',
      );
    }

    await _ensure(queue);
    final String id = 'amqp-${DateTime.now().microsecondsSinceEpoch}-'
        '${_sequence++}';
    await channel.publish(
      queue,
      utf8.encode(jsonEncode(<String, Object?>{
        'id': id,
        'type': name,
        'payload': codecs.encodeFor<TPayload>(payload),
        'maxAttempts': maxAttempts,
      })),
      // Durable queue, transient message is the combination that looks
      // durable and loses everything on a restart.
      persistent: true,
      priority: priority,
    );

    return DVJobEnvelope<TPayload>(
      id: id,
      queue: queue,
      payloadType: TPayload,
      payload: payload,
      priority: priority,
      maxAttempts: maxAttempts,
      backoff: backoff,
      attempts: 0,
      state: DVJobState.queued,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<DVJobEnvelope<DVJobPayload>?> reserve(String queue) async {
    await _ensure(queue);
    final DVAmqpMessage? message = await channel.get(queue);
    if (message == null) return null;

    // Wrapped, because jsonDecode throws on malformed input rather than
    // returning null -- so a single corrupt message would take down the
    // worker that picked it up instead of being dead-lettered.
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(message.body));
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map) {
      // Unreadable, and requeueing it would hand the same broken message to
      // the next worker forever. It goes to the dead-letter exchange.
      await channel.nack(message.deliveryTag, requeue: false);
      return null;
    }

    const DVJobPayloadCodecs codecs = DVJobPayloadCodecs();
    final DVJobPayload? payload = codecs.decodeNamed(
      '${decoded['type']}',
      (decoded['payload'] as Map).cast<String, Object?>(),
    );
    if (payload == null) {
      // A codec this deployment does not have. Requeued rather than dead
      // lettered: another deployment may be able to run it.
      await channel.nack(message.deliveryTag, requeue: true);
      return null;
    }

    final String id = '${decoded['id']}';
    _tags[id] = message.deliveryTag;
    return DVJobEnvelope<DVJobPayload>(
      id: id,
      queue: queue,
      // The registered type, not the wrapper's. Handlers are routed by
      // payloadType, and a decoded payload is a _DVStoredJobPayload<T> --
      // so runtimeType here is the wrapper and no handler ever matches.
      payloadType: codecs.typeNamed('${decoded['type']}') ?? payload.payloadType,
      payload: payload,
      priority: 0,
      maxAttempts: (decoded['maxAttempts'] as num?)?.toInt() ?? 3,
      backoff: const Duration(seconds: 30),
      attempts: message.redelivered ? 1 : 0,
      state: DVJobState.running,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> complete(String id) async {
    final int? tag = _tags.remove(id);
    if (tag == null) return;
    await channel.ack(tag);
  }

  @override
  Future<void> fail(String id, String error, StackTrace stackTrace) async {
    final int? tag = _tags.remove(id);
    if (tag == null) return;
    // Not requeued. RabbitMQ has no attempt counter of its own, so requeueing
    // a job that fails every time is an infinite loop at full speed; the
    // dead-letter exchange is where a failure belongs.
    await channel.nack(tag, requeue: false);
  }

  @override
  Future<List<DVJobEnvelope<DVJobPayload>>> pending(String queue) async =>
      throw UnsupportedError(
        'AMQP has no way to read a queue without consuming from it. Reading '
        'here would take the messages out of it, which is the opposite of '
        'inspecting. Use the management API for a count.',
      );

  @override
  Future<List<DVJobEnvelope<DVJobPayload>>> deadLetters(String queue) =>
      throw UnsupportedError(
        'Dead letters are an ordinary queue -- ${deadLetterSuffix} by '
        'convention -- reached by pointing an adapter at it, because reading '
        'it is consuming from it.',
      );

  @override
  Future<bool> retry(String id) async => throw UnsupportedError(
        'Retrying means republishing from the dead-letter queue to the live '
        'one, which is two adapters rather than an id.',
      );

  @override
  Future<bool> discard(String id) async => throw UnsupportedError(
        'A dead-lettered message is acknowledged on the dead-letter queue, '
        'not through this one.',
      );

  @override
  Future<int> flush(String queue) async {
    await _ensure(queue);
    return channel.purge(queue);
  }
}
