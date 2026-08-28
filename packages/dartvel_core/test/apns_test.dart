// APNS is unusually unforgiving: it rejects a payload whose custom data is in
// the wrong place, a background push at the wrong priority, and a token minted
// for the other environment — each with a terse reason and no explanation.
// These tests pin the details that are wrong silently.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  DVHttpRequest? captured;

  DVHttpSend respondWith(int status, {String body = '{}'}) {
    return (DVHttpRequest request) async {
      captured = request;
      return DVHttpResponse(statusCode: status, body: body);
    };
  }

  ApnsPushProvider provider({
    ApnsEnvironment environment = ApnsEnvironment.production,
    ApnsPushType pushType = ApnsPushType.alert,
    int? priority,
    DVHttpSend? transport,
  }) =>
      ApnsPushProvider(
        topic: 'com.example.app',
        accessToken: () async => 'jwt-token',
        environment: environment,
        pushType: pushType,
        priority: priority,
        transport: transport ?? respondWith(200),
      );

  const message = DVNotificationMessage(
    title: 'Order shipped',
    body: 'It is on its way',
    data: <String, String>{'orderId': '42'},
  );

  setUp(() => captured = null);

  group('the request', () {
    test('is pinned to HTTP/2 and never falls back', () async {
      // Apple runs no HTTP/1.1 endpoint. Falling back would fail at a layer
      // that cannot explain itself.
      await provider().send('device-token', message);
      expect(captured!.protocols.protocols,
          <DVHttpProtocol>[DVHttpProtocol.http2]);
    });

    test('addresses the device on the right host and path', () async {
      await provider().send('abc123', message);
      expect(captured!.url.host, 'api.push.apple.com');
      expect(captured!.url.path, '/3/device/abc123');
    });

    test('sandbox is a different host, not a flag', () async {
      await provider(environment: ApnsEnvironment.sandbox)
          .send('abc123', message);
      expect(captured!.url.host, 'api.sandbox.push.apple.com');
    });

    test('carries the headers APNS requires', () async {
      await provider().send('abc123', message);
      expect(captured!.headers['apns-topic'], 'com.example.app');
      expect(captured!.headers['apns-push-type'], 'alert');
      expect(captured!.headers['authorization'], 'bearer jwt-token');
    });

    test('trims the device token', () async {
      await provider().send('  abc123  ', message);
      expect(captured!.url.path, '/3/device/abc123');
    });

    test('an empty token is rejected before any request', () async {
      await expectLater(
        provider().send('   ', message),
        throwsA(isA<ArgumentError>()),
      );
      expect(captured, isNull);
    });
  });

  group('the payload', () {
    Map<String, Object?> decode() =>
        jsonDecode(utf8.decode(captured!.body)) as Map<String, Object?>;

    test('puts custom data beside aps, not inside it', () async {
      // The usual mistake. Apple ignores unknown keys inside `aps` silently
      // rather than reporting them, so getting this wrong looks like working.
      await provider().send('abc123', message);
      final payload = decode();
      expect(payload['orderId'], '42');
      expect((payload['aps'] as Map).containsKey('orderId'), isFalse);
    });

    test('an alert push carries title and body', () async {
      await provider().send('abc123', message);
      final alert = (decode()['aps'] as Map)['alert'] as Map;
      expect(alert['title'], 'Order shipped');
      expect(alert['body'], 'It is on its way');
    });

    test('a background push sends content-available and no alert', () async {
      await provider(pushType: ApnsPushType.background)
          .send('abc123', message);
      final aps = decode()['aps'] as Map;
      expect(aps['content-available'], 1);
      expect(aps.containsKey('alert'), isFalse);
    });
  });

  group('priority', () {
    test('defaults to 10 for an alert', () async {
      await provider().send('abc123', message);
      expect(captured!.headers['apns-priority'], '10');
    });

    test('defaults to 5 for a background push, which APNS requires', () async {
      // APNS rejects a background push sent at priority 10 outright, so the
      // default has to depend on the push type rather than be a constant.
      await provider(pushType: ApnsPushType.background)
          .send('abc123', message);
      expect(captured!.headers['apns-priority'], '5');
    });

    test('an explicit priority still wins', () async {
      await provider(pushType: ApnsPushType.background, priority: 10)
          .send('abc123', message);
      expect(captured!.headers['apns-priority'], '10');
    });
  });

  group('failures', () {
    test('a rejection explains what the terse reason means', () async {
      await expectLater(
        provider(
          transport: respondWith(400, body: '{"reason":"BadDeviceToken"}'),
        ).send('abc123', message),
        throwsA(isA<DVPushProviderException>().having(
          (e) => e.toString(),
          'message',
          contains('other APNS environment'),
        )),
      );
    });

    test('an unrecognised reason is passed through, never swallowed',
        () async {
      // A reason Apple adds later must still reach the log verbatim.
      final response =
          const DVHttpResponse(statusCode: 400, body: '{"reason":"SomethingNew"}');
      expect(apnsFailureReason(response), 'SomethingNew');
    });

    test('a body with no reason still produces a message', () async {
      expect(
        apnsFailureReason(const DVHttpResponse(statusCode: 503, body: '')),
        contains('rejected'),
      );
    });

    test('a non-JSON body does not throw while reporting', () async {
      expect(
        apnsFailureReason(
            const DVHttpResponse(statusCode: 502, body: '<html>gateway</html>')),
        contains('rejected'),
      );
    });

    test('success does not throw', () async {
      await provider().send('abc123', message);
    });
  });
}
