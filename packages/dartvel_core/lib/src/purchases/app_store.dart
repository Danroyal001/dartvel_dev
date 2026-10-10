/// The App Store, verified on the server: StoreKit 2 signed transactions,
/// App Store Server Notifications v2, and promotional offer signatures.
///
/// A StoreKit 2 transaction is a JWS whose header carries the certificate
/// chain that signed it. The chain is the whole of the trust, so each link is
/// checked rather than assumed:
///
/// * The last certificate must be byte-for-byte a pinned root -- Apple Root
///   CA - G3 unless configured otherwise. A chain that is never compared with
///   a root accepts a signature from any certificate anybody can mint.
/// * The intermediate must be signed by that root and the leaf by that
///   intermediate. Comparing only the last certificate with the root would
///   accept a leaf from any chain that happened to end with Apple's root.
/// * Each must carry Apple's marker extension. Apple signs a great many
///   certificates; only the ones marked for receipt signing sign receipts.
/// * Each must be inside its validity period, now.
/// * The JWS itself must verify under the leaf's key, and its bundle id and
///   environment must be this application's.
///
/// No request goes to Apple to verify a transaction. The signature is
/// Apple's answer; asking again would trade a check that cannot be faked for
/// one that can be unreachable.
library dartvel.purchases.app_store;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../auth/webauthn.dart' show dvDecodeDerSignature;
import '../billing/money.dart';
import 'purchases.dart';

/// Apple's marker on the certificate that signs receipts and notifications.
const String _leafMarker = '1.2.840.113635.100.6.11.1';

/// Apple's marker on the intermediate that issues those certificates.
const String _intermediateMarker = '1.2.840.113635.100.6.2.1';

const String _ecPublicKey = '1.2.840.10045.2.1';
const String _ecdsaWithSha256 = '1.2.840.10045.4.3.2';
const String _ecdsaWithSha384 = '1.2.840.10045.4.3.3';

const Map<String, String> _curveNames = <String, String>{
  '1.2.840.10045.3.1.7': 'prime256v1',
  '1.3.132.0.34': 'secp384r1',
};

/// The App Store as a [DVStoreAdapter].
class DVAppStoreAdapter implements DVStoreAdapter, DVStoreOfferSigner {
  DVAppStoreAdapter({
    required this.bundleId,
    this.appAppleId,
    Set<String> environments = const <String>{'Production', 'Sandbox'},
    bool allowXcode = false,
    List<List<int>>? rootCertificates,
    DateTime Function()? clock,
    this.inAppKeyId,
    String? inAppPrivateKeyPem,
  })  : environments = <String>{...environments, if (allowXcode) 'Xcode'},
        _roots = <Uint8List>[
          for (final List<int> root
              in rootCertificates ?? <List<int>>[appleRootCaG3])
            Uint8List.fromList(root),
        ],
        _clock = clock ?? DateTime.now,
        _offerKey = inAppPrivateKeyPem == null
            ? null
            : dvEcPrivateScalarFromPkcs8Pem(inAppPrivateKeyPem) {
    if (_roots.isEmpty) {
      throw ArgumentError.value(rootCertificates, 'rootCertificates',
          'with no root, nothing can be verified');
    }
    if ((inAppKeyId == null) != (inAppPrivateKeyPem == null)) {
      throw ArgumentError('inAppKeyId and inAppPrivateKeyPem go together: a '
          'signature names the key it was made with');
    }
  }

  /// The application's bundle identifier. A transaction for any other is
  /// another application's purchase.
  final String bundleId;

  /// The App Store's id for the application, checked against notifications
  /// that carry one. Sandbox notifications do not.
  final int? appAppleId;

  /// The environments accepted. Production and Sandbox by default: App
  /// Review buys in the sandbox against the production build, and refusing
  /// it is a rejected submission. Xcode's local testing signs with a key of
  /// its own and is accepted only when asked for.
  final Set<String> environments;

  /// The In-App Purchase key id that signs promotional offers, or null.
  final String? inAppKeyId;

  final List<Uint8List> _roots;
  final DateTime Function() _clock;
  final Uint8List? _offerKey;

