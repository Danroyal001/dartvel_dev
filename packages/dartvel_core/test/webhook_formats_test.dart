// What a delivery looks like on the wire under each dartvel.webhooks setting:
// Dartvel's envelope and signature (the default, unchanged), CloudEvents in
// either content mode, and Standard Webhooks signatures.
//
// The failures worth the effort are the quiet ones: a default that changed
// under existing subscribers, a signature over a body other than the one
// sent, a CloudEvent whose id differs from the delivery id a consumer
// deduplicates on, and a misconfigured key that sends a delivery unsigned.
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _Wire {
  final List<DVHttpRequest> requests = <DVHttpRequest>[];

  Future<DVHttpStreamedResponse> send(DVHttpRequest request) async {
    requests.add(request);
    return DVHttpStreamedResponse(
      statusCode: 200,
      headers: const <String, String>{},
      body: Stream<List<int>>.value(const <int>[]),
    );
  }
}

// 32 random-looking bytes, as a Standard Webhooks key is handed out.
final String _whsec = 'whsec_${base64.encode(List<int>.generate(32, (int i) => i * 7 + 3))}';

Matcher _refused(String why) => throwsA(isA<DVWebhooksConfigException>()
    .having((DVWebhooksConfigException e) => e.code, 'code', 'DV-WEBHOOK-009')
    .having((DVWebhooksConfigException e) => e.message, 'message',
        contains(why)));

