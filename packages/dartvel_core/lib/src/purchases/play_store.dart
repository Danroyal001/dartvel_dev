/// Google Play as a [DVStoreAdapter]: the Play Developer API for what a
/// purchase token bought, and Real-Time Developer Notifications delivered
/// through a Pub/Sub push subscription.
///
/// A purchase token is only a name. What it bought, until when, for which
/// application account and whether it still stands are read back from
/// Google with the service account's own access token, so nothing the device
/// sent is believed except the token itself.
///
/// A push is believed only when Google signed it for this endpoint. Pub/Sub
/// attaches an OIDC token to each push it makes for a subscription configured
/// with a service account; this checks its signature against Google's
/// published keys, its audience against this endpoint and its email against
/// that service account. An unsigned "revoked" takes a customer's access
/// away, so there is no configuration that accepts one.
///
/// A notification only says that something changed. What changed is read
/// again from the Developer API, as Google's own reference tells a backend to
/// do, so a notification type Dartvel has never heard of still lands
/// correctly.
library dartvel.purchases.play_store;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

import '../billing/webhooks.dart' show DVBillingFetch;
import 'purchases.dart';

/// Decodes a PKCS#8 (`BEGIN PRIVATE KEY`) or PKCS#1 (`BEGIN RSA PRIVATE
/// KEY`) PEM into an RSA private key: the `private_key` of a Google service
/// account JSON file is the first.
RSAPrivateKey dvRsaPrivateKeyFromPem(String pem) {
  final bool pkcs1 = pem.contains('BEGIN RSA PRIVATE KEY');
  final Uint8List der = base64.decode(
      pem.replaceAll(RegExp(r'-----[^-]+-----'), '').replaceAll(RegExp(r'\s'), ''));
  ASN1Sequence key = ASN1Parser(der).nextObject() as ASN1Sequence;
  if (!pkcs1) {
    // PrivateKeyInfo: version, algorithm, then the PKCS#1 key as an octet
    // string.
    final ASN1OctetString inner = key.elements![2] as ASN1OctetString;
    key = ASN1Parser(inner.valueBytes ?? inner.octets!).nextObject()
        as ASN1Sequence;
  }
  BigInt integer(int index) => (key.elements![index] as ASN1Integer).integer!;
  return RSAPrivateKey(integer(1), integer(3), integer(4), integer(5));
}

/// RSASSA-PKCS1-v1_5 with SHA-256 over [message]: the `RS256` of a JWT.
Uint8List dvRs256Sign(RSAPrivateKey key, List<int> message) {
  final RSASigner signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(key));
  return signer.generateSignature(Uint8List.fromList(message)).bytes;
}

bool _rs256Verify(RSAPublicKey key, List<int> message, List<int> signature) {
  final RSASigner signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(false, PublicKeyParameter<RSAPublicKey>(key));
  try {
    return signer.verifySignature(
        Uint8List.fromList(message), RSASignature(Uint8List.fromList(signature)));
  } on Object {
    return false;
  }
}

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

List<int> _fromBase64Url(String text) =>
    base64Url.decode(base64Url.normalize(text));

