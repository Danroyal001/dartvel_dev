@Tags(<String>['live'])
library;

// The Pub/Sub adapter against Google's emulator.
//
// The unit tests drive a fake. That proves the adapter calls the right paths
// with the right bodies and nothing about whether the service agrees -- and on
// this project every live broker run so far has found a bug the fake had
// happily confirmed.
import 'dart:convert';
import 'dart:io';
import 'dart:io' as io show Platform;

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/queues/pubsub_queue.dart';
import 'package:test/test.dart';

/// The Pub/Sub REST API over plain HTTP, which is what the emulator speaks.
class HttpPubSubTransport implements DVPubSubTransport {
  HttpPubSubTransport(this.endpoint);

  final String endpoint;
  final HttpClient _client = HttpClient();

  @override
  Future<Map<String, Object?>> post(
    String path,
    Map<String, Object?> body,
  ) async {
    final HttpClientRequest request =
        await _client.postUrl(Uri.parse('$endpoint/v1/$path'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final HttpClientResponse response = await request.close();
    final String text = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      throw StateError('Pub/Sub $path failed ${response.statusCode}: $text');
    }
    if (text.trim().isEmpty) return <String, Object?>{};
    final Object? decoded = jsonDecode(text);
    return decoded is Map
        ? decoded.cast<String, Object?>()
        : <String, Object?>{};
  }

  /// The emulator starts empty, so the topic and subscription have to exist
  /// before anything is published to them.
  Future<void> ensure(String project, String topic, String subscription) async {
    Future<void> put(String path, Map<String, Object?> body) async {
      final HttpClientRequest request =
          await _client.putUrl(Uri.parse('$endpoint/v1/$path'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final HttpClientResponse response = await request.close();
      await response.drain<void>();
    }

    await put('projects/$project/topics/$topic', <String, Object?>{});
    await put('projects/$project/subscriptions/$subscription',
        <String, Object?>{
          'topic': 'projects/$project/topics/$topic',
          'ackDeadlineSeconds': 10,
        });
  }
}

class LivePing {
  const LivePing(this.note);
  final String note;
}

void main() {
  final String? endpoint = io.Platform.environment['DARTVEL_PUBSUB_ENDPOINT'];
  if (endpoint == null || endpoint.isEmpty) {
    test('skipped: DARTVEL_PUBSUB_ENDPOINT is not set', () {}, skip: true);
    return;
  }

  const String project = 'dartvel-live';
  final String queue = 'q${DateTime.now().millisecondsSinceEpoch}';
  late HttpPubSubTransport transport;
  late DVPubSubQueueAdapter adapter;

  setUpAll(() async {
    transport = HttpPubSubTransport(endpoint);
    await transport.ensure(project, queue, '$queue-sub');
    adapter = DVPubSubQueueAdapter(transport, project: project);
    const DVJobPayloadCodecs().register(
      DVJobPayloadCodec<LivePing>(
        name: 'live_ping',
        encode: (LivePing job) => <String, Object?>{'note': job.note},
        decode: (Map<String, Object?> json) =>
            LivePing(json['note']! as String),
      ),
    );
  });

  test('a published job comes back from the subscription', () async {
    await adapter.enqueue(queue, const LivePing('hello'));

    final DVJobEnvelope<DVJobPayload>? job = await adapter.reserve(queue);

    expect(job, isNotNull, reason: 'it was published, so it must pull back');
    expect(job!.payloadType, LivePing);

    // Acknowledged before leaving. An unacknowledged message returns once the
    // ack deadline passes, and it then turns up in the next test as a job
    // that was supposed to have been deleted -- which reads as a broken
    // acknowledgement rather than as a leak from here.
    await adapter.complete(job.id);
  });

  test('acknowledging it means it is not delivered again', () async {
    await adapter.enqueue(queue, const LivePing('once'));
    final DVJobEnvelope<DVJobPayload> job = (await adapter.reserve(queue))!;
    await adapter.complete(job.id);

    // Past the ack deadline the subscription was created with, so a message
    // that had not been acknowledged would certainly have returned by now.
    await Future<void>.delayed(const Duration(seconds: 12));

    expect(await adapter.reserve(queue), isNull,
        reason: 'an acknowledged message is gone');
  });
}
