import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class SendWelcomeEmail {
  final String userId;
  const SendWelcomeEmail(this.userId);
}

final welcomeCodec = DVJobPayloadCodec<SendWelcomeEmail>(
  name: 'send_welcome_email',
  encode: (job) => <String, Object?>{'userId': job.userId},
  decode: (json) => SendWelcomeEmail(json['userId']! as String),
);

void main() {
  setUp(() {
    const DVJobPayloadCodecs().clear();
    const DVJobPayloadCodecs().register(welcomeCodec);
  });
  tearDown(const DVJobPayloadCodecs().clear);

  // Both adapters implement one contract, so the expectations are written once.
  void sharedContract(String name, DVQueueAdapter Function() create) {
    group('$name (DVQueueAdapter contract)', () {
      late DVQueueAdapter queue;

      setUp(() => queue = create());

      test('enqueues and reserves in FIFO order', () async {
        await queue.enqueue('mail', const SendWelcomeEmail('a'));
        await queue.enqueue('mail', const SendWelcomeEmail('b'));

        final first = await queue.reserve('mail');
        final second = await queue.reserve('mail');

        expect(first, isNotNull);
        expect(second, isNotNull);
        expect(first!.state, DVJobState.running);
        expect(first.payloadType, SendWelcomeEmail);
        expect(await queue.reserve('mail'), isNull);
      });

      test('reserves higher priority first', () async {
        await queue.enqueue('mail', const SendWelcomeEmail('low'));
        await queue.enqueue('mail', const SendWelcomeEmail('high'),
            priority: 10);

        final reserved = await queue.reserve('mail');
        expect(reserved!.priority, 10);
      });

      test('keeps queues isolated', () async {
        await queue.enqueue('mail', const SendWelcomeEmail('a'));
        expect(await queue.reserve('reports'), isNull);
        expect(await queue.reserve('mail'), isNotNull);
      });

      test('pending lists queued work and drops it once reserved', () async {
        await queue.enqueue('mail', const SendWelcomeEmail('a'));
        expect(await queue.pending('mail'), hasLength(1));

        await queue.reserve('mail');
        expect(await queue.pending('mail'), isEmpty);
      });

      test('a completed job leaves the queue', () async {
        final job = await queue.enqueue('mail', const SendWelcomeEmail('a'));
        await queue.reserve('mail');
        await queue.complete(job.id);

        expect(await queue.pending('mail'), isEmpty);
        expect(await queue.deadLetters('mail'), isEmpty);
      });

      test('a failed job is requeued until it dead-letters', () async {
        final job = await queue.enqueue(
          'mail',
          const SendWelcomeEmail('a'),
          maxAttempts: 2,
        );

        await queue.reserve('mail');
        await queue.fail(job.id, 'boom', StackTrace.empty);
        expect(await queue.pending('mail'), hasLength(1),
            reason: 'first failure retries rather than dropping the job');
        expect(await queue.deadLetters('mail'), isEmpty);

        await queue.reserve('mail');
        await queue.fail(job.id, 'boom again', StackTrace.empty);

        expect(await queue.pending('mail'), isEmpty);
        final dead = await queue.deadLetters('mail');
        expect(dead, hasLength(1), reason: 'failed jobs are never dropped');
        expect(dead.single.lastError, 'boom again');
      });

      test('retry moves a dead letter back to pending', () async {
        final job = await queue.enqueue(
          'mail',
          const SendWelcomeEmail('a'),
          maxAttempts: 1,
        );
        await queue.reserve('mail');
        await queue.fail(job.id, 'boom', StackTrace.empty);
        expect(await queue.deadLetters('mail'), hasLength(1));

        expect(await queue.retry(job.id), isTrue);
        expect(await queue.deadLetters('mail'), isEmpty);
        expect(await queue.pending('mail'), hasLength(1));
      });

      test('retry reports false for an unknown job', () async {
        expect(await queue.retry('does-not-exist'), isFalse);
      });

      test('discard drops one dead letter and leaves the rest', () async {
        // Flushing to be rid of a single poison message would take every
        // other job in the queue with it.
        final poison = await queue.enqueue(
          'mail',
          const SendWelcomeEmail('poison'),
          maxAttempts: 1,
        );
        await queue.reserve('mail');
        await queue.fail(poison.id, 'boom', StackTrace.empty);
        final other = await queue.enqueue(
          'mail',
          const SendWelcomeEmail('other'),
          maxAttempts: 1,
        );
        await queue.reserve('mail');
        await queue.fail(other.id, 'boom', StackTrace.empty);
        expect(await queue.deadLetters('mail'), hasLength(2));

        expect(await queue.discard(poison.id), isTrue);

        final remaining = await queue.deadLetters('mail');
        expect(remaining, hasLength(1));
        expect(remaining.single.id, other.id);
      });

      test('discard reports false for an unknown job', () async {
        expect(await queue.discard('does-not-exist'), isFalse);
      });

      test('discard leaves a queued job alone', () async {
        // A job waiting to run has not been abandoned; only a dead letter
        // has.
        final job = await queue.enqueue('mail', const SendWelcomeEmail('a'));

        expect(await queue.discard(job.id), isFalse);
        expect(await queue.pending('mail'), hasLength(1));
      });

      test('flush empties the queue', () async {
        await queue.enqueue('mail', const SendWelcomeEmail('a'));
        await queue.enqueue('mail', const SendWelcomeEmail('b'));

        expect(await queue.flush('mail'), greaterThan(0));
        expect(await queue.pending('mail'), isEmpty);
      });
    });
  }

  sharedContract('DVInMemoryQueueAdapter', DVInMemoryQueueAdapter.new);
  sharedContract(
    'DVDatabaseQueueAdapter',
    () => DVDatabaseQueueAdapter(SqliteDVDatabaseAdapter.memory()),
  );

  group('DVDatabaseQueueAdapter', () {
    test('a dispatched job survives a restart', () async {
      final dir = Directory.systemTemp.createTempSync('dartvel_queue_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/jobs.db';

      final firstDb = SqliteDVDatabaseAdapter.file(path);
      await DVDatabaseQueueAdapter(firstDb)
          .enqueue('mail', const SendWelcomeEmail('ada'));
      firstDb.close();

      // A fresh process opens the same file and drains the job.
      final secondDb = SqliteDVDatabaseAdapter.file(path);
      addTearDown(secondDb.close);
      final reserved = await DVDatabaseQueueAdapter(secondDb).reserve('mail');

      expect(reserved, isNotNull,
          reason: 'the in-memory adapter would have lost this');
      expect(reserved!.payloadType, SendWelcomeEmail);
    });

    test('a decoded payload reaches a typed handler through DVQueues',
        () async {
      final dir = Directory.systemTemp.createTempSync('dartvel_queue_e2e_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/jobs.db';

      // Dispatch in one "process"...
      final firstDb = SqliteDVDatabaseAdapter.file(path);
      const DVQueues().useAdapter(DVDatabaseQueueAdapter(firstDb));
      await const DVQueues()
          .dispatch(const SendWelcomeEmail('ada'), queue: 'mail');
      firstDb.close();

      // ...and drain it in another, where only the codec is registered.
      final secondDb = SqliteDVDatabaseAdapter.file(path);
      addTearDown(secondDb.close);
      const DVQueues().useAdapter(DVDatabaseQueueAdapter(secondDb));
      addTearDown(() => const DVQueues().useAdapter(DVInMemoryQueueAdapter()));

      final handled = <String>[];
      const DVQueues().register<SendWelcomeEmail>(
        (job) => handled.add(job.userId),
      );

      expect(await const DVQueues().work(queue: 'mail'), 1);
      expect(handled, <String>['ada'],
          reason: 'the payload survived JSON and arrived correctly typed');
    });

    test('refuses to persist a payload with no registered codec', () async {
      final db = SqliteDVDatabaseAdapter.memory();
      addTearDown(db.close);
      final queue = DVDatabaseQueueAdapter(db);

      await expectLater(
        queue.enqueue('mail', const Duration(seconds: 1)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('No DVJobPayloadCodec registered'),
                contains('DVInMemoryQueueAdapter')),
          ),
        ),
      );
      expect(await queue.pending('mail'), isEmpty);
    });

    test('fails loudly when a stored codec is missing after a restart',
        () async {
      final db = SqliteDVDatabaseAdapter.memory();
      addTearDown(db.close);
      final queue = DVDatabaseQueueAdapter(db);
      await queue.enqueue('mail', const SendWelcomeEmail('ada'));

      // Simulates a deploy that dropped the codec registration.
      const DVJobPayloadCodecs().clear();

      await expectLater(
        queue.reserve('mail'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('not registered in this process'),
          ),
        ),
      );
    });

    test('rejects an unsafe table name', () {
      final db = SqliteDVDatabaseAdapter.memory();
      addTearDown(db.close);

      expect(
        () => DVDatabaseQueueAdapter(db, tableName: 'jobs; DROP TABLE users'),
        throwsArgumentError,
      );
    });
  });

  group('DVJobPayloadCodecs', () {
    test('rejects an empty codec name', () {
      expect(
        () => const DVJobPayloadCodecs().register(
          DVJobPayloadCodec<String>(
            name: '  ',
            encode: (value) => <String, Object?>{'v': value},
            decode: (json) => json['v']! as String,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('rejects reusing one name for a different payload type', () {
      expect(
        () => const DVJobPayloadCodecs().register(
          DVJobPayloadCodec<String>(
            name: 'send_welcome_email',
            encode: (value) => <String, Object?>{'v': value},
            decode: (json) => json['v']! as String,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('reports which types it can persist', () {
      expect(const DVJobPayloadCodecs().supports(SendWelcomeEmail), isTrue);
      expect(const DVJobPayloadCodecs().supports(Duration), isFalse);
      expect(const DVJobPayloadCodecs().names, contains('send_welcome_email'));
    });
  });
}
