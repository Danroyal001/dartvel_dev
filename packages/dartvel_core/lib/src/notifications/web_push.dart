// Web Push message encryption, per RFC 8291.
//
// A browser subscription is not a token that can be posted to: the push
// service is untrusted infrastructure, so the payload is encrypted end to end
// with a key only the subscribing user agent holds. Sending an unencrypted
// body is not a degraded mode, it is a protocol error — so this is what makes
// `DVNotificationChannel.webPush` more than an enum value.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// The subscription a browser hands back from `PushManager.subscribe()`.
///
/// `p256dh` and `auth` arrive base64url-encoded in the subscription JSON,
/// which is why [fromJson] is the usual way to build one.
class DVWebPushSubscription {
  /// Where the push service accepts the message.
  final String endpoint;

  /// The user agent's P-256 public key, uncompressed (65 bytes).
  final Uint8List p256dh;

  /// The subscription's authentication secret (16 bytes).
  final Uint8List auth;

  DVWebPushSubscription({
    required this.endpoint,
    required Uint8List p256dh,
    required Uint8List auth,
  })  : p256dh = Uint8List.fromList(p256dh),
        auth = Uint8List.fromList(auth) {
    if (this.p256dh.length != 65 || this.p256dh[0] != 0x04) {
      throw ArgumentError.value(
        p256dh,
        'p256dh',
        'A Web Push subscription key is a 65-byte uncompressed P-256 point '
            'starting with 0x04.',
      );
    }
    if (this.auth.length != 16) {
      throw ArgumentError.value(
        auth,
        'auth',
        'A Web Push authentication secret is 16 bytes.',
      );
    }
  }

  /// Reads the shape `PushSubscription.toJSON()` produces.
  factory DVWebPushSubscription.fromJson(Map<String, Object?> json) {
    final keys = json['keys'];
    if (keys is! Map) {
      throw ArgumentError.value(
        json,
        'json',
        'A push subscription carries its keys under "keys".',
      );
    }
    return DVWebPushSubscription(
      endpoint: json['endpoint']! as String,
      p256dh: dvWebPushBase64Decode('${keys['p256dh']}'),
      auth: dvWebPushBase64Decode('${keys['auth']}'),
    );
  }
}

/// An application server key pair — the sender's identity to the push
/// service, and the ephemeral half of the key agreement.
class DVWebPushKeyPair {
  /// Uncompressed P-256 public key (65 bytes).
  final Uint8List publicKey;

  /// P-256 private scalar (32 bytes).
  final Uint8List privateKey;

  DVWebPushKeyPair({
    required Uint8List publicKey,
    required Uint8List privateKey,
  })  : publicKey = Uint8List.fromList(publicKey),
        privateKey = Uint8List.fromList(privateKey);

  /// A fresh key pair. Each message uses its own, which is what stops one
  /// recovered key from opening every message ever sent.
  factory DVWebPushKeyPair.generate([Random? random]) {
    final source = random ?? Random.secure();
    final seed = Uint8List(32);
    for (var i = 0; i < seed.length; i++) {
      seed[i] = source.nextInt(256);
    }
    final generator = ECKeyGenerator()
      ..init(ParametersWithRandom(
        ECKeyGeneratorParameters(ECDomainParameters('prime256v1')),
        SecureRandom('Fortuna')..seed(KeyParameter(seed)),
      ));
    final pair = generator.generateKeyPair();
    final public = pair.publicKey;
    final private = pair.privateKey;
    return DVWebPushKeyPair(
      publicKey: Uint8List.fromList(public.Q!.getEncoded(false)),
      privateKey: _unsignedBytes(private.d!, 32),
    );
  }

  /// Rebuilds the pair from a stored private scalar.
  factory DVWebPushKeyPair.fromPrivateKey(Uint8List privateKey) {
    if (privateKey.length != 32) {
      throw ArgumentError.value(
        privateKey,
        'privateKey',
        'A P-256 private key is 32 bytes.',
      );
    }
    final domain = ECDomainParameters('prime256v1');
    final d = _toBigInt(privateKey);
    final q = domain.G * d;
    return DVWebPushKeyPair(
      publicKey: Uint8List.fromList(q!.getEncoded(false)),
      privateKey: privateKey,
    );
  }
}

/// An encrypted Web Push message: the body to POST and the headers that
/// describe it.
class DVWebPushMessage {
  /// The `aes128gcm` body, header and ciphertext together.
  final Uint8List body;

  /// Headers the push service requires alongside [body]. VAPID
  /// authorization, if used, is added on top of these.
  Map<String, String> get headers => <String, String>{
        'content-encoding': 'aes128gcm',
        'content-type': 'application/octet-stream',
        'content-length': '${body.length}',
      };

  const DVWebPushMessage(this.body);
}

/// Encrypts payloads for Web Push subscriptions.
class DVWebPush {
  const DVWebPush._();

