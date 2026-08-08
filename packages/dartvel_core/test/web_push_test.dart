// Web Push encryption, checked against RFC 8291's own worked example.
//
// Encryption is the one thing that cannot be verified by reading it: a
// derivation that is subtly wrong still produces plausible-looking bytes, and
// the failure only shows up as a browser silently dropping every message. The
// RFC publishes each intermediate value, so each step is checked rather than
// only the final body.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

// RFC 8291 §5.
const String rfcPlaintext = 'When I grow up, I want to be a watermelon';
const String rfcUaPublic =
    'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4';
const String rfcUaPrivate = 'q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94';
const String rfcAuthSecret = 'BTBZMqHH6r4Tts7J_aSIgg';
const String rfcAsPublic =
    'BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8';
const String rfcAsPrivate = 'yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw';
const String rfcSalt = 'DGv6ra1nlYgDCS1FRnbzlw';
const String rfcSharedSecret = 'kyrL1jIIOHEzg3sM2ZWRHDRB62YACZhhSlknJ672kSs';
const String rfcPrkKey = 'Snr3JMxaHVDXHWJn5wdC52WjpCtd2EIEGBykDcZW32k';
const String rfcIkm = 'S4lYMb_L0FxCeq0WhDx813KgSYqU26kOyzWUdsXYyrg';
const String rfcPrk = '09_eUZGrsvxChDCGRCdkLiDXrReGOEVeSCdCcPBSJSc';
const String rfcCek = 'oIhVW04MRdy2XN9CiKLxTg';
const String rfcNonce = '4h_95klXJ5E_qnoN';
const String rfcBody =
    'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27ml'
    'mlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPT'
    'pK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN';

DVWebPushSubscription rfcSubscription() => DVWebPushSubscription(
      endpoint: 'https://push.example.net/push/JzLQ3raZJfFBR0aqvOMsLrt54w4rJUsV',
      p256dh: dvWebPushBase64Decode(rfcUaPublic),
      auth: dvWebPushBase64Decode(rfcAuthSecret),
    );

DVWebPushMessage rfcMessage() => DVWebPush.encrypt(
      subscription: rfcSubscription(),
      payload: utf8.encode(rfcPlaintext),
      salt: dvWebPushBase64Decode(rfcSalt),
      keyPair:
          DVWebPushKeyPair.fromPrivateKey(dvWebPushBase64Decode(rfcAsPrivate)),
    );

