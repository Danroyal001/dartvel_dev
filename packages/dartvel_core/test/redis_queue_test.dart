// Runs against a real Redis at localhost:6379 — no scripted server.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class Ping {
  final String label;

  const Ping(this.label);
}

Future<bool> _reachable() async {
  try {
    final socket = await Socket.connect('127.0.0.1', 6379,
        timeout: const Duration(seconds: 1));
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}

void main() async {
  if (!await _reachable()) {
    test(
      'redis queue adapter (skipped: no Redis at localhost:6379)',
      () {},
      skip: 'Start redis-server to run these.',
    );
    return;
  }

  late DVRedisClient client;
  late DVRedisQueueAdapter adapter;

  setUp(() async {
    const DVJobPayloadCodecs().register(
      DVJobPayloadCodec<Ping>(
        name: 'Ping',
        encode: (Ping job) => <String, Object?>{'label': job.label},
        decode: (Map<String, Object?> json) => Ping('${json['label']}'),
      ),
    );
    client = await DVRedisClient.connect();
    adapter = DVRedisQueueAdapter(client, keyPrefix: 'dvtest:queue:');
    await adapter.flush('mail');
  });

  tearDown(() async {
    await adapter.flush('mail');
    await client.close();
  });

  test('an enqueued job comes back to a worker', () async {
    await adapter.enqueue<Ping>('mail', const Ping('welcome'));

    final reserved = await adapter.reserve('mail');
    expect(reserved, isNotNull);
    expect(reserved!.payloadType, Ping);
    expect(reserved.state, DVJobState.running);
  });

  test('reserving removes the job so two workers cannot take it', () async {
    // The property an in-memory queue gets for free and a distributed one
    // has to earn.
    await adapter.enqueue<Ping>('mail', const Ping('once'));

    final first = await adapter.reserve('mail');
    final second = await adapter.reserve('mail');

    expect(first, isNotNull);
    expect(second, isNull);
  });

  test('higher priority is served first, then oldest', () async {
    await adapter.enqueue<Ping>('mail', const Ping('low'));
    await adapter.enqueue<Ping>('mail', const Ping('high'), priority: 10);
    await adapter.enqueue<Ping>('mail', const Ping('low2'));

    // Ordering is observable through the handler each job reaches, which is
    // also the path an application actually uses.
    final seen = <String>[];
    const DVQueues()
      ..useAdapter(adapter)
      ..register<Ping>((Ping job) => seen.add(job.label));
    addTearDown(() => const DVQueues().useAdapter(DVInMemoryQueueAdapter()));

    expect(await const DVQueues().work(queue: 'mail', maxJobs: 3), 3);
    expect(seen, <String>['high', 'low', 'low2']);
  });

  test('completing removes the job entirely', () async {
    final job = await adapter.enqueue<Ping>('mail', const Ping('done'));
    await adapter.reserve('mail');

    await adapter.complete(job.id);

    expect(await adapter.pending('mail'), isEmpty);
    expect(await adapter.deadLetters('mail'), isEmpty);
  });

  test('a failure requeues until attempts run out, then dead-letters',
      () async {
    final job = await adapter.enqueue<Ping>(
      'mail',
      const Ping('flaky'),
      maxAttempts: 2,
    );

    await adapter.reserve('mail');
    await adapter.fail(job.id, 'boom', StackTrace.current);
    // Still retryable, so it is back in the queue rather than gone.
    expect(await adapter.pending('mail'), hasLength(1));

    await adapter.reserve('mail');
    await adapter.fail(job.id, 'boom again', StackTrace.current);

    // A failed job is never silently dropped.
    expect(await adapter.pending('mail'), isEmpty);
    final dead = await adapter.deadLetters('mail');
    expect(dead, hasLength(1));
    expect(dead.single.attempts, 2);
    expect(dead.single.lastError, 'boom again');
  });

  test('retry moves a dead letter back, keeping its attempt history',
      () async {
    final job = await adapter.enqueue<Ping>(
      'mail',
      const Ping('retryable'),
      maxAttempts: 1,
    );
    await adapter.reserve('mail');
    await adapter.fail(job.id, 'boom', StackTrace.current);
    expect(await adapter.deadLetters('mail'), hasLength(1));

    expect(await adapter.retry(job.id), isTrue);

    expect(await adapter.deadLetters('mail'), isEmpty);
    final pending = await adapter.pending('mail');
    expect(pending, hasLength(1));
    // Resetting the count would hide a job that fails forever.
    expect(pending.single.attempts, 1);
    expect(pending.single.payloadType, Ping);
  });

  test('retrying an unknown job reports false rather than pretending',
      () async {
    expect(await adapter.retry('job-does-not-exist'), isFalse);
  });

  test('flush clears queued and dead letters and reports the count', () async {
    await adapter.enqueue<Ping>('mail', const Ping('a'));
    final b = await adapter.enqueue<Ping>('mail', const Ping('b'),
        maxAttempts: 1);
    await adapter.reserve('mail');
    await adapter.fail(b.id, 'x', StackTrace.current);

    final flushed = await adapter.flush('mail');

    expect(flushed, 2);
    expect(await adapter.pending('mail'), isEmpty);
    expect(await adapter.deadLetters('mail'), isEmpty);
  });

  test('a payload with no registered codec is refused, not dropped', () async {
    // A durable queue that silently drops unencodable work loses it with no
    // trace.
    await expectLater(
      adapter.enqueue<String>('mail', 'not a registered payload'),
      throwsA(isA<StateError>()),
    );
  });

  test('jobs survive a new adapter over a new connection', () async {
    await adapter.enqueue<Ping>('mail', const Ping('durable'));

    final other = await DVRedisClient.connect();
    addTearDown(other.close);
    final second = DVRedisQueueAdapter(other, keyPrefix: 'dvtest:queue:');

    // Durability is the whole point: a restart must not lose queued work.
    final reserved = await second.reserve('mail');
    expect(reserved, isNotNull);
    expect(reserved!.payloadType, Ping);
  });
}