  /// The record size used for a single-record message. A Web Push payload is
  /// capped well below this, so one record is always enough.
  static const int recordSize = 4096;

  /// Encrypts [payload] for [subscription].
  ///
  /// [salt] and [keyPair] exist so a caller can reproduce a known message —
  /// the RFC's own test vector is checked this way. Leave them out and each
  /// message gets a fresh random salt and ephemeral key pair, which is what
  /// the protocol requires of real traffic.
  static DVWebPushMessage encrypt({
    required DVWebPushSubscription subscription,
    required List<int> payload,
    Uint8List? salt,
    DVWebPushKeyPair? keyPair,
    Random? random,
  }) {
    final source = random ?? Random.secure();
    final messageSalt = salt ?? _randomBytes(16, source);
    if (messageSalt.length != 16) {
      throw ArgumentError.value(
        salt,
        'salt',
        'A Web Push salt is 16 bytes.',
      );
    }
    final keys = keyPair ?? DVWebPushKeyPair.generate(random);

    final sharedSecret = _sharedSecret(keys.privateKey, subscription.p256dh);

    // RFC 8291 §3.4. The auth secret keys the first extraction, so a push
    // service that saw the ECDH exchange still cannot derive the key.
    final prkKey = _hmac(subscription.auth, sharedSecret);
    final keyInfo = Uint8List.fromList(<int>[
      ...utf8.encode('WebPush: info'),
      0x00,
      ...subscription.p256dh,
      ...keys.publicKey,
      0x01,
    ]);
    final ikm = _hmac(prkKey, keyInfo);

    // RFC 8188 §2.2: the content encryption key and nonce for aes128gcm.
    final prk = _hmac(messageSalt, ikm);
    final cek = Uint8List.sublistView(
      _hmac(prk, _info('Content-Encoding: aes128gcm')),
      0,
      16,
    );
    final nonce = Uint8List.sublistView(
      _hmac(prk, _info('Content-Encoding: nonce')),
      0,
      12,
    );

    // 0x02 marks the last record. Using 0x01 here would tell the receiver to
    // expect another record that never arrives.
    final record = Uint8List.fromList(<int>[...payload, 0x02]);
    final ciphertext = _aesGcmEncrypt(cek, nonce, record);

    final header = BytesBuilder()
      ..add(messageSalt)
      ..add(_uint32(recordSize))
      ..addByte(keys.publicKey.length)
      ..add(keys.publicKey);

    return DVWebPushMessage(
      Uint8List.fromList(<int>[...header.toBytes(), ...ciphertext]),
    );
  }

  /// The X coordinate of the ECDH agreement, which is the shared secret
  /// RFC 8291 derives from.
  static Uint8List _sharedSecret(Uint8List privateKey, Uint8List peerPublic) {
    final domain = ECDomainParameters('prime256v1');
    final peer = ECPublicKey(domain.curve.decodePoint(peerPublic), domain);
    final own = ECPrivateKey(_toBigInt(privateKey), domain);
    final agreement = ECDHBasicAgreement()..init(own);
    // Left-padded: a shared secret with a small X would otherwise be short,
    // and every derivation downstream would shift with it.
    return _unsignedBytes(agreement.calculateAgreement(peer), 32);
  }

  static Uint8List _info(String label) =>
      Uint8List.fromList(<int>[...utf8.encode(label), 0x00, 0x01]);

  static Uint8List _hmac(List<int> key, List<int> data) =>
      Uint8List.fromList(Hmac(sha256, key).convert(data).bytes);

  static Uint8List _aesGcmEncrypt(
    Uint8List key,
    Uint8List nonce,
    Uint8List plaintext,
  ) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
      );
    return cipher.process(plaintext);
  }

  static Uint8List _uint32(int value) {
    final bytes = Uint8List(4);
    ByteData.view(bytes.buffer).setUint32(0, value);
    return bytes;
  }

  static Uint8List _randomBytes(int length, Random source) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = source.nextInt(256);
    }
    return bytes;
  }
}

/// Decodes the unpadded base64url the Web Push APIs use throughout.
Uint8List dvWebPushBase64Decode(String value) {
  final padding = (4 - value.length % 4) % 4;
  return base64Url.decode(value + ('=' * padding));
}

/// Encodes to the unpadded base64url the Web Push APIs use throughout.
String dvWebPushBase64Encode(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

BigInt _toBigInt(Uint8List bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

/// A big-endian encoding of exactly [length] bytes.
///
/// BigInt drops leading zeroes, and a 31-byte key or shared secret breaks
/// every derivation that follows it.
Uint8List _unsignedBytes(BigInt value, int length) {
  final bytes = Uint8List(length);
  var remaining = value;
  for (var i = length - 1; i >= 0; i--) {
    bytes[i] = (remaining & BigInt.from(0xff)).toInt();
    remaining = remaining >> 8;
  }
  return bytes;
}