void main() {
  late DateTime now;
  late _Wire wire;

  setUp(() {
    DVHttp.reset();
    DVWebhooks.reset();
    const DVQueues().useAdapter(DVInMemoryQueueAdapter());
    const DVDatabase().configure(MemoryDVDatabaseAdapter());
    DVSecrets.reset();
    DVSecrets.configure(<String, String>{
      'PLAIN_KEY': 'plain-dartvel-key',
      'STANDARD_KEY': _whsec,
      'STANDARD_KEY_NEXT': 'whsec_${base64.encode(List<int>.filled(24, 9))}',
    });
    now = DateTime.utc(2026, 9, 26, 12);
    DVWebhooks.clock = () => now;
    DVWebhooks.resolveHost = (String host) async => <String>['93.184.216.34'];
    wire = _Wire();
    DVHttp.transport = wire.send;
    const DVWebhooks().declare(const DVWebhookEvent('order.paid'));
  });

  tearDown(() {
    DVHttp.reset();
    DVWebhooks.reset();
    const DVDatabase().unconfigure();
    DVSecrets.reset();
  });

  Future<(DVWebhookDelivery, DVHttpRequest)> deliver(
      {String key = 'PLAIN_KEY'}) async {
    await const DVWebhooks().subscribe(
      url: 'https://hooks.acme.test/in',
      events: <String>{'order.paid'},
      signingSecret: key,
    );
    final List<DVWebhookDelivery> sent = await const DVWebhooks()
        .emit('order.paid', <String, Object?>{'orderId': 'o-42'});
    await const DVWebhooks().drainAll();
    return (sent.single, wire.requests.last);
  }

  Map<String, String> headersOf(DVHttpRequest request) => <String, String>{
        for (final MapEntry<String, String> e in request.headers.entries)
          e.key.toLowerCase(): e.value,
      };

  group('the default is what existing subscribers already receive', () {
    test('Dartvel\'s envelope, its four headers and no others', () async {
      final (DVWebhookDelivery delivery, DVHttpRequest request) =
          await deliver();
      final Map<String, String> headers = headersOf(request);
      expect(headers['content-type'], 'application/json; charset=utf-8');
      expect(headers['dartvel-webhook-id'], delivery.id);
      expect(headers['dartvel-webhook-event'], 'order.paid');
      expect(headers.keys.where((String k) =>
          k.startsWith('ce-') || k.startsWith('webhook-')), isEmpty);
      final String body = utf8.decode(request.body);
      expect(jsonDecode(body), <String, Object?>{
        'id': delivery.id,
        'event': 'order.paid',
        'created': '2026-09-26T12:00:00.000Z',
        'data': <String, Object?>{'orderId': 'o-42'},
      });
      expect(
        DVWebhookSignature.verify(
          secret: 'plain-dartvel-key',
          timestamp: headers['dartvel-webhook-timestamp']!,
          body: body,
          header: headers['dartvel-webhook-signature']!,
        ),
        isTrue,
      );
    });
  });

  group('format: cloudevents', () {
    test('structured by default: one application/cloudevents+json body whose '
        'id is the delivery id, signed as sent', () async {
      DVWebhooks.config = DVWebhooksConfig.read(
          <String, Object?>{'format': 'cloudevents'},
          application: 'shop');
      final (DVWebhookDelivery delivery, DVHttpRequest request) =
          await deliver();
      final Map<String, String> headers = headersOf(request);
      final String body = utf8.decode(request.body);
      expect(headers['content-type'],
          'application/cloudevents+json; charset=utf-8');
      expect(jsonDecode(body), <String, Object?>{
        'specversion': '1.0',
        'id': delivery.id,
        'source': '/shop',
        'type': 'order.paid',
        'time': '2026-09-26T12:00:00.000Z',
        'datacontenttype': 'application/json',
        'data': <String, Object?>{'orderId': 'o-42'},
      });
      final DVCloudEvent event =
          DVCloudEvent.fromHttp(headers: headers, body: body);
      expect(event.id, delivery.id);
      expect(
        DVWebhookSignature.verify(
          secret: 'plain-dartvel-key',
          timestamp: headers['dartvel-webhook-timestamp']!,
          body: body,
          header: headers['dartvel-webhook-signature']!,
        ),
        isTrue,
        reason: 'the signature covers the CloudEvent that was sent',
      );
    });

    test('binary: ce- headers and the data alone as the body', () async {
      DVWebhooks.config = DVWebhooksConfig.read(<String, Object?>{
        'format': 'cloudevents',
        'mode': 'binary',
        'source': 'https://shop.example.com',
      }, application: 'shop');
      final (DVWebhookDelivery delivery, DVHttpRequest request) =
          await deliver();
      final Map<String, String> headers = headersOf(request);
      final String body = utf8.decode(request.body);
      expect(headers['ce-specversion'], '1.0');
      expect(headers['ce-id'], delivery.id);
      expect(headers['ce-source'], 'https://shop.example.com');
      expect(headers['ce-type'], 'order.paid');
      expect(headers['ce-time'], '2026-09-26T12:00:00.000Z');
      expect(headers['content-type'], 'application/json; charset=utf-8');
      expect(jsonDecode(body), <String, Object?>{'orderId': 'o-42'});
      final DVCloudEvent event =
          DVCloudEvent.fromHttp(headers: headers, body: body);
      expect(event.data, <String, Object?>{'orderId': 'o-42'});
    });

    test('a replay is the same CloudEvent id, so a consumer deduplicates it',
        () async {
      DVWebhooks.config = DVWebhooksConfig.read(
          <String, Object?>{'format': 'cloudevents'},
          application: 'shop');
      final (DVWebhookDelivery delivery, DVHttpRequest first) = await deliver();
      await const DVWebhooks().replay(delivery.id);
      await const DVWebhooks().drainAll();
      final DVHttpRequest again = wire.requests.last;
      expect(again, isNot(same(first)));
      expect(
        (jsonDecode(utf8.decode(again.body)) as Map<String, Object?>)['id'],
        delivery.id,
      );
    });
  });

  group('signature: standard', () {
    test('webhook-id, webhook-timestamp and webhook-signature, verifiable '
        'with the key as a customer holds it', () async {
      DVWebhooks.config = DVWebhooksConfig.read(
          <String, Object?>{'signature': 'standard'},
          application: 'shop');
      final (DVWebhookDelivery delivery, DVHttpRequest request) =
          await deliver(key: 'STANDARD_KEY');
      final Map<String, String> headers = headersOf(request);
      final String body = utf8.decode(request.body);
      expect(headers['webhook-id'], delivery.id);
      expect(headers['webhook-timestamp'], '${now.millisecondsSinceEpoch ~/ 1000}');
      expect(headers.keys.where((String k) => k.startsWith('dartvel-webhook-') &&
          k != 'dartvel-webhook-event'), isEmpty);

      // Recomputed the way the official libraries do, not through the class
      // under test.
      final String expected = base64.encode(Hmac(
              sha256, base64.decode(_whsec.substring('whsec_'.length)))
          .convert(utf8.encode(
              '${delivery.id}.${headers['webhook-timestamp']}.$body'))
          .bytes);
      expect(headers['webhook-signature'], 'v1,$expected');
      expect(
        DVStandardWebhookSignature.verify(
            secret: _whsec, headers: headers, body: body, now: now),
        isTrue,
      );
    });

    test('with CloudEvents binary, webhook-id is ce-id, so the signed id '
        'names the event', () async {
      DVWebhooks.config = DVWebhooksConfig.read(<String, Object?>{
        'format': 'cloudevents',
        'mode': 'binary',
        'signature': 'standard',
      }, application: 'shop');
      final (_, DVHttpRequest request) = await deliver(key: 'STANDARD_KEY');
      final Map<String, String> headers = headersOf(request);
      expect(headers['webhook-id'], headers['ce-id']);
      expect(
        DVStandardWebhookSignature.verify(
          secret: _whsec,
          headers: headers,
          body: utf8.decode(request.body),
          now: now,
        ),
        isTrue,
      );
    });

    test('a rotation overlap sends both keys\' signatures, space-delimited',
        () async {
      DVWebhooks.config = DVWebhooksConfig.read(
          <String, Object?>{'signature': 'standard'},
          application: 'shop');
      final DVWebhookSubscription s = await const DVWebhooks().subscribe(
        url: 'https://hooks.acme.test/in',
        events: <String>{'order.paid'},
        signingSecret: 'STANDARD_KEY',
      );
      await const DVWebhooks().rotateSigningKey(s.id, 'STANDARD_KEY_NEXT',
          overlap: const Duration(hours: 1));
      await const DVWebhooks()
          .emit('order.paid', <String, Object?>{'orderId': 'o-1'});
      await const DVWebhooks().drainAll();
      final Map<String, String> headers = headersOf(wire.requests.single);
      final String body = utf8.decode(wire.requests.single.body);
      expect(headers['webhook-signature']!.split(' '), hasLength(2));
      for (final String key in <String>[
        _whsec,
        const DVSecrets().get('STANDARD_KEY_NEXT'),
      ]) {
        expect(
          DVStandardWebhookSignature.verify(
              secret: key, headers: headers, body: body, now: now),
          isTrue,
        );
      }
    });

    test('a key that is not a Standard Webhooks key sends nothing, rather '
        'than a delivery nobody can verify, and the record does not repeat '
        'the key', () async {
      DVWebhooks.config = DVWebhooksConfig.read(
          <String, Object?>{'signature': 'standard'},
          application: 'shop');
      DVSecrets.configure(<String, String>{'BAD_KEY': 'not base64 !!'});
      await const DVWebhooks().subscribe(
        url: 'https://hooks.acme.test/in',
        events: <String>{'order.paid'},
        signingSecret: 'BAD_KEY',
      );
      final List<DVWebhookDelivery> sent = await const DVWebhooks()
          .emit('order.paid', <String, Object?>{'orderId': 'o-1'});
      await const DVWebhooks().drainOnce(sent.single.subscriptionId);
      expect(wire.requests, isEmpty);
      final DVWebhookDelivery record =
          (await const DVWebhooks().delivery(sent.single.id))!;
      expect(record.state, DVWebhookDeliveryState.pending);
      expect(record.lastError, isNotNull);
      expect(record.lastError, isNot(contains('not base64 !!')));
    });
  });

  group('dartvel.webhooks is read strictly', () {
    test('no block is the default: Dartvel\'s envelope and signature', () {
      final DVWebhooksConfig config = DVWebhooksConfig.read(null);
      expect(config.format, DVWebhookFormat.dartvel);
      expect(config.signature, DVWebhookSignatureScheme.dartvel);
    });

    test('the source defaults to the application\'s name', () {
      expect(
        DVWebhooksConfig.read(<String, Object?>{'format': 'cloudevents'},
                application: 'shop')
            .source,
        '/shop',
      );
    });

    test('the settings the specification already lists are honoured', () {
      final DVWebhooksConfig config = DVWebhooksConfig.read(<String, Object?>{
        'allowPrivateAddresses': true,
        'retention': '7d',
        'disableAfter': 5,
        'maxAttempts': 3,
      });
      expect(config.allowPrivateAddresses, isTrue);
      expect(config.retention, const Duration(days: 7));
      expect(config.disableAfter, 5);
      expect(config.maxAttempts, 3);
    });

    test('an unknown key is refused, naming the ones there are', () {
      expect(() => DVWebhooksConfig.read(<String, Object?>{'fromat': 'x'}),
          _refused('dartvel.webhooks.fromat is not a setting'));
    });

    test('an unknown format is refused', () {
      expect(() => DVWebhooksConfig.read(<String, Object?>{'format': 'json'}),
          _refused('dartvel, cloudevents'));
    });

    test('an unknown signature scheme is refused', () {
      expect(
          () => DVWebhooksConfig.read(<String, Object?>{'signature': 'hmac'}),
          _refused('dartvel, standard'));
    });

    test('a CloudEvents mode or source without format: cloudevents is '
        'refused, since it would do nothing', () {
      expect(() => DVWebhooksConfig.read(<String, Object?>{'mode': 'binary'}),
          _refused('format: cloudevents'));
      expect(() => DVWebhooksConfig.read(<String, Object?>{'source': '/x'}),
          _refused('format: cloudevents'));
    });

    test('an unknown mode is refused', () {
      expect(
          () => DVWebhooksConfig.read(
              <String, Object?>{'format': 'cloudevents', 'mode': 'batch'}),
          _refused('structured, binary'));
    });

    test('a source that is not a URI reference is refused', () {
      expect(
          () => DVWebhooksConfig.read(
              <String, Object?>{'format': 'cloudevents', 'source': ''}),
          _refused('source'));
      expect(
          () => DVWebhooksConfig.read(<String, Object?>{
                'format': 'cloudevents',
                'source': 'http://[bad',
              }),
          _refused('source'));
    });

    test('allowPrivateAddresses must be a boolean, not a string that reads '
        'as one', () {
      expect(
          () => DVWebhooksConfig.read(
              <String, Object?>{'allowPrivateAddresses': 'false'}),
          _refused('allowPrivateAddresses'));
    });

    test('a block that is not a map is refused', () {
      expect(() => DVWebhooksConfig.read('cloudevents'), _refused('a map'));
    });

    test('toMap reads back as the same configuration', () {
      final DVWebhooksConfig config = DVWebhooksConfig.read(<String, Object?>{
        'format': 'cloudevents',
        'mode': 'binary',
        'signature': 'standard',
        'retention': '7d',
      }, application: 'shop');
      final DVWebhooksConfig again = DVWebhooksConfig.read(config.toMap());
      expect(again.format, DVWebhookFormat.cloudevents);
      expect(again.cloudEventsMode, DVCloudEventMode.binary);
      expect(again.signature, DVWebhookSignatureScheme.standard);
      expect(again.source, '/shop');
      expect(again.retention, const Duration(days: 7));
    });
  });
}
