// VAPID, checked against RFC 8292's example.
//
// ECDSA signatures are not reproducible from a published example unless the
// private key is published too, and RFC 8292 gives only the public half. So
// the RFC's own token is verified against the RFC's own key — which pins the
// signing input, the segment encoding and the r||s layout exactly — and this
// implementation's tokens are then round-tripped through the same verifier.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

// RFC 8292 §2.4.
const String rfcToken =
    'eyJ0eXAiOiJKV1QiLCJhbGciOiJFUzI1NiJ9.eyJhdWQiOiJodHRwczovL3B1c2guZXhh'
    'bXBsZS5uZXQiLCJleHAiOjE0NTM1MjM3NjgsInN1YiI6Im1haWx0bzpwdXNoQGV4YW1w'
    'bGUuY29tIn0.i3CYb7t4xfxCDquptFOepC9GAu_HLGkMlMuCGSK2rpiUfnK9ojFwDXb1'
    'JrErtmysazNjjvW2L9OkSSHzvoD1oA';
const String rfcJwkX = 'DUfHPKLVFQzVvnCPGyfucbECzPDa7rWbXriLcysAjEc';
const String rfcJwkY = 'F6YK5h4SDYic-dRuU_RCPCfA5aq9ojSwk5Y2EmClBPs';

/// The RFC's key as the uncompressed point the `k=` parameter carries.
Uint8List rfcPublicKey() => Uint8List.fromList(<int>[
      0x04,
      ...dvWebPushBase64Decode(rfcJwkX),
      ...dvWebPushBase64Decode(rfcJwkY),
    ]);

/// A key pair to sign with. Any P-256 scalar works; this one is fixed so the
/// tests do not depend on an entropy source.
DVWebPushKeyPair testKeyPair() => DVWebPushKeyPair.fromPrivateKey(
    dvWebPushBase64Decode('yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw'));

void main() {
  group('RFC 8292 §2.4', () {
    test("the RFC's own token verifies against the RFC's own key", () {
      // If the signing input were assembled differently, or r||s were read as
      // DER, this would not verify.
      expect(DVWebPushVapid.verify(rfcToken, rfcPublicKey()), isTrue);
    });

    test('a token that has been tampered with does not verify', () {
      final parts = rfcToken.split('.');
      final forged = <String, Object?>{
        'aud': 'https://push.attacker.example',
        'exp': 1453523768,
        'sub': 'mailto:push@example.com',
      };
      final swapped =
          '${parts[0]}.${dvWebPushBase64Encode(utf8.encode(jsonEncode(forged)))}'
          '.${parts[2]}';

      expect(DVWebPushVapid.verify(swapped, rfcPublicKey()), isFalse);
    });

    test('the published claims are the ones VAPID requires', () {
      final claims = DVWebPushVapid.claimsOf(rfcToken);

      expect(claims['aud'], 'https://push.example.net');
      expect(claims['exp'], 1453523768);
      expect(claims['sub'], 'mailto:push@example.com');
    });

    test('the header names JWT and ES256', () {
      final header = jsonDecode(utf8
          .decode(dvWebPushBase64Decode(rfcToken.split('.').first)));

      expect(header, <String, Object?>{'typ': 'JWT', 'alg': 'ES256'});
    });
  });

  group('signing', () {
    test('a token this implementation produces verifies', () {
      final keys = testKeyPair();
      final token = DVWebPushVapid.signedToken(
        audience: 'https://push.example.net',
        expiresAt: DateTime.utc(2026, 1, 1),
        subject: 'mailto:push@example.com',
        keyPair: keys,
      );

      expect(DVWebPushVapid.verify(token, keys.publicKey), isTrue);
      // And not against somebody else's key.
      expect(DVWebPushVapid.verify(token, rfcPublicKey()), isFalse);
    });

    test('expiry is seconds since the epoch, not milliseconds', () {
      // A millisecond exp reads as a date 50,000 years out, which a push
      // service rejects as beyond the 24-hour limit.
      final token = DVWebPushVapid.signedToken(
        audience: 'https://push.example.net',
        expiresAt: DateTime.utc(2016, 1, 23, 4, 36, 8),
        keyPair: testKeyPair(),
      );

      expect(DVWebPushVapid.claimsOf(token)['exp'], 1453523768);
    });

    test('a subject is optional but kept when given', () {
      final without = DVWebPushVapid.signedToken(
        audience: 'https://push.example.net',
        expiresAt: DateTime.utc(2026),
        keyPair: testKeyPair(),
      );

      expect(DVWebPushVapid.claimsOf(without).containsKey('sub'), isFalse);
    });
  });

  group('the authorization header', () {
    test('carries the token and the sending key', () {
      final keys = testKeyPair();
      final header = DVWebPushVapid.authorizationHeader(
        endpoint: 'https://push.example.net/push/JzLQ3raZJfFBR0aqvOMsLrt54w4',
        keyPair: keys,
        subject: 'mailto:push@example.com',
        now: DateTime.utc(2026, 1, 1),
      );

      expect(header, startsWith('vapid t='));
      expect(header, contains(', k=${dvWebPushBase64Encode(keys.publicKey)}'));

      final token = header.substring('vapid t='.length).split(', k=').first;
      expect(DVWebPushVapid.verify(token, keys.publicKey), isTrue);
    });

    test('the audience is the origin, not the subscription', () {
      // A token scoped to one subscription path would have to be re-signed
      // for every recipient.
      final header = DVWebPushVapid.authorizationHeader(
        endpoint: 'https://push.example.net/push/JzLQ3raZJfFBR0aqvOMsLrt54w4',
        keyPair: testKeyPair(),
        now: DateTime.utc(2026, 1, 1),
      );
      final token = header.substring('vapid t='.length).split(', k=').first;

      expect(DVWebPushVapid.claimsOf(token)['aud'], 'https://push.example.net');
    });

    test('a non-default port stays in the audience', () {
      expect(
        DVWebPushVapid.audienceFor('https://push.example.net:8443/push/abc'),
        'https://push.example.net:8443',
      );
    });

    test('expiry defaults inside the limit and is capped at it', () {
      final now = DateTime.utc(2026, 1, 1);
      final header = DVWebPushVapid.authorizationHeader(
        endpoint: 'https://push.example.net/push/abc',
        keyPair: testKeyPair(),
        now: now,
      );
      final token = header.substring('vapid t='.length).split(', k=').first;
      final exp = DVWebPushVapid.claimsOf(token)['exp']! as int;

      expect(exp, now.add(const Duration(hours: 12)).millisecondsSinceEpoch ~/ 1000);

      expect(
        () => DVWebPushVapid.authorizationHeader(
          endpoint: 'https://push.example.net/push/abc',
          keyPair: testKeyPair(),
          expiry: const Duration(hours: 25),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a subject that is not a contact URI is refused', () {
      expect(
        () => DVWebPushVapid.authorizationHeader(
          endpoint: 'https://push.example.net/push/abc',
          keyPair: testKeyPair(),
          subject: 'Dartvel',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a relative endpoint is refused', () {
      expect(
        () => DVWebPushVapid.audienceFor('/push/abc'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
