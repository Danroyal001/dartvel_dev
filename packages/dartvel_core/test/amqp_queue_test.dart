// DV.Queues on RabbitMQ.
//
// Durability here is the broker's, and the adapter's job is to not undermine
// it: a durable queue holding transient messages looks durable and loses
// everything on a restart, which is the failure that only shows up the day it
// matters.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/queues/amqp_queue.dart';
import 'package:test/test.dart';

class FakeChannel implements DVAmqpChannel {
  final List<String> declared = <String>[];
  final List<({String queue, List<int> body, bool persistent, int priority})>
      published = <({String queue, List<int> body, bool persistent, int priority})>[];
  final List<({int tag, bool? requeue})> settled = <({int tag, bool? requeue})>[];
  final List<DVAmqpMessage?> waiting = <DVAmqpMessage?>[];
  int purged = 0;

  @override
  Future<void> declareQueue(String name, {required bool durable}) async {
    declared.add('$name:${durable ? 'durable' : 'transient'}');
  }

  @override
  Future<void> publish(String queue, List<int> body,
      {required bool persistent, int priority = 0}) async {
    published.add((queue: queue, body: body, persistent: persistent, priority: priority));
  }

  @override
  Future<DVAmqpMessage?> get(String queue) async =>
      waiting.isEmpty ? null : waiting.removeAt(0);

  @override
  Future<void> ack(int deliveryTag) async {
    settled.add((tag: deliveryTag, requeue: null));
  }

  @override
  Future<void> nack(int deliveryTag, {required bool requeue}) async {
    settled.add((tag: deliveryTag, requeue: requeue));
  }

  @override
  Future<int> purge(String queue) async => purged;
}

class _Welcome {
  const _Welcome(this.userId);
  final String userId;
}

DVAmqpMessage message(Map<String, Object?> json, {int tag = 1, bool redelivered = false}) =>
    DVAmqpMessage(
      deliveryTag: tag,
      body: utf8.encode(jsonEncode(json)),
      redelivered: redelivered,
    );

void main() {
  late FakeChannel channel;
  late DVAmqpQueueAdapter adapter;

  setUp(() {
    channel = FakeChannel();
    adapter = DVAmqpQueueAdapter(channel);
    const DVJobPayloadCodecs().register(
      DVJobPayloadCodec<_Welcome>(
        name: 'welcome',
        encode: (_Welcome job) => <String, Object?>{'userId': job.userId},
        decode: (Map<String, Object?> json) => _Welcome(json['userId']! as String),
      ),
    );
  });

  group('publishing', () {
    test('the queue is declared durable before anything is sent', () async {
      await adapter.enqueue('mail', const _Welcome('u1'));

      expect(channel.declared, contains('mail:durable'));
    });

    test('and the message is persistent', () async {
      // A durable queue full of transient messages survives a restart with
      // nothing in it. Both halves are needed and only one of them is
      // obvious.
      await adapter.enqueue('mail', const _Welcome('u1'));

      expect(channel.published.single.persistent, isTrue);
    });

    test('the queue is declared once, not on every publish', () async {
      await adapter.enqueue('mail', const _Welcome('u1'));
      await adapter.enqueue('mail', const _Welcome('u2'));

      expect(channel.declared.where((String d) => d.startsWith('mail:')),
          hasLength(1));
    });

    test('an unregistered payload is refused', () async {
      await expectLater(adapter.enqueue('mail', DateTime.now()),
          throwsStateError);
    });
  });

  group('reserving', () {
    test('nothing waiting is null', () async {
      expect(await adapter.reserve('mail'), isNull);
    });

    test('a delivery becomes an envelope holding its tag', () async {
      channel.waiting.add(message(<String, Object?>{
        'id': 'j-1',
        'type': 'welcome',
        'payload': <String, Object?>{'userId': 'u1'},
        'maxAttempts': 5,
      }, tag: 42));

      final DVJobEnvelope<DVJobPayload>? job = await adapter.reserve('mail');

      expect(job!.id, 'j-1');
      expect(job.maxAttempts, 5);
      expect(adapter.tagFor('j-1'), 42);
    });

    test('a redelivery is reported as an attempt already made', () async {
      channel.waiting.add(message(<String, Object?>{
        'id': 'j-1', 'type': 'welcome',
        'payload': <String, Object?>{'userId': 'u1'},
      }, redelivered: true));

      expect((await adapter.reserve('mail'))!.attempts, 1);
    });

    test('an unreadable message is dead-lettered, not requeued', () async {
      // Requeueing it hands the same broken message to the next worker, and
      // to the one after that, forever and at full speed.
      channel.waiting.add(DVAmqpMessage(deliveryTag: 7, body: utf8.encode('{')));

      expect(await adapter.reserve('mail'), isNull);
      expect(channel.settled.single, (tag: 7, requeue: false));
    });

    test('a payload this deployment cannot decode is requeued', () async {
      // Different from unreadable: the message is fine and another
      // deployment may have the codec, so throwing it away would lose work
      // that something else can do.
      channel.waiting.add(message(<String, Object?>{
        'id': 'j-1', 'type': 'not_registered', 'payload': <String, Object?>{},
      }, tag: 9));

      expect(await adapter.reserve('mail'), isNull);
      expect(channel.settled.single, (tag: 9, requeue: true));
    });
  });

  group('settling', () {
    Future<DVJobEnvelope<DVJobPayload>> reserved() async {
      channel.waiting.add(message(<String, Object?>{
        'id': 'j-1', 'type': 'welcome',
        'payload': <String, Object?>{'userId': 'u1'},
      }, tag: 3));
      return (await adapter.reserve('mail'))!;
    }

    test('completing acknowledges the delivery', () async {
      await adapter.complete((await reserved()).id);

      expect(channel.settled.last, (tag: 3, requeue: null));
    });

    test('failing dead-letters rather than requeueing', () async {
      // RabbitMQ keeps no attempt count, so requeueing a job that always
      // fails is an infinite loop at full speed.
      await adapter.fail((await reserved()).id, 'boom', StackTrace.current);

      expect(channel.settled.last, (tag: 3, requeue: false));
    });

    test('settling something never reserved does nothing', () async {
      await adapter.complete('unknown');

      expect(channel.settled, isEmpty);
    });
  });

  group('what it will not pretend to do', () {
    test('reading a queue means consuming it, so pending is refused', () async {
      await expectLater(adapter.pending('mail'), throwsUnsupportedError);
      await expectLater(adapter.retry('j-1'), throwsUnsupportedError);
      await expectLater(adapter.discard('j-1'), throwsUnsupportedError);
    });

    test('the dead-letter queue is named, not hidden', () {
      expect(adapter.deadLetterQueue('mail'), 'mail.dead');
    });

    test('flush purges and reports what went', () async {
      channel.purged = 4;

      expect(await adapter.flush('mail'), 4);
    });
  });
}