  /// Apple Root CA - G3, as Apple publishes it at
  /// https://www.apple.com/certificateauthority/AppleRootCA-G3.cer.
  /// SHA-256 fingerprint
  /// `63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179`;
  /// it expires on 30 April 2039.
  static final Uint8List appleRootCaG3 = base64.decode(
      'MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9v'
      'dCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UE'
      'CgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2'
      'WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmlj'
      'YXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqG'
      'SM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxE'
      'tX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNC'
      'MEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0P'
      'AQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3m'
      'eoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkL'
      'F1vLUagM6BgD56KyKA==');

  @override
  DVStore get store => DVStore.appStore;

  /// None: the App Store does not refund an unacknowledged purchase.
  @override
  Duration? get acknowledgementWindow => null;

  @override
  Future<void> acknowledge({
    required String originalTransactionId,
    required String transactionId,
    required String storeProductId,
  }) async {}

  @override
  Future<DVStoreTransaction> verifyReceipt(String receipt) async =>
      _transactionFrom(_verifiedPayload(receipt), renewal: null);

  @override
  Future<DVStoreNotification> verifyNotification(
    String body,
    Map<String, String> headers,
  ) async {
    final Object? signedPayload;
    try {
      final Object? decoded = jsonDecode(body);
      signedPayload = decoded is Map ? decoded['signedPayload'] : null;
    } on FormatException {
      throw DVStoreRefusal(store, 'the notification body is not JSON');
    }
    if (signedPayload is! String) {
      throw DVStoreRefusal(store, 'the notification has no signedPayload');
    }
    final Map<String, Object?> payload = _verifiedPayload(signedPayload);
    final String type = _string(payload, 'notificationType');
    final Object? subtype = payload['subtype'];
    final Map<String, Object?> data = _map(payload['data']);

    final Object? notifiedBundle = data['bundleId'];
    if (notifiedBundle != null && notifiedBundle != bundleId) {
      throw DVStoreRefusal(
          store, 'the notification is for bundle "$notifiedBundle"');
    }
    final Object? notifiedApp = data['appAppleId'];
    if (appAppleId != null && notifiedApp != null && notifiedApp != appAppleId) {
      throw DVStoreRefusal(store, 'the notification is for another app');
    }
    final Object? environment = data['environment'];
    if (environment != null && !environments.contains(environment)) {
      throw DVStoreRefusal(
          store, 'the notification is from the $environment environment');
    }

    if (type == 'TEST') {
      throw const DVStoreNothingToApply('an App Store TEST notification');
    }
    final Object? signedTransaction = data['signedTransactionInfo'];
    if (signedTransaction is! String) {
      throw DVStoreNothingToApply('a $type notification carries no transaction');
    }
    final Object? signedRenewal = data['signedRenewalInfo'];
    final Map<String, Object?>? renewal =
        signedRenewal is String ? _verifiedPayload(signedRenewal) : null;

    return DVStoreNotification(
      notificationId: _string(payload, 'notificationUUID'),
      type: subtype is String ? '$type/$subtype' : type,
      signedAt: _date(payload, 'signedDate')!,
      transaction:
          _transactionFrom(_verifiedPayload(signedTransaction), renewal: renewal),
    );
  }

