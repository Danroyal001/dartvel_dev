// DV.Queues on Kafka.
//
// Kafka is a log, not a queue, and most of this suite is about the difference.
// A record is not removed when it is read -- consumption is a committed offset
// -- so a job cannot be individually deleted, retried out of order, or left
// behind for another worker. An adapter that approximated those would be
// lying about what happens to work that fails.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/queues/kafka_queue.dart';
import 'package:test/test.dart';

class FakeKafka implements DVKafkaClient {
  final Map<String, List<List<int>>> log = <String, List<List<int>>>{};
  final Map<String, int> commits = <String, int>{};

  @override
  Future<int> produce(String topic, List<int> value) async {
    final List<List<int>> records = log.putIfAbsent(topic, () => <List<int>>[]);
    records.add(value);
    return records.length - 1;
  }

  @override
  Future<DVKafkaRecord?> fetchOne(String topic) async {
    final int at = commits[topic] ?? 0;
    final List<List<int>> records = log[topic] ?? <List<int>>[];
    if (at >= records.length) return null;
    return DVKafkaRecord(offset: at, value: records[at]);
  }

  @override
  Future<void> commit(String topic, int offset) async {
    commits[topic] = offset;
  }

  @override
  Future<int> committed(String topic) async => commits[topic] ?? 0;

  @override
  Future<int> endOffset(String topic) async => (log[topic] ?? const []).length;
}

class _Ping {
  const _Ping(this.note);
  final String note;
}

void main() {
  late FakeKafka kafka;
  late DVKafkaQueueAdapter adapter;

  setUp(() {
    kafka = FakeKafka();
    adapter = DVKafkaQueueAdapter(kafka);
    const DVJobPayloadCodecs().register(
      DVJobPayloadCodec<_Ping>(
        name: 'ping',
        encode: (_Ping job) => <String, Object?>{'note': job.note},
        decode: (Map<String, Object?> json) => _Ping(json['note']! as String),
      ),
    );
  });

  group('the log', () {
    test('a queue is one prefixed topic', () {
      expect(adapter.topicFor('mail'), 'dartvel.mail');
    });

    test('producing appends and reports the offset', () async {
      final DVJobEnvelope<_Ping> first =
          await adapter.enqueue('mail', const _Ping('a'));
      final DVJobEnvelope<_Ping> second =
          await adapter.enqueue('mail', const _Ping('b'));

      expect(first.id, 'dartvel.mail@0');
      expect(second.id, 'dartvel.mail@1');
    });

    test('priority is refused, because a log is ordered by arrival', () async {
      await expectLater(
        adapter.enqueue('mail', const _Ping('a'), priority: 2),
        throwsUnsupportedError,
      );
    });

    test('an unregistered payload is refused', () async {
      await expectLater(
          adapter.enqueue('mail', DateTime.now()), throwsStateError);
    });
  });

  group('reading', () {
    test('an empty topic is null', () async {
      expect(await adapter.reserve('mail'), isNull);
    });

    test('reading does not consume: the offset moves on commit', () async {
      // The property that makes this a log. Reading twice without committing
      // returns the same record, which is why complete() has to move past it.
      await adapter.enqueue('mail', const _Ping('a'));

      final DVJobEnvelope<DVJobPayload> first = (await adapter.reserve('mail'))!;
      final DVJobEnvelope<DVJobPayload> again = (await adapter.reserve('mail'))!;

      expect(first.id, again.id);
    });

    test('the registered type is what routes it', () async {
      await adapter.enqueue('mail', const _Ping('a'));

      expect((await adapter.reserve('mail'))!.payloadType, _Ping);
    });

    test('an unreadable record is skipped, or it stalls the topic', () async {
      // A log cannot skip one entry while continuing, so leaving it in place
      // stops every job behind it forever.
      await kafka.produce('dartvel.mail', utf8.encode('{'));

      expect(await adapter.reserve('mail'), isNull);
      expect(kafka.commits['dartvel.mail'], 1);
    });

    test('a payload with no codec here is left for another deployment',
        () async {
      // Different from unreadable: the record is fine and another deployment
      // may have the codec. Skipping it would lose the job for everyone,
      // because a committed offset is shared by the group.
      await kafka.produce(
        'dartvel.mail',
        utf8.encode(jsonEncode(<String, Object?>{
          'type': 'not_registered',
          'payload': <String, Object?>{},
        })),
      );

      expect(await adapter.reserve('mail'), isNull);
      expect(kafka.commits['dartvel.mail'], isNull,
          reason: 'the offset must not move past a job someone else can run');
    });
  });

  group('settling', () {
    test('completing commits past the record, not at it', () async {
      // Committing the record's own offset re-delivers it forever.
      await adapter.enqueue('mail', const _Ping('a'));
      final DVJobEnvelope<DVJobPayload> job = (await adapter.reserve('mail'))!;
      await adapter.complete(job.id);

      expect(kafka.commits['dartvel.mail'], 1);
      expect(await adapter.reserve('mail'), isNull);
    });

    test('failing also advances, because a log cannot hold one back',
        () async {
      // The honest behaviour. Not advancing stops the queue on one failure;
      // there is no third option in a log.
      await adapter.enqueue('mail', const _Ping('a'));
      await adapter.enqueue('mail', const _Ping('b'));
      final DVJobEnvelope<DVJobPayload> job = (await adapter.reserve('mail'))!;
      await adapter.fail(job.id, 'boom', StackTrace.current);

      expect(kafka.commits['dartvel.mail'], 1);
      expect((await adapter.reserve('mail'))!.id, 'dartvel.mail@1');
    });

    test('settling something never reserved does nothing', () async {
      await adapter.complete('dartvel.mail@9');

      expect(kafka.commits, isEmpty);
    });
  });

  group('what a log cannot do', () {
    test('there is no list of pending messages, only a distance', () async {
      await adapter.enqueue('mail', const _Ping('a'));
      await adapter.enqueue('mail', const _Ping('b'));

      await expectLater(adapter.pending('mail'), throwsUnsupportedError);
      expect(await adapter.lag('mail'), 2);
    });

    test('no dead letters, no retry, no discard', () async {
      await expectLater(adapter.deadLetters('mail'), throwsUnsupportedError);
      await expectLater(adapter.retry('x'), throwsUnsupportedError);
      await expectLater(adapter.discard('x'), throwsUnsupportedError);
    });

    test('flush commits the end and says how many it passed', () async {
      await adapter.enqueue('mail', const _Ping('a'));
      await adapter.enqueue('mail', const _Ping('b'));

      expect(await adapter.flush('mail'), 2);
      expect(await adapter.reserve('mail'), isNull);
    });
  });
}
