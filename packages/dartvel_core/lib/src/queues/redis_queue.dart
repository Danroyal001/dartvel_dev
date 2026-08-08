/// A durable queue on Redis (or Valkey).
library dartvel_core.queues.redis_queue;

import 'dart:convert';

import '../../dartvel.dart';

/// `DV.Queues` on Redis.
///
/// Jobs live in three structures per queue: a sorted set of queued work
/// ordered by priority then age, a hash of reserved jobs, and a list of dead
/// letters. A worker reserves atomically, so two workers cannot take the same
/// job — the property an in-memory queue gets for free and a distributed one
/// has to earn.
class DVRedisQueueAdapter implements DVQueueAdapter {
  final DVRedisClient client;

  /// Prefix isolating this application's queues on a shared server.
  final String keyPrefix;

  int _sequence = 0;

  DVRedisQueueAdapter(this.client, {this.keyPrefix = 'dartvel:queue:'});

  String _queued(String queue) => '$keyPrefix$queue:queued';
  String _reserved(String queue) => '$keyPrefix$queue:reserved';
  String _dead(String queue) => '$keyPrefix$queue:dead';
  String _job(String id) => '$keyPrefix job:$id'.replaceAll(' ', '');

  @override
  Future<DVJobEnvelope<TPayload>> enqueue<TPayload>(
    String queue,
    TPayload payload, {
    int priority = 0,
    int maxAttempts = 3,
    Duration backoff = const Duration(seconds: 30),
  }) async {
    const codecs = DVJobPayloadCodecs();
    final name = codecs.nameFor<TPayload>();
    if (name == null) {
      throw StateError(
        'No DVJobPayloadCodec registered for $TPayload, so it cannot be '
        'persisted. Register one, or use DVInMemoryQueueAdapter.',
      );
    }

    final envelope = DVJobEnvelope<TPayload>(
      id: 'job-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
      queue: queue,
      payloadType: TPayload,
      payload: payload,
      priority: priority,
      maxAttempts: maxAttempts,
      backoff: backoff,
      createdAt: DateTime.now(),
      attempts: 0,
      state: DVJobState.queued,
    );

    await client.command(<String>[
      'SET',
      _job(envelope.id),
      jsonEncode(<String, Object?>{
        'id': envelope.id,
        'queue': queue,
        'payloadName': name,
        'payload': codecs.encodeFor<TPayload>(payload),
        'priority': priority,
        'maxAttempts': maxAttempts,
        'backoffMs': backoff.inMilliseconds,
        'createdAt': envelope.createdAt.millisecondsSinceEpoch,
        'attempts': 0,
        'state': DVJobState.queued.name,
        'lastError': null,
      }),
    ]);
    // Score orders by priority first, then age. Negating priority makes a
    // plain ascending range give highest-priority-oldest-first in one read.
    final score = (-priority * 1e13) + envelope.createdAt.microsecondsSinceEpoch;
    await client.command(<String>[
      'ZADD',
      _queued(queue),
      '$score',
      envelope.id,
    ]);
    return envelope;
  }

  @override
  Future<DVJobEnvelope<DVJobPayload>?> reserve(String queue) async {
    // ZPOPMIN removes and returns in one operation, so two workers polling
    // the same queue cannot both take the same job.
    final popped =
        await client.command(<String>['ZPOPMIN', _queued(queue)]) as List<Object?>;
    if (popped.isEmpty) return null;
    final id = '${popped.first}';

    final raw = await client.command(<String>['GET', _job(id)]);
    if (raw is! String) return null;
    final data = (jsonDecode(raw) as Map).cast<String, Object?>();
    data['state'] = DVJobState.running.name;
    await client.command(<String>['SET', _job(id), jsonEncode(data)]);
    await client.command(<String>['HSET', _reserved(queue), id, '1']);
    return _envelopeFrom(data);
  }

  @override
  Future<void> complete(String id) async {
    final data = await _load(id);
    if (data == null) return;
    await client.command(
      <String>['HDEL', _reserved('${data['queue']}'), id],
    );
    await client.command(<String>['DEL', _job(id)]);
  }

  @override
  Future<void> fail(String id, String error, StackTrace stackTrace) async {
    final data = await _load(id);
    if (data == null) return;
    final queue = '${data['queue']}';
    final attempts = ((data['attempts'] as num?)?.toInt() ?? 0) + 1;
    final maxAttempts = (data['maxAttempts'] as num?)?.toInt() ?? 3;
    data['attempts'] = attempts;
    data['lastError'] = error;
    await client.command(<String>['HDEL', _reserved(queue), id]);

    if (attempts >= maxAttempts) {
      // Out of attempts: a failed job is never dropped, it becomes a dead
      // letter that can be inspected and replayed.
      data['state'] = DVJobState.deadLettered.name;
      await client.command(<String>['SET', _job(id), jsonEncode(data)]);
      await client.command(<String>['RPUSH', _dead(queue), id]);
      return;
    }

    data['state'] = DVJobState.queued.name;
    await client.command(<String>['SET', _job(id), jsonEncode(data)]);
    final createdAt = (data['createdAt'] as num?)?.toInt() ?? 0;
    final priority = (data['priority'] as num?)?.toInt() ?? 0;
    await client.command(<String>[
      'ZADD',
      _queued(queue),
      '${(-priority * 1e13) + createdAt * 1000}',
      id,
    ]);
  }

