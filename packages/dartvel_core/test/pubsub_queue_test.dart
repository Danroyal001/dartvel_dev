// DV.Queues on Pub/Sub.
//
// Pub/Sub separates what you publish to from what you read from: a topic fans
// out to every subscription on it. A Dartvel queue is one topic and one
// subscription, because a queue that fanned out would run every job once per
// subscriber -- which looks like duplicate work rather than like a
// misconfiguration.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/queues/pubsub_queue.dart';
import 'package:test/test.dart';

class FakePubSub implements DVPubSubTransport {
  final List<({String path, Map<String, Object?> body})> calls =
      <({String path, Map<String, Object?> body})>[];
  final List<Map<String, Object?>> replies = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> post(
    String path,
    Map<String, Object?> body,
  ) async {
    calls.add((path: path, body: body));
    return replies.isEmpty ? <String, Object?>{} : replies.removeAt(0);
  }
}

class _Ping {
  const _Ping(this.note);
  final String note;
}

Map<String, Object?> delivery(Map<String, Object?> payload,
        {String ackId = 'a-1', String id = 'm-1'}) =>
    <String, Object?>{
      'receivedMessages': <Object?>[
        <String, Object?>{
          'ackId': ackId,
          'message': <String, Object?>{
            'messageId': id,
            'data': base64Encode(utf8.encode(jsonEncode(payload))),
          },
        },
      ],
    };

void main() {
  late FakePubSub pubsub;
  late DVPubSubQueueAdapter adapter;

  setUp(() {
    pubsub = FakePubSub();
    adapter = DVPubSubQueueAdapter(pubsub, project: 'demo');
    const DVJobPayloadCodecs().register(
      DVJobPayloadCodec<_Ping>(
        name: 'ping',
        encode: (_Ping job) => <String, Object?>{'note': job.note},
        decode: (Map<String, Object?> json) => _Ping(json['note']! as String),
      ),
    );
  });

  group('naming', () {
    test('a queue is one topic and one subscription', () {
      // Not two queues sharing a topic: a second subscription would deliver
      // every job again.
      expect(adapter.topicPath('mail'), 'projects/demo/topics/mail');
      expect(adapter.subscriptionPath('mail'),
          'projects/demo/subscriptions/mail-sub');
    });
  });

  group('publishing', () {
    test('it publishes to the topic, base64 encoded', () async {
      await adapter.enqueue('mail', const _Ping('hello'));

      expect(pubsub.calls.single.path, 'projects/demo/topics/mail:publish');
      final List<Object?> messages =
          pubsub.calls.single.body['messages']! as List<Object?>;
      final String data =
          (messages.single as Map<String, Object?>)['data']! as String;
      expect(utf8.decode(base64Decode(data)), contains('ping'));
    });

    test('an unregistered payload is refused', () async {
      await expectLater(
          adapter.enqueue('mail', DateTime.now()), throwsStateError);
    });

    test('priority is refused rather than ignored', () async {
      await expectLater(
        adapter.enqueue('mail', const _Ping('x'), priority: 3),
        throwsUnsupportedError,
      );
    });
  });

  group('pulling', () {
    test('nothing waiting is null', () async {
      pubsub.replies.add(<String, Object?>{});

      expect(await adapter.reserve('mail'), isNull);
    });

    test('a delivery carries its ack id and the registered type', () async {
      pubsub.replies.add(delivery(<String, Object?>{
        'type': 'ping',
        'payload': <String, Object?>{'note': 'hello'},
      }));

      final DVJobEnvelope<DVJobPayload>? job = await adapter.reserve('mail');

      expect(job!.id, 'm-1');
      // The registered type, not the wrapper's: handlers are routed by this.
      expect(job.payloadType, _Ping);
      expect(adapter.ackIdFor('m-1'), 'a-1');
    });

    test('an unreadable message is acknowledged, not redelivered', () async {
      // Redelivering hands the same broken message back forever.
      pubsub.replies.add(<String, Object?>{
        'receivedMessages': <Object?>[
          <String, Object?>{
            'ackId': 'a-2',
            'message': <String, Object?>{
              'messageId': 'm-2',
              'data': base64Encode(utf8.encode('{')),
            },
          },
        ],
      });

      expect(await adapter.reserve('mail'), isNull);
      expect(pubsub.calls.last.path,
          'projects/demo/subscriptions/mail-sub:acknowledge');
    });

    test('a payload with no codec here is released, not dropped', () async {
      pubsub.replies.add(delivery(<String, Object?>{
        'type': 'not_registered',
        'payload': <String, Object?>{},
      }));

      expect(await adapter.reserve('mail'), isNull);
      expect(pubsub.calls.last.path,
          'projects/demo/subscriptions/mail-sub:modifyAckDeadline');
    });
  });

  group('settling', () {
    Future<DVJobEnvelope<DVJobPayload>> reserved() async {
      await adapter.enqueue('mail', const _Ping('hello'));
      pubsub.replies.add(delivery(<String, Object?>{
        'type': 'ping',
        'payload': <String, Object?>{'note': 'hello'},
      }));
      return (await adapter.reserve('mail'))!;
    }

    test('completing acknowledges it', () async {
      await adapter.complete((await reserved()).id);

      expect(pubsub.calls.last.path,
          'projects/demo/subscriptions/mail-sub:acknowledge');
    });

    test('failing extends the deadline by the backoff', () async {
      // Not zero: retrying a failing job immediately is a hot loop. The ack
      // deadline is when it comes back, so the backoff belongs there.
      await adapter.fail((await reserved()).id, 'boom', StackTrace.current);

      expect(pubsub.calls.last.body['ackDeadlineSeconds'], 30);
    });

    test('settling something never pulled does nothing', () async {
      await adapter.complete('unknown');

      expect(pubsub.calls, isEmpty);
    });
  });

  group('what it will not pretend to do', () {
    test('a backlog cannot be read without consuming it', () async {
      await expectLater(adapter.pending('mail'), throwsUnsupportedError);
      await expectLater(adapter.deadLetters('mail'), throwsUnsupportedError);
      await expectLater(adapter.retry('m-1'), throwsUnsupportedError);
      await expectLater(adapter.discard('m-1'), throwsUnsupportedError);
    });

    test('flush seeks to now and claims no count', () async {
      // Pub/Sub reports no number here, and inventing one would be a figure
      // nobody could act on.
      expect(await adapter.flush('mail'), 0);
      expect(pubsub.calls.single.path,
          'projects/demo/subscriptions/mail-sub:seek');
    });
  });
}
