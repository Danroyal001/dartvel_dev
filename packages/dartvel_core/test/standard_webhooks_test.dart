// Standard Webhooks signing (https://www.standardwebhooks.com).
//
// The point of offering this scheme is that a customer verifies with the
// official standardwebhooks library in their own language, not with code we
// wrote. So the vectors here are the libraries' own, copied from their test
// suites (libraries/go/webhook_test.go and
// libraries/javascript/src/webhook.test.ts), not values this implementation
// produced and then wrote down.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

// The libraries' shared fixture.
const String _secret = 'MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw';
const String _id = 'msg_p5jXN8AQM9LWM0D4loKWxJek';
const String _payload = '{"test": 2432232314}';

/// What the JavaScript suite's TestPayload computes, written independently of
/// the implementation: base64(HMAC-SHA256(base64decode(secret), id.ts.body)).
String _reference(String id, int timestamp, String body) => base64.encode(
      Hmac(sha256, base64.decode(_secret))
          .convert(utf8.encode('$id.$timestamp.$body'))
          .bytes,
    );

void main() {
  final DateTime now = DateTime.utc(2026, 9, 26, 12);
  final int nowSeconds = now.millisecondsSinceEpoch ~/ 1000;

  Map<String, String> headersAt(int timestamp) => <String, String>{
        'webhook-id': _id,
        'webhook-timestamp': '$timestamp',
        'webhook-signature': 'v1,${_reference(_id, timestamp, _payload)}',
      };

  bool verify(Map<String, String> headers,
          {String secret = _secret, Duration? tolerance = const Duration(minutes: 5)}) =>
      DVStandardWebhookSignature.verify(
        secret: secret,
        headers: headers,
        body: _payload,
        tolerance: tolerance,
        now: now,
      );

  group('the libraries\' signing vector', () {
    test('whsec_ key, msg id, 1614265330 and the fixture body sign to the '
        'value every official library expects', () {
      expect(
        DVStandardWebhookSignature.sign(
          secret: 'whsec_$_secret',
          id: _id,
          timestamp: '1614265330',
          body: _payload,
        ),
        'v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=',
      );
    });

    test('an unbranded key, without whsec_, signs the same', () {
      expect(
        DVStandardWebhookSignature.sign(
          secret: _secret,
          id: _id,
          timestamp: '1614265330',
          body: _payload,
        ),
        'v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=',
      );
    });

    test('a rotation header is the signatures space-delimited, current first',
        () {
      final String header = DVStandardWebhookSignature.header(
        id: _id,
        timestamp: '1614265330',
        body: _payload,
        secrets: <String>[
          'whsec_$_secret',
          'whsec_${base64.encode(List<int>.filled(32, 7))}',
        ],
      );
      final List<String> parts = header.split(' ');
      expect(parts, hasLength(2));
      expect(parts.first, 'v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=');
      expect(parts.last, startsWith('v1,'));
      expect(parts.last, isNot(parts.first));
    });
  });

  group('verification, case for case with the libraries\' suites', () {
    test('a valid signature is valid', () {
      expect(verify(headersAt(nowSeconds)), isTrue);
    });

    test('a valid signature is valid under the whsec_ form of the key', () {
      expect(verify(headersAt(nowSeconds), secret: 'whsec_$_secret'), isTrue);
    });

    test('header names are matched without regard to case', () {
      final Map<String, String> headers = <String, String>{
        for (final MapEntry<String, String> e in headersAt(nowSeconds).entries)
          e.key.toUpperCase(): e.value,
      };
      expect(verify(headers), isTrue);
    });

    for (final String missing in <String>[
      'webhook-id',
      'webhook-timestamp',
      'webhook-signature',
    ]) {
      test('a missing $missing fails', () {
        expect(verify(headersAt(nowSeconds)..remove(missing)), isFalse);
      });
    }

    test('an unreadable timestamp fails', () {
      expect(verify(headersAt(nowSeconds)..['webhook-timestamp'] = 'hello'),
          isFalse);
    });

    test('an invalid signature fails', () {
      expect(
        verify(headersAt(nowSeconds)
          ..['webhook-signature'] = 'v1,Ceo5qEr07ixe2NLpvHk3FH9bwy/WavXrAFQ/9tdO6mc='),
        isFalse,
      );
    });

    test('a partial signature fails', () {
      final Map<String, String> headers = headersAt(nowSeconds);
      expect(
          verify(<String, String>{
            ...headers,
            'webhook-signature': headers['webhook-signature']!.substring(0, 8),
          }),
          isFalse);
      expect(verify(<String, String>{...headers, 'webhook-signature': 'v1,'}),
          isFalse);
    });

    test('a signature for a different id fails: the id is signed', () {
      expect(verify(headersAt(nowSeconds)..['webhook-id'] = 'msg_other'),
          isFalse);
    });

    test('a timestamp older than the tolerance fails', () {
      expect(verify(headersAt(nowSeconds - 5 * 60 - 1)), isFalse);
    });

    test('a timestamp further ahead than the tolerance fails', () {
      expect(verify(headersAt(nowSeconds + 5 * 60 + 1)), isFalse);
    });

    test('the tolerance defaults to the libraries\' five minutes', () {
      expect(
        DVStandardWebhookSignature.verify(
          secret: _secret,
          headers: headersAt(nowSeconds - 5 * 60 - 1),
          body: _payload,
          now: now,
        ),
        isFalse,
      );
      expect(
        DVStandardWebhookSignature.verify(
          secret: _secret,
          headers: headersAt(nowSeconds - 4 * 60),
          body: _payload,
          now: now,
        ),
        isTrue,
      );
    });

    test('an old timestamp passes when the caller turns the window off', () {
      expect(verify(headersAt(nowSeconds - 3600), tolerance: null), isTrue);
    });

    test('a multi-signature header with other versions and wrong entries is '
        'valid when one v1 entry matches', () {
      final Map<String, String> headers = headersAt(nowSeconds);
      headers['webhook-signature'] = <String>[
        'v1,Ceo5qEr07ixe2NLpvHk3FH9bwy/WavXrAFQ/9tdO6mc=',
        'v2,Ceo5qEr07ixe2NLpvHk3FH9bwy/WavXrAFQ/9tdO6mc=',
        headers['webhook-signature']!,
        'v1,Ceo5qEr07ixe2NLpvHk3FH9bwy/WavXrAFQ/9tdO6mc=',
      ].join(' ');
      expect(verify(headers), isTrue);
    });

    test('a v1 signature under a v2 label does not count', () {
      final Map<String, String> headers = headersAt(nowSeconds);
      headers['webhook-signature'] =
          headers['webhook-signature']!.replaceFirst('v1,', 'v2,');
      expect(verify(headers), isFalse);
    });
  });

  group('keys', () {
    for (final String bad in <String>['', 'whsec_']) {
      test('an empty key ("$bad") is refused', () {
        expect(
          () => DVStandardWebhookSignature.sign(
              secret: bad, id: _id, timestamp: '1', body: _payload),
          throwsArgumentError,
        );
      });
    }

    test('a key that is not base64 is refused, and the refusal does not '
        'repeat the key', () {
      const String secret = 'whsec_not base64 at all!';
      expect(
        () => DVStandardWebhookSignature.sign(
            secret: secret, id: _id, timestamp: '1', body: _payload),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => '$e', 'message', isNot(contains('not base64')))),
      );
    });
  });
}
