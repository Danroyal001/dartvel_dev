@Tags(<String>['live'])
library;

// The Kafka adapter against a real broker.
//
// The unit tests drive a fake log, which proves the adapter's semantics and
// nothing about the wire format -- and this client hand-writes a v2 record
// batch, including its CRC-32C, which is exactly where a hand-written protocol
// goes wrong. Every live broker on this project has found a bug the fake
// agreed with.
import 'dart:io' as io show Platform;

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/queues/kafka_queue.dart';
import 'package:dartvel_core/src/queues/kafka_socket_io.dart';
import 'package:test/test.dart';

class LiveKafkaJob {
  const LiveKafkaJob(this.note);
  final String note;
}

void main() {
  final String? host = io.Platform.environment['DARTVEL_KAFKA_HOST'];
  if (host == null || host.isEmpty) {
    test('skipped: DARTVEL_KAFKA_HOST is not set', () {}, skip: true);
    return;
  }
  final int port =
      int.tryParse(io.Platform.environment['DARTVEL_KAFKA_PORT'] ?? '') ?? 9092;

  late DVKafkaSocketClient client;
  late DVKafkaQueueAdapter adapter;
  final String queue = 'live${DateTime.now().millisecondsSinceEpoch}';

  setUpAll(() async {
    client = await DVKafkaSocketClient.connect(
      host: host,
      port: port,
      group: 'dartvel-live-$queue',
    );
    adapter = DVKafkaQueueAdapter(client);
    // Metadata creates the topic where the broker auto-creates, and gives it
    // a moment to become writable.
    await client.ensureTopic(adapter.topicFor(queue));
    await Future<void>.delayed(const Duration(seconds: 2));

    const DVJobPayloadCodecs().register(
      DVJobPayloadCodec<LiveKafkaJob>(
        name: 'live_kafka_job',
        encode: (LiveKafkaJob job) => <String, Object?>{'note': job.note},
        decode: (Map<String, Object?> json) =>
            LiveKafkaJob(json['note']! as String),
      ),
    );
  });

  tearDownAll(() async {
    await client.close();
  });

  test('a produced record is accepted, batch and checksum and all', () async {
    // The broker validates the record batch's CRC-32C. A wrong checksum, a
    // wrong length, or a varint written the wrong way is rejected here rather
    // than silently stored.
    final DVJobEnvelope<LiveKafkaJob> job =
        await adapter.enqueue(queue, const LiveKafkaJob('hello'));

    expect(job.id, endsWith('@0'), reason: 'the first record is at offset 0');
  });

  test('the broker agrees the record is there', () async {
    // Printed rather than inferred. Two runs were spent guessing why a fetch
    // came back empty; whether the log actually holds the record separates a
    // produce that lied from a fetch that cannot read it.
    final int end = await client.endOffset(adapter.topicFor(queue));
    final int at = await client.committed(adapter.topicFor(queue));
    // ignore: avoid_print
    print('kafka: endOffset=$end committed=$at');

    expect(end, greaterThan(0), reason: 'the produce claimed offset 0');
  });

  test('it reads back with the type that routes it', () async {
    final DVJobEnvelope<DVJobPayload>? read = await adapter.reserve(queue);

    expect(read, isNotNull, reason: 'it was produced, so it must be readable');
    expect(read!.payloadType, LiveKafkaJob);
  });

  test('completing moves the committed offset past it', () async {
    final DVJobEnvelope<DVJobPayload> job = (await adapter.reserve(queue))!;
    await adapter.complete(job.id);

    expect(await adapter.reserve(queue), isNull,
        reason: 'the offset is past the only record');
  });

  test('lag is the distance to the end of the log', () async {
    expect(await adapter.lag(queue), 0);

    await adapter.enqueue(queue, const LiveKafkaJob('a'));
    await adapter.enqueue(queue, const LiveKafkaJob('b'));

    expect(await adapter.lag(queue), 2);
  });
}
