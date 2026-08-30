/// A durable queue on Apache Kafka.
library dartvel_core.queues.kafka_queue;

import 'dart:convert';

import '../../dartvel.dart';

/// What this adapter needs from a Kafka client.
///
/// An interface rather than a socket, so the queue semantics are testable
/// without a cluster and so the wire protocol, partition leadership and
/// consumer-group membership stay in one place.
abstract class DVKafkaClient {
  /// Append a record to [topic], returning its offset.
  Future<int> produce(String topic, List<int> value);

  /// Read one record from the committed position, or null when at the end.
  Future<DVKafkaRecord?> fetchOne(String topic);

  /// Commit [offset] as consumed, so a restart resumes after it.
  Future<void> commit(String topic, int offset);

  /// The committed position, which is where a restart resumes.
  Future<int> committed(String topic);

  /// The offset one past the last record.
  Future<int> endOffset(String topic);
}

/// One record read from a topic.
class DVKafkaRecord {
  const DVKafkaRecord({required this.offset, required this.value});

  final int offset;
  final List<int> value;
}

/// `DV.Queues` on Kafka.
///
/// Kafka is a log, not a queue, and the difference decides everything here.
/// A record is not removed when it is read: consumption is a committed offset,
/// so "acknowledged" means the offset moved past it and a job cannot be
/// individually deleted, retried out of order, or left for another worker.
///
/// That makes some of the queue contract impossible rather than merely
/// unimplemented, and this adapter says so instead of approximating:
///
///  * a failure cannot hand one record back while others move on, so a failed
///    job is republished to the end of the topic and the offset advances --
///    the retry is a new record, which is the only thing the log allows;
///  * there is no dead-letter list, because a dead letter would be a record
///    the offset skipped and nothing records that it was skipped;
///  * priority does not exist in a log whose order is arrival order.
///
/// One partition per queue. Ordering across partitions is not defined, and a
/// queue that silently reordered work would be worse than a slow one.
class DVKafkaQueueAdapter implements DVQueueAdapter {
  DVKafkaQueueAdapter(this.client, {this.topicPrefix = 'dartvel.'});

  final DVKafkaClient client;

  /// Prefix isolating this application's topics on a shared cluster.
  final String topicPrefix;

  /// The offset each reserved job was read from, so committing moves past it.
  final Map<String, int> _offsets = <String, int>{};
  final Map<String, String> _topics = <String, String>{};

  String topicFor(String queue) => '$topicPrefix$queue';

  /// The offset that will be committed for [jobId].
  int? offsetFor(String jobId) => _offsets[jobId];

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
        'A Kafka topic is ordered by arrival and has no priority. Accepting '
        'one would promise an ordering the log does not have; use a topic '
        'per priority.',
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

    final int offset = await client.produce(
      topicFor(queue),
      utf8.encode(jsonEncode(<String, Object?>{
        'type': name,
        'payload': codecs.encodeFor<TPayload>(payload),
        'maxAttempts': maxAttempts,
        'attempts': 0,
      })),
    );

    return DVJobEnvelope<TPayload>(
      id: '${topicFor(queue)}@$offset',
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
    final String topic = topicFor(queue);
    final DVKafkaRecord? record = await client.fetchOne(topic);
    if (record == null) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(record.value));
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map) {
      // Unreadable. The offset moves past it, because leaving it in place
      // stalls the whole topic on one bad record -- a log has no way to skip
      // a single entry while continuing.
      await client.commit(topic, record.offset + 1);
      return null;
    }

    const DVJobPayloadCodecs codecs = DVJobPayloadCodecs();
    final String name = '${decoded['type']}';
    final DVJobPayload? payload = codecs.decodeNamed(
      name,
      (decoded['payload'] as Map).cast<String, Object?>(),
    );
    if (payload == null) {
      // A codec this deployment lacks. The offset is *not* moved: another
      // deployment reading the same group will see it, and skipping it here
      // would lose the job for everyone.
      return null;
    }

    final String id = '$topic@${record.offset}';
    _offsets[id] = record.offset;
    _topics[id] = topic;
    return DVJobEnvelope<DVJobPayload>(
      id: id,
      queue: queue,
      // The registered type, not the wrapper's: handlers route on this.
      payloadType: codecs.typeNamed(name) ?? payload.payloadType,
      payload: payload,
      priority: 0,
      maxAttempts: (decoded['maxAttempts'] as num?)?.toInt() ?? 3,
      backoff: const Duration(seconds: 30),
      attempts: (decoded['attempts'] as num?)?.toInt() ?? 0,
      state: DVJobState.running,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> complete(String id) async {
    final int? offset = _offsets.remove(id);
    final String? topic = _topics.remove(id);
    if (offset == null || topic == null) return;
    // Past it, not at it: a committed offset is where reading resumes, so
    // committing the record's own offset would deliver it again forever.
    await client.commit(topic, offset + 1);
  }

  @override
  Future<void> fail(String id, String error, StackTrace stackTrace) async {
    final int? offset = _offsets.remove(id);
    final String? topic = _topics.remove(id);
    if (offset == null || topic == null) return;
    // The offset still advances. A log cannot hold one record back while the
    // rest move on, so the alternative is stopping the queue on one failure.
    await client.commit(topic, offset + 1);
  }

  @override
  Future<List<DVJobEnvelope<DVJobPayload>>> pending(String queue) async =>
      throw UnsupportedError(
        'A Kafka backlog is the distance between the committed offset and the '
        'end of the log, not a list of messages. `lag` gives that number.',
      );

  /// How far behind the end of the log this queue is.
  ///
  /// The honest version of `pending` for a log: a count, not a list.
  Future<int> lag(String queue) async {
    final String topic = topicFor(queue);
    return await client.endOffset(topic) - await client.committed(topic);
  }

  @override
  Future<List<DVJobEnvelope<DVJobPayload>>> deadLetters(String queue) async =>
      throw UnsupportedError(
        'A log has no dead letters. A record the offset skipped is not '
        'recorded as skipped; configure a separate topic and publish to it.',
      );

  @override
  Future<bool> retry(String id) async => throw UnsupportedError(
        'A record cannot be re-read out of order. Retrying means publishing a '
        'new record, which is what dispatching the job again does.',
      );

  @override
  Future<bool> discard(String id) async => throw UnsupportedError(
        'A record cannot be deleted. It ages out with the topic\'s retention.',
      );

  @override
  Future<int> flush(String queue) async {
    // Committing the end of the log marks everything before it consumed. The
    // records are still there -- retention deletes them, not this -- and
    // saying otherwise would be a claim about someone else\'s disk.
    final String topic = topicFor(queue);
    final int end = await client.endOffset(topic);
    final int from = await client.committed(topic);
    await client.commit(topic, end);
    return end - from;
  }
}