  @override
  Future<List<DVJobEnvelope<DVJobPayload>>> pending(String queue) async {
    final ids = await client.command(
      <String>['ZRANGE', _queued(queue), '0', '-1'],
    ) as List<Object?>;
    return _loadAll(ids);
  }

  @override
  Future<List<DVJobEnvelope<DVJobPayload>>> deadLetters(String queue) async {
    final ids = await client.command(
      <String>['LRANGE', _dead(queue), '0', '-1'],
    ) as List<Object?>;
    return _loadAll(ids);
  }

  @override
  Future<bool> retry(String id) async {
    final data = await _load(id);
    if (data == null) return false;
    final queue = '${data['queue']}';
    // Retrying preserves the payload and the attempt history; resetting the
    // count would hide a job that fails forever.
    data['state'] = DVJobState.queued.name;
    await client.command(<String>['SET', _job(id), jsonEncode(data)]);
    await client.command(<String>['LREM', _dead(queue), '0', id]);
    final createdAt = (data['createdAt'] as num?)?.toInt() ?? 0;
    final priority = (data['priority'] as num?)?.toInt() ?? 0;
    await client.command(<String>[
      'ZADD',
      _queued(queue),
      '${(-priority * 1e13) + createdAt * 1000}',
      id,
    ]);
    return true;
  }

  @override
  Future<bool> discard(String id) async {
    final data = await _load(id);
    if (data == null) return false;
    // Only from the dead-letter list: a queued job is still expected to run.
    final queue = '${data['queue']}';
    final removed = await client.command(
      <String>['LREM', _dead(queue), '0', id],
    );
    if (removed is int && removed == 0) return false;
    await client.command(<String>['DEL', _job(id)]);
    return true;
  }

  @override
  Future<int> flush(String queue) async {
    final queued = await client.command(
      <String>['ZRANGE', _queued(queue), '0', '-1'],
    ) as List<Object?>;
    final dead = await client.command(
      <String>['LRANGE', _dead(queue), '0', '-1'],
    ) as List<Object?>;
    // Reserved jobs count too. Dropping only the tracking hash would leave
    // their payload keys orphaned in Redis, so a flushed queue would still
    // be holding data.
    final reserved = await client.command(
      <String>['HKEYS', _reserved(queue)],
    ) as List<Object?>;
    final ids = <String>{
      for (final id in queued) '$id',
      for (final id in dead) '$id',
      for (final id in reserved) '$id',
    };
    for (final id in ids) {
      await client.command(<String>['DEL', _job(id)]);
    }
    await client.command(<String>['DEL', _queued(queue)]);
    await client.command(<String>['DEL', _dead(queue)]);
    await client.command(<String>['DEL', _reserved(queue)]);
    return ids.length;
  }

  Future<Map<String, Object?>?> _load(String id) async {
    final raw = await client.command(<String>['GET', _job(id)]);
    if (raw is! String) return null;
    return (jsonDecode(raw) as Map).cast<String, Object?>();
  }

  Future<List<DVJobEnvelope<DVJobPayload>>> _loadAll(List<Object?> ids) async {
    final envelopes = <DVJobEnvelope<DVJobPayload>>[];
    for (final id in ids) {
      final data = await _load('$id');
      if (data == null) continue;
      final envelope = _envelopeFrom(data);
      if (envelope != null) envelopes.add(envelope);
    }
    return envelopes;
  }

  DVJobEnvelope<DVJobPayload>? _envelopeFrom(Map<String, Object?> data) {
    const codecs = DVJobPayloadCodecs();
    final name = '${data['payloadName']}';
    final payload = codecs.decodeNamed(
      name,
      (data['payload'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{},
    );
    if (payload == null) return null;
    return DVJobEnvelope<DVJobPayload>(
      id: '${data['id']}',
      queue: '${data['queue']}',
      payloadType: codecs.typeNamed(name) ?? payload.runtimeType,
      payload: payload,
      priority: (data['priority'] as num?)?.toInt() ?? 0,
      maxAttempts: (data['maxAttempts'] as num?)?.toInt() ?? 3,
      backoff: Duration(
        milliseconds: (data['backoffMs'] as num?)?.toInt() ?? 30000,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (data['createdAt'] as num?)?.toInt() ?? 0,
      ),
      attempts: (data['attempts'] as num?)?.toInt() ?? 0,
      state: DVJobState.values.firstWhere(
        (DVJobState state) => state.name == data['state'],
        orElse: () => DVJobState.queued,
      ),
      lastError: data['lastError'] as String?,
    );
  }
}
