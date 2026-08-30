@Tags(<String>['live'])
library;

// The SQS adapter against a server that implements the SQS API.
//
// The unit tests drive a fake that returns what the protocol says it should.
// That proves the adapter speaks the protocol it was written against and
// nothing about whether a server agrees — a fake that shares the author's
// misunderstanding passes every time. ElasticMQ enforces the real rules.
//
// Skipped unless DARTVEL_SQS_ENDPOINT is set, so a developer without a broker
// still gets a green suite rather than a failure they cannot act on.
import 'dart:convert';
import 'dart:io';
import 'dart:io' as io show Platform;

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/queues/sqs_queue.dart';
import 'package:test/test.dart';

/// The SQS query API over plain HTTP, which is what ElasticMQ speaks.
class HttpSqsTransport implements DVSqsTransport {
  HttpSqsTransport(this.endpoint);

  final String endpoint;
  final HttpClient _client = HttpClient();

  /// The queue the last addressed request went to.
  ///
  /// DeleteMessage and ChangeMessageVisibility carry a receipt and no queue,
  /// but the query API still addresses them to the queue's URL.
  String? _lastQueue;

  @override
  Future<Map<String, Object?>> call(
    String action,
    Map<String, String> body,
  ) async {
    final Map<String, String> form = <String, String>{
      'Action': action,
      'Version': '2012-11-05',
      ...body,
    };
    _lastQueue = form['QueueUrl'] ?? _lastQueue;
    // The SQS query API is addressed by queue URL: the request goes *to* the
    // queue, and QueueUrl is not a parameter. Posting everything at the root
    // with QueueUrl in the body is the JSON protocol, and against a real
    // server it silently addressed the wrong thing -- every receive came back
    // empty and looked like a message that had not arrived.
    final String? queueUrl = form.remove('QueueUrl');
    final HttpClientRequest request =
        await _client.postUrl(Uri.parse(queueUrl ?? _lastQueue ?? endpoint));
    request.headers.contentType =
        ContentType('application', 'x-www-form-urlencoded');
    request.write(form.entries
        .map((MapEntry<String, String> e) =>
            '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent(e.value)}')
        .join('&'));
    final HttpClientResponse response = await request.close();
    final String text = await response.transform(utf8.decoder).join();
    // Logged, not guessed at. Two runs were spent inferring why a receive came
    // back empty; the server was saying so all along and nothing printed it.
    // ignore: avoid_print
    print('SQS $action -> ${response.statusCode} '
        '${text.replaceAll(RegExp(r'\s+'), ' ').trim()}');
    if (response.statusCode >= 400) {
      throw StateError('SQS $action failed ${response.statusCode}: $text');
    }
    return _parse(action, text);
  }

  /// Enough of the XML response to drive the adapter.
  ///
  /// A full XML parser is a dependency this package does not need for four
  /// element names, and the responses here are machine-generated and flat.
  Map<String, Object?> _parse(String action, String xml) {
    /// The text of one element, with XML entities turned back into
    /// characters.
    ///
    /// The message body is JSON and arrives escaped -- `&quot;` for every
    /// quote in it. Handing that to jsonDecode throws, the adapter catches it
    /// and returns null, and the whole thing reads as a message that never
    /// arrived. It took a log of the raw response to see that the server had
    /// been returning the message all along.
    String? tag(String name, [String source = '']) {
      final RegExpMatch? m = RegExp('<$name>(.*?)</$name>', dotAll: true)
          .firstMatch(source.isEmpty ? xml : source);
      final String? value = m?.group(1);
      return value
          ?.replaceAll('&quot;', '"')
          .replaceAll('&apos;', "'")
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          // Ampersand last, or an escaped entity is unescaped twice.
          .replaceAll('&amp;', '&');
    }

    if (action == 'ReceiveMessage') {
      final Iterable<RegExpMatch> messages =
          RegExp('<Message>(.*?)</Message>', dotAll: true).allMatches(xml);
      return <String, Object?>{
        'Messages': <Object?>[
          for (final RegExpMatch m in messages)
            <String, Object?>{
              'MessageId': tag('MessageId', m.group(1)!),
              'ReceiptHandle': tag('ReceiptHandle', m.group(1)!),
              'Body': tag('Body', m.group(1)!),
            },
        ],
      };
    }
    if (action == 'CreateQueue') {
      return <String, Object?>{'QueueUrl': tag('QueueUrl')};
    }
    return <String, Object?>{};
  }
}

