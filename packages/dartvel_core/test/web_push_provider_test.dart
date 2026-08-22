// The provider that puts RFC 8291 encryption and RFC 8292 VAPID on the wire
// together. The encryption and signing are tested elsewhere; what is tested
// here is that both are actually applied, that the ephemeral key is not
// confused with the identity key, and that a gone subscription is reported as
// something to delete rather than retry.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late DVWebPushKeyPair vapidKeys;
  late DVWebPushKeyPair browserKeys;
  late String subscriptionJson;
  DVHttpRequest? captured;

  setUp(() {
    // Seeded so the test is deterministic; the production path uses
    // Random.secure().
    final random = Random(7);
    vapidKeys = DVWebPushKeyPair.generate(random);
    browserKeys = DVWebPushKeyPair.generate(random);
    final auth = Uint8List.fromList(
        List<int>.generate(16, (int i) => (i * 7 + 3) & 0xff));
    subscriptionJson = jsonEncode(<String, Object?>{
      'endpoint': 'https://push.example.test/subscription/abc',
      'keys': <String, String>{
        'p256dh': base64Url.encode(browserKeys.publicKey).replaceAll('=', ''),
        'auth': base64Url.encode(auth).replaceAll('=', ''),
      },
    });
    captured = null;
  });

  DVHttpSend respondWith(int status, {String body = ''}) =>
      (DVHttpRequest request) async {
        captured = request;
        return DVHttpResponse(statusCode: status, body: body);
      };

  WebPushProvider provider({DVHttpSend? transport}) => WebPushProvider(
        vapidKeys: vapidKeys,
        subject: 'mailto:ops@example.test',
        transport: transport ?? respondWith(201),
      );

  const message = DVNotificationMessage(
    title: 'Build finished',
    body: 'All targets passed',
    data: <String, String>{'runId': '99'},
  );

  group('the request', () {
    test('goes to the subscription endpoint', () async {
      await provider().send(subscriptionJson, message);
      expect(captured!.url.toString(),
          'https://push.example.test/subscription/abc');
    });

    test('is encrypted, never plaintext', () async {
      // An unencrypted body is a protocol error rather than a degraded mode,
      // so the assertion is that the payload is *absent* from the wire.
      await provider().send(subscriptionJson, message);
      expect(captured!.headers['content-encoding'], 'aes128gcm');
      final wire = utf8.decode(captured!.body, allowMalformed: true);
      expect(wire, isNot(contains('Build finished')));
      expect(wire, isNot(contains('runId')));
    });

    test('is signed with VAPID', () async {
      // A push service refuses an anonymous POST, since anyone who learned the
      // endpoint could otherwise send to it.
      await provider().send(subscriptionJson, message);
      expect(captured!.headers['authorization'], startsWith('vapid '));
    });

    test('carries a TTL the service can act on', () async {
      await provider().send(subscriptionJson, message);
      expect(captured!.headers['ttl'], '${const Duration(hours: 24).inSeconds}');
    });
  });

  group('keys', () {
    test('the identity key is stable across sends', () async {
      // The browser pinned this key at subscribe time. If it changed per
      // message, every existing subscription would break on the next send —
      // and would look like a server problem, not a key problem.
      // The `k=` parameter carries the identity public key. Comparing whole
      // headers would be flaky, because the JWT's `exp` moves with the clock —
      // the key is the part that must not move.
      String identityKeyOf(String header) => header
          .split(',')
          .map((String part) => part.trim())
          .firstWhere((String part) => part.startsWith('k='));

      await provider().send(subscriptionJson, message);
      final first = identityKeyOf(captured!.headers['authorization']!);
      await provider().send(subscriptionJson, message);
      final second = identityKeyOf(captured!.headers['authorization']!);
      expect(first, second);
      expect(first.length, greaterThan('k='.length));
    });

    test('the message key is fresh every time', () async {
      // Distinct from the VAPID pair: one recovered message key must not open
      // every message ever sent.
      await provider().send(subscriptionJson, message);
      final first = Uint8List.fromList(captured!.body);
      await provider().send(subscriptionJson, message);
      final second = Uint8List.fromList(captured!.body);
      expect(first, isNot(equals(second)),
          reason: 'a fresh salt and key pair must change the ciphertext');
    });
  });

  group('recipients', () {
    test('an empty recipient is rejected before any request', () async {
      await expectLater(
        provider().send('  ', message),
        throwsA(isA<ArgumentError>()),
      );
      expect(captured, isNull);
    });

    test('a non-JSON recipient explains what was expected', () async {
      await expectLater(
        provider().send('not-json', message),
        throwsA(isA<ArgumentError>().having(
          (ArgumentError e) => e.toString(),
          'message',
          contains('PushManager.subscribe()'),
        )),
      );
    });

    test('a JSON value that is not an object is rejected', () async {
      await expectLater(
        provider().send('[1,2,3]', message),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('failures', () {
    test('410 says to delete the subscription, not retry it', () async {
      // The status that matters most, and the one whose ordinary meaning is
      // misleading here.
      expect(
        webPushFailureReason(const DVHttpResponse(statusCode: 410, body: '')),
        allOf(contains('gone'), contains('Delete')),
      );
    });

    test('404 is treated the same as 410', () async {
      expect(
        webPushFailureReason(const DVHttpResponse(statusCode: 404, body: '')),
        contains('Delete'),
      );
    });

    test('413 names the payload limit', () async {
      expect(
        webPushFailureReason(const DVHttpResponse(statusCode: 413, body: '')),
        contains('4KB'),
      );
    });

    test('401 points at VAPID rather than the payload', () async {
      expect(
        webPushFailureReason(const DVHttpResponse(statusCode: 401, body: '')),
        contains('VAPID'),
      );
    });

    test('a rejection surfaces as a push provider exception', () async {
      await expectLater(
        provider(transport: respondWith(410)).send(subscriptionJson, message),
        throwsA(isA<DVPushProviderException>()),
      );
    });

    test('a 201 does not throw', () async {
      await provider().send(subscriptionJson, message);
    });
  });
}