  @override
  Future<DVStoreOfferSignature> signOffer({
    required String storeProductId,
    required String offerId,
    required String appAccountToken,
  }) async {
    final Uint8List? key = _offerKey;
    final String? keyId = inAppKeyId;
    if (key == null || keyId == null) {
      throw StateError(
          'No In-App Purchase key is configured, so no promotional offer can '
          'be signed. Pass inAppKeyId and inAppPrivateKeyPem (the .p8 from App '
          'Store Connect) to DVAppStoreAdapter.');
    }
    final String nonce = _uuidV4();
    final int timestamp = _clock().toUtc().millisecondsSinceEpoch;
    // Apple's payload: the fields joined by U+2063 INVISIBLE SEPARATOR, the
    // token and the nonce in lowercase.
    final String payload = <String>[
      bundleId,
      keyId,
      storeProductId,
      offerId,
      appAccountToken.toLowerCase(),
      nonce,
      '$timestamp',
    ].join('⁣');
    final ECDomainParameters domain = ECDomainParameters('prime256v1');
    final ECDSASigner signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true,
          PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(_unsigned(key), domain)));
    final ECSignature signature = signer
        .generateSignature(Uint8List.fromList(utf8.encode(payload))) as ECSignature;
    return DVStoreOfferSignature(
      keyId: keyId,
      nonce: nonce,
      timestamp: timestamp,
      signature: base64.encode(_derSignature(signature.r, signature.s)),
    );
  }

  // -- the transaction -------------------------------------------------------

  DVStoreTransaction _transactionFrom(
    Map<String, Object?> payload, {
    required Map<String, Object?>? renewal,
  }) {
    final Object? transactionBundle = payload['bundleId'];
    if (transactionBundle != bundleId) {
      throw DVStoreRefusal(
          store, 'the transaction is for bundle "$transactionBundle"');
    }
    final Object? environment = payload['environment'];
    if (environment is! String || !environments.contains(environment)) {
      throw DVStoreRefusal(
          store, 'the transaction is from the $environment environment');
    }
    DVMoney? price;
    final Object? amount = payload['price'];
    final Object? currency = payload['currency'];
    if (amount is int && currency is String) {
      try {
        price = DVStoreMoney.fromMilliunits(amount, currency);
      } on ArgumentError {
        // A price that is not whole minor units is shown as no price. It is
        // not a reason to refuse a purchase Apple signed.
        price = null;
      }
    }
    final DateTime purchasedAt = _date(payload, 'purchaseDate') ??
        (throw DVStoreRefusal(store, 'the transaction has no purchaseDate'));
    return DVStoreTransaction(
      store: store,
      originalTransactionId: _string(payload, 'originalTransactionId'),
      transactionId: _string(payload, 'transactionId'),
      storeProductId: _string(payload, 'productId'),
      purchasedAt: purchasedAt,
      signedAt: _date(payload, 'signedDate') ?? purchasedAt,
      expiresAt: _date(payload, 'expiresDate'),
      graceEndsAt:
          renewal == null ? null : _date(renewal, 'gracePeriodExpiresDate'),
      revokedAt: _date(payload, 'revocationDate'),
      appAccountToken: payload['appAccountToken'] as String?,
      // The App Store has nothing to acknowledge; finishing is the device's.
      acknowledged: true,
      price: price,
    );
  }

  String _string(Map<String, Object?> payload, String key) {
    final Object? value = payload[key];
    if (value is String && value.isNotEmpty) return value;
    if (value is int) return '$value';
    throw DVStoreRefusal(store, 'the signed payload has no $key');
  }

  DateTime? _date(Map<String, Object?> payload, String key) {
    final Object? value = payload[key];
    if (value == null) return null;
    if (value is! num) {
      throw DVStoreRefusal(store, '$key is not a timestamp');
    }
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }

  Map<String, Object?> _map(Object? value) => value is Map
      ? value.cast<String, Object?>()
      : throw DVStoreRefusal(store, 'the signed payload has no data');

  // -- the JWS ---------------------------------------------------------------

  /// [jws]'s payload, once its chain and signature have verified.
  Map<String, Object?> _verifiedPayload(String jws) {
    final List<String> parts = jws.split('.');
    if (parts.length != 3) {
      throw DVStoreRefusal(store, 'a signed transaction has three parts');
    }
    final Map<String, Object?> header;
    final Map<String, Object?> payload;
    final Uint8List signature;
    try {
      header = _jsonSegment(parts[0]);
      payload = _jsonSegment(parts[1]);
      signature = _base64UrlDecode(parts[2]);
    } on Object {
      throw DVStoreRefusal(store, 'the signed transaction is not readable');
    }
    if (header['alg'] != 'ES256') {
      throw DVStoreRefusal(store, 'the signature is not ES256');
    }
    final Object? x5c = header['x5c'];
    if (x5c is! List || x5c.length != 3 || x5c.any((Object? c) => c is! String)) {
      throw DVStoreRefusal(
          store, 'the signature does not carry a leaf, intermediate and root');
    }
    final List<_Certificate> chain;
    try {
      chain = <_Certificate>[
        for (final Object? encoded in x5c)
          _Certificate.parse(base64.decode(encoded! as String)),
      ];
    } on Object {
      throw DVStoreRefusal(store, 'a certificate in the chain is not readable');
    }
    _verifyChain(leaf: chain[0], intermediate: chain[1], root: chain[2]);

    if (signature.length != 64 || chain[0].curve != 'prime256v1') {
      throw DVStoreRefusal(store, 'the signature is not a P-256 signature');
    }
    final bool verified = _verifyEcdsa(
      publicKey: chain[0],
      digest: SHA256Digest(),
      message: utf8.encode('${parts[0]}.${parts[1]}'),
      r: _unsigned(signature.sublist(0, 32)),
      s: _unsigned(signature.sublist(32)),
    );
    if (!verified) {
      throw DVStoreRefusal(store, 'the transaction signature does not verify');
    }
    return payload;
  }

  void _verifyChain({
    required _Certificate leaf,
    required _Certificate intermediate,
    required _Certificate root,
  }) {
    if (!_roots.any((Uint8List pinned) => _equalBytes(pinned, root.der))) {
      throw DVStoreRefusal(
          store, 'the chain does not end in a pinned Apple root');
    }
    if (!_signedBy(intermediate, root)) {
      throw DVStoreRefusal(store, 'the intermediate is not signed by the root');
    }
    if (!_signedBy(leaf, intermediate)) {
      throw DVStoreRefusal(
          store, 'the leaf is not signed by the intermediate');
    }
    if (!intermediate.extensions.contains(_intermediateMarker)) {
      throw DVStoreRefusal(
          store, 'the intermediate does not carry Apple\'s marker');
    }
    if (!leaf.extensions.contains(_leafMarker)) {
      throw DVStoreRefusal(store,
          'the leaf does not carry Apple\'s receipt-signing marker');
    }
    final DateTime now = _clock().toUtc();
    for (final _Certificate certificate in <_Certificate>[leaf, intermediate, root]) {
      if (now.isBefore(certificate.notBefore) ||
          now.isAfter(certificate.notAfter)) {
        throw DVStoreRefusal(store,
            'a certificate in the chain is not valid now (valid '
            '${certificate.notBefore.toIso8601String()} to '
            '${certificate.notAfter.toIso8601String()})');
      }
    }
  }

  bool _signedBy(_Certificate subject, _Certificate issuer) {
    if (!_equalBytes(subject.issuer, issuer.subject)) return false;
    final Digest digest = switch (subject.signatureAlgorithm) {
      _ecdsaWithSha256 => SHA256Digest(),
      _ecdsaWithSha384 => SHA384Digest(),
      _ => throw DVStoreRefusal(store,
          'a certificate is signed with ${subject.signatureAlgorithm}'),
    };
    final ({BigInt r, BigInt s})? parsed =
        dvDecodeDerSignature(subject.signature);
    if (parsed == null) return false;
    return _verifyEcdsa(
      publicKey: issuer,
      digest: digest,
      message: subject.tbs,
      r: parsed.r,
      s: parsed.s,
    );
  }

  static bool _verifyEcdsa({
    required _Certificate publicKey,
    required Digest digest,
    required List<int> message,
    required BigInt r,
    required BigInt s,
  }) {
    try {
      final ECDomainParameters domain = ECDomainParameters(publicKey.curve);
      final ECDSASigner verifier = ECDSASigner(digest)
        ..init(
          false,
          PublicKeyParameter<ECPublicKey>(
            ECPublicKey(domain.curve.decodePoint(publicKey.publicKey), domain),
          ),
        );
      return verifier.verifySignature(
          Uint8List.fromList(message), ECSignature(r, s));
    } on Object {
      // Attacker-supplied bytes: a malformed key or signature is a refusal.
      return false;
    }
  }

  static Map<String, Object?> _jsonSegment(String segment) =>
      (jsonDecode(utf8.decode(_base64UrlDecode(segment))) as Map<Object?, Object?>)
          .cast<String, Object?>();

  static Uint8List _base64UrlDecode(String value) =>
      base64Url.decode(value.padRight(value.length + (4 - value.length % 4) % 4, '='));

  static final Random _random = Random.secure();

  static String _uuidV4() {
    final List<int> bytes =
        List<int>.generate(16, (int index) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final String hex =
        bytes.map((int byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// The 32-byte private scalar of a PKCS#8 P-256 key, such as App Store
/// Connect's `.p8` In-App Purchase key.
Uint8List dvEcPrivateScalarFromPkcs8Pem(String pem) {
  final String body = pem
      .split('\n')
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty && !line.startsWith('-----'))
      .join();
  final _DerReader outer = _DerReader(base64.decode(body)).enter(0x30);
  outer.next(0x02); // version
  final _DerReader algorithm = outer.enter(0x30);
  if (_DerReader.oid(algorithm.next(0x06)) != _ecPublicKey) {
    throw const FormatException('the key is not an EC key');
  }
  if (_DerReader.oid(algorithm.next(0x06)) != '1.2.840.10045.3.1.7') {
    throw const FormatException('the key is not a P-256 key');
  }
  final _DerReader ecKey = _DerReader(outer.next(0x04)).enter(0x30);
  ecKey.next(0x02); // version
  final Uint8List scalar = ecKey.next(0x04);
  if (scalar.length > 32) throw const FormatException('the key is too long');
  return Uint8List(32)..setRange(32 - scalar.length, 32, scalar);
}

BigInt _unsigned(List<int> bytes) {
  BigInt result = BigInt.zero;
  for (final int byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

bool _equalBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// `SEQUENCE { INTEGER r, INTEGER s }`, as Apple expects an offer signature.
Uint8List _derSignature(BigInt r, BigInt s) {
  List<int> integer(BigInt value) {
    final List<int> bytes = <int>[];
    BigInt remaining = value;
    while (remaining > BigInt.zero) {
      bytes.insert(0, (remaining & BigInt.from(0xff)).toInt());
      remaining = remaining >> 8;
    }
    if (bytes.isEmpty) bytes.add(0);
    if (bytes.first & 0x80 != 0) bytes.insert(0, 0);
    return <int>[0x02, bytes.length, ...bytes];
  }

  final List<int> content = <int>[...integer(r), ...integer(s)];
  return Uint8List.fromList(<int>[0x30, ..._DerReader.length(content.length), ...content]);
}

/// The parts of an X.509 certificate a chain check reads.
class _Certificate {
  _Certificate({
    required this.der,
    required this.tbs,
    required this.issuer,
    required this.subject,
    required this.notBefore,
    required this.notAfter,
    required this.curve,
    required this.publicKey,
    required this.signatureAlgorithm,
    required this.signature,
    required this.extensions,
  });

  final Uint8List der;

  /// The signed bytes: the TBSCertificate's whole encoding.
  final Uint8List tbs;
  final Uint8List issuer;
  final Uint8List subject;
  final DateTime notBefore;
  final DateTime notAfter;
  final String curve;
  final Uint8List publicKey;
  final String signatureAlgorithm;
  final Uint8List signature;

  /// The extension OIDs present.
  final Set<String> extensions;

  static _Certificate parse(Uint8List der) {
    final _DerReader certificate = _DerReader(der).enter(0x30);
    final Uint8List tbsBytes = certificate.raw(0x30);
    final _DerReader algorithm = certificate.enter(0x30);
    final String signatureAlgorithm = _DerReader.oid(algorithm.next(0x06));
    final Uint8List bits = certificate.next(0x03);

    final _DerReader tbs = _DerReader(tbsBytes).enter(0x30);
    if (tbs.peek == 0xa0) tbs.next(0xa0); // version
    tbs.next(0x02); // serial
    tbs.next(0x30); // signature algorithm, repeated
    final Uint8List issuer = tbs.raw(0x30);
    final _DerReader validity = tbs.enter(0x30);
    final DateTime notBefore = _DerReader.time(validity);
    final DateTime notAfter = _DerReader.time(validity);
    final Uint8List subject = tbs.raw(0x30);
    final _DerReader keyInfo = tbs.enter(0x30);
    final _DerReader keyAlgorithm = keyInfo.enter(0x30);
    if (_DerReader.oid(keyAlgorithm.next(0x06)) != _ecPublicKey) {
      throw const FormatException('not an EC key');
    }
    final String? curve = _curveNames[_DerReader.oid(keyAlgorithm.next(0x06))];
    if (curve == null) throw const FormatException('an unknown curve');
    final Uint8List keyBits = keyInfo.next(0x03);

    final Set<String> extensions = <String>{};
    while (tbs.hasMore) {
      final int tag = tbs.peek;
      if (tag != 0xa3) {
        tbs.next(tag);
        continue;
      }
      final _DerReader list = _DerReader(tbs.next(0xa3)).enter(0x30);
      while (list.hasMore) {
        final _DerReader extension = list.enter(0x30);
        extensions.add(_DerReader.oid(extension.next(0x06)));
      }
    }
    return _Certificate(
      der: der,
      tbs: tbsBytes,
      issuer: issuer,
      subject: subject,
      notBefore: notBefore,
      notAfter: notAfter,
      curve: curve,
      publicKey: keyBits.sublist(1),
      signatureAlgorithm: signatureAlgorithm,
      signature: bits.sublist(1),
      extensions: extensions,
    );
  }
}

/// A forward reader over DER: tag, length, value. Only what certificates
/// and keys need, and strict, because every byte here came from outside.
class _DerReader {
  _DerReader(this._bytes) : _end = _bytes.length;

  final Uint8List _bytes;
  final int _end;
  int _offset = 0;

  bool get hasMore => _offset < _end;
  int get peek => hasMore ? _bytes[_offset] : -1;

  /// The next element's (start, contentStart, end), checked against [tag].
  (int, int, int) _element(int tag) {
    if (!hasMore || _bytes[_offset] != tag) {
      throw FormatException('expected tag 0x${tag.toRadixString(16)}');
    }
    final int start = _offset;
    int cursor = _offset + 1;
    if (cursor >= _end) throw const FormatException('truncated');
    int length = _bytes[cursor++];
    if (length & 0x80 != 0) {
      final int count = length & 0x7f;
      if (count == 0 || count > 4 || cursor + count > _end) {
        throw const FormatException('a bad length');
      }
      length = 0;
      for (int index = 0; index < count; index++) {
        length = (length << 8) | _bytes[cursor++];
      }
    }
    if (cursor + length > _end) throw const FormatException('truncated');
    _offset = cursor + length;
    return (start, cursor, cursor + length);
  }

  /// The next element's content.
  Uint8List next(int tag) {
    final (int _, int content, int end) = _element(tag);
    return Uint8List.sublistView(_bytes, content, end);
  }

  /// The next element's whole encoding, tag and length included.
  Uint8List raw(int tag) {
    final (int start, int _, int end) = _element(tag);
    return Uint8List.sublistView(_bytes, start, end);
  }

  /// A reader over the next element's content.
  _DerReader enter(int tag) => _DerReader(next(tag));

  static List<int> length(int value) {
    if (value < 0x80) return <int>[value];
    final List<int> bytes = <int>[];
    int remaining = value;
    while (remaining > 0) {
      bytes.insert(0, remaining & 0xff);
      remaining >>= 8;
    }
    return <int>[0x80 | bytes.length, ...bytes];
  }

  static String oid(Uint8List bytes) {
    if (bytes.isEmpty) throw const FormatException('an empty OID');
    final List<int> parts = <int>[bytes[0] ~/ 40, bytes[0] % 40];
    int value = 0;
    for (int index = 1; index < bytes.length; index++) {
      value = (value << 7) | (bytes[index] & 0x7f);
      if (bytes[index] & 0x80 == 0) {
        parts.add(value);
        value = 0;
      }
    }
    return parts.join('.');
  }

  /// A UTCTime or GeneralizedTime, in UTC.
  static DateTime time(_DerReader reader) {
    final int tag = reader.peek;
    final String text = ascii.decode(reader.next(tag));
    final RegExpMatch? match =
        RegExp(r'^(\d{2,4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$').firstMatch(text);
    if (match == null || (tag != 0x17 && tag != 0x18)) {
      throw FormatException('not a certificate time', text);
    }
    int year = int.parse(match[1]!);
    if (tag == 0x17) year += year < 50 ? 2000 : 1900;
    return DateTime.utc(year, int.parse(match[2]!), int.parse(match[3]!),
        int.parse(match[4]!), int.parse(match[5]!), int.parse(match[6]!));
  }
}