BigInt _bigInt(List<int> bytes) {
  BigInt value = BigInt.zero;
  for (final int byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

/// Google Play's server-side verification and notifications.
class DVPlayStoreAdapter implements DVStoreAdapter, DVStoreCatalogAware {
  DVPlayStoreAdapter({
    required this.packageName,
    String? serviceAccountEmail,
    String? serviceAccountPrivateKeyPem,
    Future<String> Function()? accessToken,
    DVBillingFetch? fetch,
    DateTime Function()? clock,
    this.pushAudience,
    this.pushServiceAccountEmail,
  })  : _serviceAccountEmail = serviceAccountEmail,
        _serviceAccountKey = serviceAccountPrivateKeyPem == null
            ? null
            : dvRsaPrivateKeyFromPem(serviceAccountPrivateKeyPem),
        _injectedToken = accessToken,
        _fetch = fetch ?? _noNetwork,
        _clock = clock ?? DateTime.now {
    if (accessToken == null &&
        (serviceAccountEmail == null || serviceAccountPrivateKeyPem == null)) {
      throw ArgumentError(
          'DVPlayStoreAdapter needs a service account (email and private '
          'key) or an accessToken function to call the Play Developer API');
    }
  }

  /// The application id, which every Developer API path and every
  /// notification names.
  final String packageName;

  /// The push endpoint's URL as configured on the Pub/Sub subscription, which
  /// is the audience of the OIDC token Google attaches. Null refuses every
  /// push.
  final String? pushAudience;

  /// The service account the Pub/Sub subscription pushes as.
  final String? pushServiceAccountEmail;

  final String? _serviceAccountEmail;
  final RSAPrivateKey? _serviceAccountKey;
  final Future<String> Function()? _injectedToken;
  final DVBillingFetch _fetch;
  final DateTime Function() _clock;

  static const String _scope = 'https://www.googleapis.com/auth/androidpublisher';
  static final Uri _tokenUri = Uri.parse('https://oauth2.googleapis.com/token');
  static final Uri _certificatesUri =
      Uri.parse('https://www.googleapis.com/oauth2/v3/certs');

  static Future<(int, String)> _noNetwork(
          String m, Uri u, Map<String, String> h, String? b) =>
      throw const DVStoreUnavailable(
          'No HTTP transport was configured for Google Play.');

  @override
  DVStore get store => DVStore.play;

  /// Play refunds a purchase not acknowledged within three days.
  @override
  Duration? get acknowledgementWindow => const Duration(days: 3);

  final Map<String, DVPurchaseKind> _catalog = <String, DVPurchaseKind>{};

  @override
  void useCatalog(Map<String, DVPurchaseKind> storeProducts) {
    _catalog
      ..clear()
      ..addAll(storeProducts);
  }

  // -- access tokens -----------------------------------------------------------

  String? _token;
  DateTime? _tokenExpires;

  /// A live access token, minted from the service account and reused until a
  /// minute before it ends.
  Future<String> _accessToken({bool fresh = false}) async {
    final Future<String> Function()? injected = _injectedToken;
    if (injected != null) return injected();
    final DateTime now = _clock().toUtc();
    final String? held = _token;
    final DateTime? expires = _tokenExpires;
    if (!fresh &&
        held != null &&
        expires != null &&
        now.isBefore(expires.subtract(const Duration(seconds: 60)))) {
      return held;
    }
    final int issued = now.millisecondsSinceEpoch ~/ 1000;
    final String header = _base64Url(
        utf8.encode(jsonEncode(<String, Object?>{'alg': 'RS256', 'typ': 'JWT'})));
    final String claims = _base64Url(utf8.encode(jsonEncode(<String, Object?>{
      'iss': _serviceAccountEmail,
      'scope': _scope,
      'aud': _tokenUri.toString(),
      'iat': issued,
      'exp': issued + 3600,
    })));
    final String signature = _base64Url(
        dvRs256Sign(_serviceAccountKey!, utf8.encode('$header.$claims')));
    final String body = <String, String>{
      'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      'assertion': '$header.$claims.$signature',
    }
        .entries
        .map((MapEntry<String, String> e) =>
            '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final (int status, String text) = await _send('POST', _tokenUri,
        <String, String>{'content-type': 'application/x-www-form-urlencoded'},
        body);
    if (status != 200) {
      // Google's answer is not repeated: an error that gets pasted into a
      // ticket must not carry anything that signs for the account.
      throw DVStoreUnavailable(
          'Google refused the service account token request ($status)');
    }
    final Map<String, Object?> json = _object(text);
    final Object? token = json['access_token'];
    if (token is! String) {
      throw const DVStoreUnavailable('Google issued no access token');
    }
    final Object? lifetime = json['expires_in'];
    _token = token;
    _tokenExpires =
        now.add(Duration(seconds: lifetime is int ? lifetime : 3600));
    return token;
  }

  Future<(int, String)> _send(
      String method, Uri url, Map<String, String> headers, String? body) async {
    try {
      return await _fetch(method, url, headers, body);
    } on DVStoreUnavailable {
      rethrow;
    } on Object catch (error) {
      throw DVStoreUnavailable(
          'Google could not be reached (${error.runtimeType})');
    }
  }

  /// A Developer API call with the access token, minted again once when
  /// Google no longer accepts the one held.
  Future<(int, String)> _api(String method, String path) async {
    final Uri url = Uri.https('androidpublisher.googleapis.com',
        '/androidpublisher/v3/applications/$packageName/purchases/$path');
    (int, String) answer = await _send(method, url,
        <String, String>{'authorization': 'Bearer ${await _accessToken()}'},
        method == 'POST' ? '' : null);
    if (answer.$1 == 401 && _injectedToken == null) {
      answer = await _send(method, url,
          <String, String>{
            'authorization': 'Bearer ${await _accessToken(fresh: true)}'
          },
          method == 'POST' ? '' : null);
    }
    return answer;
  }

  /// The body of a 200, a refusal for what Google says does not exist, and
  /// an outage for everything else.
  Future<Map<String, Object?>> _read(String path) async {
    final (int status, String text) = await _api('GET', path);
    if (status == 200) return _object(text);
    if (status == 400 || status == 404 || status == 410) {
      throw const DVStoreRefusal(
          DVStore.play, 'Google has no record of this purchase token');
    }
    throw DVStoreUnavailable('the Play Developer API answered $status');
  }

  // -- reading purchases -----------------------------------------------------

  @override
  Future<DVStoreTransaction> verifyReceipt(String receipt) async {
    final Map<String, Object?> json;
    try {
      json = _object(receipt);
    } on FormatException {
      throw const DVStoreRefusal(DVStore.play, 'the receipt is not readable');
    }
    final Object? token = json['purchaseToken'];
    final Object? productId = json['productId'];
    final Object? type = json['type'];
    if (token is! String || token.isEmpty) {
      throw const DVStoreRefusal(DVStore.play, 'the receipt has no token');
    }
    if (type == 'subs') return _subscription(token);
    if (productId is! String || productId.isEmpty) {
      throw const DVStoreRefusal(
          DVStore.play, 'a one-time receipt must name its product');
    }
    return _oneTime(token, productId);
  }

  /// `purchases.subscriptionsv2.get`, which needs no product id.
  Future<DVStoreTransaction> _subscription(String token,
      {DateTime? revokedAt, DateTime? signedAt}) async {
    final Map<String, Object?> json =
        await _read('subscriptionsv2/tokens/${Uri.encodeComponent(token)}');
    final String? state = json['subscriptionState'] as String?;
    if (state == 'SUBSCRIPTION_STATE_PENDING') {
      throw const DVStoreRefusal(DVStore.play, 'the payment is still pending');
    }
    if (state == 'SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED') {
      throw const DVStoreRefusal(
          DVStore.play, 'the pending purchase was canceled before it was paid');
    }
    final List<Object?> items =
        (json['lineItems'] as List<Object?>?) ?? const <Object?>[];
    if (items.isEmpty) {
      throw const DVStoreRefusal(DVStore.play, 'the subscription has no items');
    }
    final Map<String, Object?> item =
        (items.first! as Map<Object?, Object?>).cast<String, Object?>();
    final Object? product = item['productId'];
    if (product is! String) {
      throw const DVStoreRefusal(
          DVStore.play, 'the subscription names no product');
    }
    final DateTime now = _clock().toUtc();
    final Map<Object?, Object?>? accounts =
        json['externalAccountIdentifiers'] as Map<Object?, Object?>?;
    return DVStoreTransaction(
      store: DVStore.play,
      originalTransactionId: token,
      transactionId: (item['latestSuccessfulOrderId'] as String?) ??
          (json['latestOrderId'] as String?) ??
          token,
      storeProductId: product,
      purchasedAt: _time(json['startTime']) ?? now,
      signedAt: signedAt ?? now,
      expiresAt: _time(item['expiryTime']) ?? now,
      revokedAt: revokedAt,
      appAccountToken: accounts?['obfuscatedExternalAccountId'] as String?,
      acknowledged:
          json['acknowledgementState'] == 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
    );
  }

  /// `purchases.products.get`, for a consumable or a non-consumable.
  Future<DVStoreTransaction> _oneTime(String token, String productId,
      {DateTime? revokedAt, DateTime? signedAt}) async {
    final Map<String, Object?> json = await _read(
        'products/${Uri.encodeComponent(productId)}/tokens/${Uri.encodeComponent(token)}');
    final Object? state = json['purchaseState'];
    if (state == 2) {
      throw const DVStoreRefusal(DVStore.play, 'the payment is still pending');
    }
    final DateTime now = _clock().toUtc();
    final Object? millis = json['purchaseTimeMillis'];
    final int? purchased =
        millis is int ? millis : int.tryParse('${millis ?? ''}');
    return DVStoreTransaction(
      store: DVStore.play,
      originalTransactionId: token,
      transactionId: (json['orderId'] as String?) ?? token,
      storeProductId: productId,
      purchasedAt: purchased == null
          ? now
          : DateTime.fromMillisecondsSinceEpoch(purchased, isUtc: true),
      signedAt: signedAt ?? now,
      // 1 is Canceled: Play took it back.
      revokedAt: revokedAt ?? (state == 1 ? signedAt ?? now : null),
      appAccountToken: json['obfuscatedExternalAccountId'] as String?,
      acknowledged: json['acknowledgementState'] == 1,
    );
  }

  @override
  Future<void> acknowledge({
    required String originalTransactionId,
    required String transactionId,
    required String storeProductId,
  }) async {
    final bool subscription = (_catalog[storeProductId] ??
            DVPurchaseKind.subscription) ==
        DVPurchaseKind.subscription;
    final String path = '${subscription ? 'subscriptions' : 'products'}/'
        '${Uri.encodeComponent(storeProductId)}/tokens/'
        '${Uri.encodeComponent(originalTransactionId)}:acknowledge';
    final (int status, String _) = await _api('POST', path);
    if (status < 200 || status >= 300) {
      throw DVStoreUnavailable('Play did not take the acknowledgement ($status)');
    }
  }

  // -- notifications -----------------------------------------------------------

  @override
  Future<DVStoreNotification> verifyNotification(
    String body,
    Map<String, String> headers,
  ) async {
    await _authenticatePush(headers);

    final Map<String, Object?> envelope;
    final Map<String, Object?> message;
    final Map<String, Object?> event;
    try {
      envelope = _object(body);
      message = (envelope['message']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      event = _object(utf8.decode(base64.decode(message['data']! as String)));
    } on Object {
      throw const DVStoreRefusal(DVStore.play, 'the push body is not readable');
    }
    if (event['packageName'] != packageName) {
      throw const DVStoreRefusal(
          DVStore.play, 'the notification is for another application');
    }
    final String messageId = '${message['messageId'] ?? message['message_id'] ?? ''}';
    if (messageId.isEmpty) {
      throw const DVStoreRefusal(DVStore.play, 'the push has no message id');
    }
    final Object? millis = event['eventTimeMillis'];
    final int? eventMillis =
        millis is int ? millis : int.tryParse('${millis ?? ''}');
    final DateTime eventAt = eventMillis == null
        ? _clock().toUtc()
        : DateTime.fromMillisecondsSinceEpoch(eventMillis, isUtc: true);

    Map<String, Object?>? part(String name) =>
        (event[name] as Map<Object?, Object?>?)?.cast<String, Object?>();

    if (part('testNotification') != null) {
      throw const DVStoreNothingToApply('a Play test notification');
    }

    final Map<String, Object?>? subscription = part('subscriptionNotification');
    if (subscription != null) {
      final Object? type = subscription['notificationType'];
      final String token = subscription['purchaseToken']! as String;
      return DVStoreNotification(
        notificationId: messageId,
        type: 'subscription:$type',
        signedAt: eventAt,
        transaction: await _subscription(token,
            // 12 is SUBSCRIPTION_REVOKED: refunded or taken back before the
            // period ended, which reads the same as an expiry on the API.
            revokedAt: type == 12 ? eventAt : null,
            signedAt: eventAt),
      );
    }

    final Map<String, Object?>? oneTime = part('oneTimeProductNotification');
    if (oneTime != null) {
      return DVStoreNotification(
        notificationId: messageId,
        type: 'oneTime:${oneTime['notificationType']}',
        signedAt: eventAt,
        transaction: await _oneTime(
            oneTime['purchaseToken']! as String, oneTime['sku']! as String,
            signedAt: eventAt),
      );
    }

    final Map<String, Object?>? voided = part('voidedPurchaseNotification');
    if (voided != null) {
      final String token = voided['purchaseToken']! as String;
      final DVStoreTransaction transaction = voided['productType'] == 1
          ? await _subscription(token, revokedAt: eventAt, signedAt: eventAt)
          : await _voidedOneTime(token, eventAt);
      return DVStoreNotification(
        notificationId: messageId,
        type: 'voided',
        signedAt: eventAt,
        transaction: transaction,
      );
    }

    throw const DVStoreNothingToApply(
        'a Play notification that describes no purchase');
  }

  /// A voided one-time purchase, which names its token and not its product.
  ///
  /// `purchases.products.get` needs the product, so each one-time product the
  /// application declares is asked in turn until Google recognises the token.
  /// An application sells few, and a refund is rare enough to afford it.
  Future<DVStoreTransaction> _voidedOneTime(String token, DateTime eventAt) async {
    for (final MapEntry<String, DVPurchaseKind> entry in _catalog.entries) {
      if (entry.value == DVPurchaseKind.subscription) continue;
      try {
        return await _oneTime(token, entry.key,
            revokedAt: eventAt, signedAt: eventAt);
      } on DVStoreRefusal {
        continue;
      }
    }
    throw const DVStoreNothingToApply(
        'a voided purchase of no product this application declares');
  }

  // -- push authentication ------------------------------------------------------

  final Map<String, RSAPublicKey> _googleKeys = <String, RSAPublicKey>{};

  Future<void> _authenticatePush(Map<String, String> headers) async {
    final String? audience = pushAudience;
    final String? email = pushServiceAccountEmail;
    if (audience == null || email == null) {
      throw const DVStoreRefusal(
          DVStore.play,
          'push authentication is not configured (pushAudience and '
          'pushServiceAccountEmail), so no notification can be believed');
    }
    String? authorization;
    for (final MapEntry<String, String> header in headers.entries) {
      if (header.key.toLowerCase() == 'authorization') {
        authorization = header.value;
      }
    }
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      throw const DVStoreRefusal(DVStore.play, 'the push is not signed');
    }
    final List<String> parts =
        authorization.substring('Bearer '.length).trim().split('.');
    if (parts.length != 3) {
      throw const DVStoreRefusal(DVStore.play, 'the push token is malformed');
    }
    final Map<String, Object?> header;
    final Map<String, Object?> claims;
    final List<int> signature;
    try {
      header = _object(utf8.decode(_fromBase64Url(parts[0])));
      claims = _object(utf8.decode(_fromBase64Url(parts[1])));
      signature = _fromBase64Url(parts[2]);
    } on Object {
      throw const DVStoreRefusal(DVStore.play, 'the push token is malformed');
    }
    if (header['alg'] != 'RS256') {
      throw const DVStoreRefusal(
          DVStore.play, 'the push token is not signed RS256');
    }
    final RSAPublicKey? key = await _googleKey('${header['kid'] ?? ''}');
    if (key == null ||
        !_rs256Verify(key, utf8.encode('${parts[0]}.${parts[1]}'), signature)) {
      throw const DVStoreRefusal(
          DVStore.play, 'the push token was not signed by Google');
    }
    final Object? issuer = claims['iss'];
    if (issuer != 'accounts.google.com' &&
        issuer != 'https://accounts.google.com') {
      throw const DVStoreRefusal(
          DVStore.play, 'the push token was not issued by Google');
    }
    if (claims['aud'] != audience) {
      throw const DVStoreRefusal(
          DVStore.play, 'the push token is for another endpoint');
    }
    if (claims['email'] != email || claims['email_verified'] != true) {
      throw const DVStoreRefusal(
          DVStore.play, 'the push came from another service account');
    }
    final Object? expires = claims['exp'];
    final int nowSeconds = _clock().toUtc().millisecondsSinceEpoch ~/ 1000;
    if (expires is! int || expires <= nowSeconds) {
      throw const DVStoreRefusal(DVStore.play, 'the push token has expired');
    }
  }

  /// Google's signing key [kid], fetched again when it is one not yet seen:
  /// Google rotates them, and a cache that never refreshed would refuse every
  /// push after the next rotation.
  Future<RSAPublicKey?> _googleKey(String kid) async {
    final RSAPublicKey? held = _googleKeys[kid];
    if (held != null) return held;
    final (int status, String text) =
        await _send('GET', _certificatesUri, const <String, String>{}, null);
    if (status != 200) {
      throw DVStoreUnavailable("Google's signing keys could not be read ($status)");
    }
    final Object? keys = _object(text)['keys'];
    if (keys is List) {
      for (final Object? entry in keys) {
        if (entry is! Map) continue;
        final Object? id = entry['kid'];
        final Object? modulus = entry['n'];
        final Object? exponent = entry['e'];
        if (id is! String || modulus is! String || exponent is! String) continue;
        _googleKeys[id] = RSAPublicKey(
            _bigInt(_fromBase64Url(modulus)), _bigInt(_fromBase64Url(exponent)));
      }
    }
    return _googleKeys[kid];
  }

  // -- helpers -----------------------------------------------------------------

  static Map<String, Object?> _object(String text) {
    final Object? decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('not a JSON object');
    return decoded.cast<String, Object?>();
  }

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}
