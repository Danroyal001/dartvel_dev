// DV.Queues on Amazon SQS.
//
// SQS is not a queue in the shape the other adapters are. It has no priority,
// no dead-letter list this adapter owns, and no way to look at what is
// pending -- those are properties of the service, configured on the queue
// itself, and an adapter that pretended otherwise would be lying about
// durability rather than providing it.
//
// So this is mostly about what it refuses to claim, and about the one thing
// SQS does that the others do not: a reserved message is invisible for a
// visibility timeout and comes back on its own if nothing completes it.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/queues/sqs_queue.dart';
import 'package:test/test.dart';

/// A stand-in for the SQS HTTP API, recording what it was asked.
class FakeSqs implements DVSqsTransport {
  final List<({String action, Map<String, String> body})> calls =
      <({String action, Map<String, String> body})>[];
  final List<Map<String, Object?>> replies = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> call(
    String action,
    Map<String, String> body,
  ) async {
    calls.add((action: action, body: body));
    return replies.isEmpty ? <String, Object?>{} : replies.removeAt(0);
  }
}

class _Welcome {
  const _Welcome(this.userId);
  final String userId;
}

void main() {
  late FakeSqs sqs;
  late DVSqsQueueAdapter adapter;

  setUp(() {
    sqs = FakeSqs();
    adapter = DVSqsQueueAdapter(
      sqs,
      queueUrl: (String queue) => 'https://sqs.eu-west-1.amazonaws.com/1/$queue',
    );
    const DVJobPayloadCodecs().register(
      DVJobPayloadCodec<_Welcome>(
        name: 'welcome',
        encode: (_Welcome job) => <String, Object?>{'userId': job.userId},
        decode: (Map<String, Object?> json) =>
            _Welcome(json['userId']! as String),
      ),
    );
  });

  group('enqueue', () {
    test('it sends the message to the queue that was asked for', () async {
      await adapter.enqueue('mail', const _Welcome('u1'));

      expect(sqs.calls.single.action, 'SendMessage');
      expect(sqs.calls.single.body['QueueUrl'],
          'https://sqs.eu-west-1.amazonaws.com/1/mail');
    });

    test('the payload round-trips through its registered codec', () async {
      await adapter.enqueue('mail', const _Welcome('u1'));

      final String body = sqs.calls.single.body['MessageBody']!;
      expect(body, contains('welcome'));
      expect(body, contains('u1'));
    });

    test('an unregistered payload is refused rather than dropped', () async {
      // A payload with no codec cannot be decoded by the worker that picks it
      // up, so accepting it would enqueue something guaranteed to fail later
      // on a different machine.
      await expectLater(
        adapter.enqueue('mail', DateTime.now()),
        throwsStateError,
      );
    });

    test('a delay becomes DelaySeconds, which SQS understands', () async {
      await adapter.enqueue(
        'mail',
        const _Welcome('u1'),
        backoff: const Duration(seconds: 45),
      );

      expect(sqs.calls.single.body['DelaySeconds'], '45');
    });
  });

  group('reserve', () {
    test('nothing waiting is null rather than an error', () async {
      sqs.replies.add(<String, Object?>{});

      expect(await adapter.reserve('mail'), isNull);
    });

    test('a message comes back as an envelope carrying its receipt', () async {
      sqs.replies.add(<String, Object?>{
        'Messages': <Object?>[
          <String, Object?>{
            'MessageId': 'm-1',
            'ReceiptHandle': 'r-1',
            'Body': '{"type":"welcome","payload":{"userId":"u1"}}',
          },
        ],
      });

      final DVJobEnvelope<DVJobPayload>? job = await adapter.reserve('mail');

      expect(job, isNotNull);
      expect(job!.queue, 'mail');
      // The receipt, not the message id, is what deletes it later -- and SQS
      // issues a new one on every receive.
      expect(adapter.receiptFor(job.id), 'r-1');
    });
  });

  group('complete and fail', () {
    test('completing deletes the message with its receipt', () async {
      sqs.replies.add(<String, Object?>{
        'Messages': <Object?>[
          <String, Object?>{
            'MessageId': 'm-1',
            'ReceiptHandle': 'r-1',
            'Body': '{"type":"welcome","payload":{"userId":"u1"}}',
          },
        ],
      });
      final DVJobEnvelope<DVJobPayload> job = (await adapter.reserve('mail'))!;
      await adapter.complete(job.id);

      expect(sqs.calls.last.action, 'DeleteMessage');
      expect(sqs.calls.last.body['ReceiptHandle'], 'r-1');
    });

    test('failing releases it instead of deleting it', () async {
      // Setting the visibility timeout to zero hands it straight back. Doing
      // nothing would work too, eventually, but leaves the job invisible for
      // the whole timeout after a failure that already happened.
      sqs.replies.add(<String, Object?>{
        'Messages': <Object?>[
          <String, Object?>{
            'MessageId': 'm-1',
            'ReceiptHandle': 'r-1',
            'Body': '{"type":"welcome","payload":{"userId":"u1"}}',
          },
        ],
      });
      final DVJobEnvelope<DVJobPayload> job = (await adapter.reserve('mail'))!;
      await adapter.fail(job.id, 'boom', StackTrace.current);

      expect(sqs.calls.last.action, 'ChangeMessageVisibility');
      expect(sqs.calls.last.body['VisibilityTimeout'], '0');
    });

    test('completing something never reserved does nothing', () async {
      await adapter.complete('unknown');

      expect(sqs.calls, isEmpty);
    });
  });

  group('what it will not pretend to do', () {
    test('pending and dead letters are the service\'s, not ours', () async {
      // SQS has no way to list what is waiting, and a redrive policy on the
      // queue owns dead letters. Returning an empty list would read as "there
      // is nothing", which is a different claim from "I cannot see".
      await expectLater(adapter.pending('mail'), throwsUnsupportedError);
      await expectLater(adapter.deadLetters('mail'), throwsUnsupportedError);
      await expectLater(adapter.retry('m-1'), throwsUnsupportedError);
      await expectLater(adapter.discard('m-1'), throwsUnsupportedError);
    });

    test('priority is not silently accepted', () async {
      // SQS has no priority. Taking the argument and ignoring it would make
      // an ordering guarantee the service does not offer.
      await expectLater(
        adapter.enqueue('mail', const _Welcome('u1'), priority: 5),
        throwsUnsupportedError,
      );
    });

    test('flush purges, which SQS does support', () async {
      await adapter.flush('mail');

      expect(sqs.calls.single.action, 'PurgeQueue');
    });
  });
}