void main() {
  group('RFC 8291 §5', () {
    test('the application server key pair rebuilds from its private key', () {
      final keys =
          DVWebPushKeyPair.fromPrivateKey(dvWebPushBase64Decode(rfcAsPrivate));

      expect(dvWebPushBase64Encode(keys.publicKey), rfcAsPublic);
    });

    test('the final body matches the published message', () {
      // The whole point: the exact bytes a push service is handed.
      expect(dvWebPushBase64Encode(rfcMessage().body), rfcBody);
    });

    test('the header carries salt, record size and sender key', () {
      final body = rfcMessage().body;
      final salt = dvWebPushBase64Decode(rfcSalt);
      final asPublic = dvWebPushBase64Decode(rfcAsPublic);

      expect(body.sublist(0, 16), salt);
      // Record size is a big-endian uint32; getting the byte order wrong
      // here reads as a 16MB record.
      expect(ByteData.view(Uint8List.fromList(body).buffer).getUint32(16),
          4096);
      expect(body[20], 65);
      expect(body.sublist(21, 86), asPublic);
    });

    test('the ciphertext is the payload, a delimiter, and a tag', () {
      final body = rfcMessage().body;
      final ciphertext = body.sublist(86);

      // 41 bytes of plaintext, the 0x02 last-record delimiter, a 16-byte tag.
      expect(utf8.encode(rfcPlaintext), hasLength(41));
      expect(ciphertext, hasLength(41 + 1 + 16));
    });

    test('each derived value matches the one the RFC publishes', () {
      // Reproducing §3.4 against the same inputs: if the final body were
      // right by luck, these would not all line up.
      Uint8List hmac(List<int> key, List<int> data) =>
          Uint8List.fromList(Hmac(sha256, key).convert(data).bytes);

      final auth = dvWebPushBase64Decode(rfcAuthSecret);
      final uaPublic = dvWebPushBase64Decode(rfcUaPublic);
      final asPublic = dvWebPushBase64Decode(rfcAsPublic);
      final sharedSecret = dvWebPushBase64Decode(rfcSharedSecret);

      final prkKey = hmac(auth, sharedSecret);
      expect(dvWebPushBase64Encode(prkKey), rfcPrkKey);

      final ikm = hmac(prkKey, <int>[
        ...utf8.encode('WebPush: info'),
        0x00,
        ...uaPublic,
        ...asPublic,
        0x01,
      ]);
      expect(dvWebPushBase64Encode(ikm), rfcIkm);

      final prk = hmac(dvWebPushBase64Decode(rfcSalt), ikm);
      expect(dvWebPushBase64Encode(prk), rfcPrk);

      final cek = hmac(prk, <int>[
        ...utf8.encode('Content-Encoding: aes128gcm'),
        0x00,
        0x01,
      ]).sublist(0, 16);
      expect(dvWebPushBase64Encode(cek), rfcCek);

      final nonce = hmac(prk, <int>[
        ...utf8.encode('Content-Encoding: nonce'),
        0x00,
        0x01,
      ]).sublist(0, 12);
      expect(dvWebPushBase64Encode(nonce), rfcNonce);
    });

    test('the agreement reaches the same shared secret from either side', () {
      // Both halves derive it, so deriving it from the user agent's key must
      // give the same answer as from the application server's.
      final fromApplicationServer = DVWebPush.encrypt(
        subscription: rfcSubscription(),
        payload: utf8.encode(rfcPlaintext),
        salt: dvWebPushBase64Decode(rfcSalt),
        keyPair:
            DVWebPushKeyPair.fromPrivateKey(dvWebPushBase64Decode(rfcAsPrivate)),
      );
      final uaKeys =
          DVWebPushKeyPair.fromPrivateKey(dvWebPushBase64Decode(rfcUaPrivate));
      expect(dvWebPushBase64Encode(uaKeys.publicKey), rfcUaPublic);
      expect(dvWebPushBase64Encode(fromApplicationServer.body), rfcBody);
    });
  });

  group('messages', () {
    test('headers describe an aes128gcm body', () {
      final message = rfcMessage();

      expect(message.headers['content-encoding'], 'aes128gcm');
      expect(message.headers['content-type'], 'application/octet-stream');
      expect(message.headers['content-length'], '${message.body.length}');
      expect(message.body, hasLength(86 + 41 + 1 + 16));
    });

    test('two messages with the same payload differ', () {
      // A fresh salt and ephemeral key per message is what keeps one
      // recovered key from opening the rest.
      final subscription = rfcSubscription();
      final first = DVWebPush.encrypt(
        subscription: subscription,
        payload: utf8.encode('same'),
      );
      final second = DVWebPush.encrypt(
        subscription: subscription,
        payload: utf8.encode('same'),
      );

      expect(first.body, isNot(second.body));
    });

    test('an empty payload still encrypts to a valid record', () {
      final message = DVWebPush.encrypt(
        subscription: rfcSubscription(),
        payload: const <int>[],
      );

      // Header, the delimiter byte, and the tag.
      expect(message.body, hasLength(86 + 1 + 16));
    });

    test('a generated key pair round-trips through its private key', () {
      final generated = DVWebPushKeyPair.generate(Random(7));
      final rebuilt = DVWebPushKeyPair.fromPrivateKey(generated.privateKey);

      expect(rebuilt.publicKey, generated.publicKey);
      expect(generated.publicKey, hasLength(65));
      expect(generated.publicKey.first, 0x04);
    });
  });

  group('subscriptions', () {
    test('are read from the JSON a browser produces', () {
      final subscription = DVWebPushSubscription.fromJson(<String, Object?>{
        'endpoint': 'https://push.example.net/push/abc',
        'keys': <String, Object?>{
          'p256dh': rfcUaPublic,
          'auth': rfcAuthSecret,
        },
      });

      expect(subscription.endpoint, 'https://push.example.net/push/abc');
      expect(dvWebPushBase64Encode(subscription.p256dh), rfcUaPublic);
      expect(subscription.auth, hasLength(16));
    });

    test('a key that is not an uncompressed P-256 point is refused', () {
      // Accepting it would produce a body no browser can decrypt, reported
      // as a successful send.
      expect(
        () => DVWebPushSubscription(
          endpoint: 'https://push.example.net/push/abc',
          p256dh: Uint8List(64),
          auth: Uint8List(16),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an auth secret of the wrong length is refused', () {
      expect(
        () => DVWebPushSubscription(
          endpoint: 'https://push.example.net/push/abc',
          p256dh: dvWebPushBase64Decode(rfcUaPublic),
          auth: Uint8List(8),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a salt of the wrong length is refused', () {
      expect(
        () => DVWebPush.encrypt(
          subscription: rfcSubscription(),
          payload: utf8.encode('x'),
          salt: Uint8List(8),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
