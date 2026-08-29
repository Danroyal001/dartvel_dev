@Tags(<String>['live'])
library;

// The AMQP adapter against a real RabbitMQ.
//
// The unit tests drive a fake channel. That proves the adapter calls the right
// operations in the right order; it proves nothing about whether the bytes on
// the wire are the ones RabbitMQ expects, and a hand-written binary protocol
// is exactly where that goes wrong. The SQS adapter's first live run found a
// bug the fake had happily agreed with.
//
// Skipped unless DARTVEL_AMQP_HOST is set, so a developer without a broker
// gets a green suite rather than a failure they cannot act on.
import 'dart:io' as io show Platform;

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/queues/amqp_queue.dart';
import 'package:dartvel_core/src/queues/amqp_socket_io.dart';
import 'package:test/test.dart';

class LiveJob {
  const LiveJob(this.note);
  final String note;
}

void main() {
  final String? host = io.Platform.environment['DARTVEL_AMQP_HOST'];
  if (host == null || host.isEmpty) {
    test('skipped: DARTVEL_AMQP_HOST is not set', () {}, skip: true);
    return;
  }
  final int port =
      int.tryParse(io.Platform.environment['DARTVEL_AMQP_PORT'] ?? '') ?? 5672;

  late DVAmqpSocketChannel channel;
  late DVAmqpQueueAdapter adapter;
  final String queue = 'dartvel-live-${DateTime.now().millisecondsSinceEpoch}';

  setUpAll(() async {
    channel = await DVAmqpSocketChannel.connect(host: host, port: port);
    adapter = DVAmqpQueueAdapter(channel);
    const DVJobPayloadCodecs().register(
      DVJobPayloadCodec<LiveJob>(
        name: 'live_job',
        encode: (LiveJob job) => <String, Object?>{'note': job.note},
        decode: (Map<String, Object?> json) => LiveJob(json['note']! as String),
      ),
    );
  });

  tearDownAll(() async {
    await channel.close();
  });

  test('the handshake completes, which is most of the protocol', () async {
    // Reaching here at all means the eight-byte header, PLAIN authentication,
    // the tune exchange, the vhost open and the channel open were all
    // accepted. Any one of them wrong is a closed connection, not a bad
    // answer.
    await adapter.flush(queue);
  });

  test('a job published persistently comes back', () async {
    await adapter.enqueue(queue, const LiveJob('hello'));

    final DVJobEnvelope<DVJobPayload>? job = await adapter.reserve(queue);

    expect(job, isNotNull, reason: 'it was published, so it must be gettable');
    expect((job!.payload as LiveJob).note, 'hello');
  });

  test('acknowledging it means it is not delivered again', () async {
    await adapter.enqueue(queue, const LiveJob('once'));
    final DVJobEnvelope<DVJobPayload> job = (await adapter.reserve(queue))!;
    await adapter.complete(job.id);

    expect(await adapter.reserve(queue), isNull,
        reason: 'an acknowledged message is gone from the broker');
  });

  test('purging empties the queue and says how many went', () async {
    await adapter.enqueue(queue, const LiveJob('a'));
    await adapter.enqueue(queue, const LiveJob('b'));

    expect(await adapter.flush(queue), 2);
    expect(await adapter.reserve(queue), isNull);
  });
}