class LiveWelcome {
  const LiveWelcome(this.userId);
  final String userId;
}

void main() {
  final String? endpoint = io.Platform.environment['DARTVEL_SQS_ENDPOINT'];
  if (endpoint == null || endpoint.isEmpty) {
    // Nothing to talk to. Said out loud rather than passing silently, so a
    // green run cannot be mistaken for a verified one.
    test('skipped: DARTVEL_SQS_ENDPOINT is not set', () {}, skip: true);
    return;
  }

  late HttpSqsTransport transport;
  late DVSqsQueueAdapter adapter;
  final String queue = 'dartvel-live-${DateTime.now().millisecondsSinceEpoch}';

  setUpAll(() async {
    transport = HttpSqsTransport(endpoint);
    // The URL the server gives back, not one this test builds. ElasticMQ and
    // SQS itself have changed that path shape more than once, and guessing it
    // addresses a queue that does not exist -- which reads as an empty queue
    // rather than as a wrong address.
    final Map<String, Object?> created =
        await transport.call('CreateQueue', <String, String>{
      'QueueName': queue,
    });
    final String url = '${created['QueueUrl'] ?? '$endpoint/queue/$queue'}';
    adapter = DVSqsQueueAdapter(
      transport,
      queueUrl: (String name) => url,
      // Long polling would make every empty read wait; this suite reads
      // straight after writing.
      waitTimeSeconds: 1,
    );
    const DVJobPayloadCodecs().register(
      DVJobPayloadCodec<LiveWelcome>(
        name: 'live_welcome',
        encode: (LiveWelcome job) => <String, Object?>{'userId': job.userId},
        decode: (Map<String, Object?> json) =>
            LiveWelcome(json['userId']! as String),
      ),
    );
  });

  test('a job survives the round trip through a real queue', () async {
    await adapter.enqueue(queue, const LiveWelcome('u-live'));

    final DVJobEnvelope<DVJobPayload>? job = await adapter.reserve(queue);

    expect(job, isNotNull, reason: 'the message was sent, so it must come back');
    // By type, not by cast: a decoded payload is wrapped, and payloadType is
    // what routes it to a handler.
    expect(job!.payloadType, LiveWelcome);
  });

  test('completing it removes it, so it is not delivered twice', () async {
    await adapter.enqueue(queue, const LiveWelcome('u-once'));
    final DVJobEnvelope<DVJobPayload> job = (await adapter.reserve(queue))!;
    await adapter.complete(job.id);

    // The visibility timeout would hide it briefly either way, so this is
    // read after it would have returned had the delete not landed.
    await Future<void>.delayed(const Duration(seconds: 2));
    final DVJobEnvelope<DVJobPayload>? again = await adapter.reserve(queue);

    expect(again, isNull, reason: 'a completed job must not come back');
  });

  test('failing hands it back after its backoff, not before', () async {
    // A short backoff on purpose. The first version of this read straight
    // after failing and got nothing, which is the adapter working: a failed
    // job is hidden for its backoff, and the default is thirty seconds.
    await adapter.enqueue(
      queue,
      const LiveWelcome('u-retry'),
      backoff: const Duration(seconds: 1),
    );
    final DVJobEnvelope<DVJobPayload> job = (await adapter.reserve(queue))!;
    await adapter.fail(job.id, 'boom', StackTrace.current);

    expect(await adapter.reserve(queue), isNull,
        reason: 'it is still inside its backoff');

    await Future<void>.delayed(const Duration(seconds: 3));

    expect(await adapter.reserve(queue), isNotNull,
        reason: 'a failed job must come back once its backoff has passed');
  });
}
