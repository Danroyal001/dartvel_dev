// Google Play as a store adapter: the Developer API for what a purchase
// token is, and Real-Time Developer Notifications through Pub/Sub push.
//
// What has to be right here is who is believed. A purchase token is only a
// name; what it bought, until when and for whom is read back from Google
// with the service account's own token. A push is believed only when Google
// signed it for this endpoint: an unsigned "subscription revoked" is how
// somebody takes away a customer's access, and an unsigned "purchased" is how
// they would give themselves one. A refund on Play arrives as a voided
// purchase that does not say which product it was, and a consumable that is
// never told apart from a subscription is acknowledged at the wrong
// endpoint, refused, and refunded three days later.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

const String packageName = 'com.example.app';
const String serviceAccount = 'play@example.iam.gserviceaccount.com';
const String pushAccount = 'push@example.iam.gserviceaccount.com';
const String pushAudience = 'https://example.com/_dartvel/purchases/notifications/play';

const Entitlement pro = Entitlement('pro');

const DVPurchaseProduct monthly = DVPurchaseProduct(
  'pro_monthly',
  billable: DVBillable.digital(play: 'pro'),
  entitlements: <Entitlement>{pro},
);

const DVPurchaseProduct coins = DVPurchaseProduct(
  'coins_100',
  billable: DVBillable.digital(play: 'coins'),
  entitlements: <Entitlement>{},
  kind: DVPurchaseKind.consumable,
);

const DVPurchaseProduct lifetime = DVPurchaseProduct(
  'lifetime',
  billable: DVBillable.digital(play: 'lifetime'),
  entitlements: <Entitlement>{Entitlement('exports')},
  kind: DVPurchaseKind.nonConsumable,
);

String fixture(String name) =>
    File('test/fixtures/play_store/$name').readAsStringSync();

final RSAPrivateKey serviceKey =
    dvRsaPrivateKeyFromPem(fixture('service_account_test_key.pem'));
final RSAPrivateKey googleKey =
    dvRsaPrivateKeyFromPem(fixture('google_signer_test_key.pem'));
final RSAPrivateKey forgerKey =
    dvRsaPrivateKeyFromPem(fixture('forger_test_key.pem'));

final DateTime now = DateTime.utc(2026, 10, 9, 12);

String base64UrlOf(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

String bigIntBase64Url(BigInt value) {
  String hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final List<int> bytes = <int>[
    for (int i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  return base64UrlOf(bytes);
}

/// A JWT signed RS256 with [key].
String signJwt(RSAPrivateKey key, Map<String, Object?> claims,
    {String kid = 'google-1'}) {
  final String header = base64UrlOf(
      utf8.encode(jsonEncode(<String, Object?>{'alg': 'RS256', 'kid': kid, 'typ': 'JWT'})));
  final String payload = base64UrlOf(utf8.encode(jsonEncode(claims)));
  final Uint8List signature =
      dvRs256Sign(key, utf8.encode('$header.$payload'));
  return '$header.$payload.${base64UrlOf(signature)}';
}

bool verifyRs256(RSAPublicKey key, String jwt) {
  final List<String> parts = jwt.split('.');
  final RSASigner signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(false, PublicKeyParameter<RSAPublicKey>(key));
  try {
    return signer.verifySignature(
      Uint8List.fromList(utf8.encode('${parts[0]}.${parts[1]}')),
      RSASignature(base64Url.decode(base64Url.normalize(parts[2]))),
    );
  } on Object {
    return false;
  }
}

Map<String, Object?> claimsOf(String jwt) => (jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(jwt.split('.')[1]))))
    as Map<Object?, Object?>)
    .cast<String, Object?>();

/// Google, as far as the adapter can see it.
class FakeGoogle {
  int tokensMinted = 0;
  int certificateFetches = 0;
  String currentKid = 'google-1';
  bool unavailable = false;

  /// purchaseToken -> SubscriptionPurchaseV2.
  final Map<String, Map<String, Object?>> subscriptions =
      <String, Map<String, Object?>>{};

  /// 'productId token' -> ProductPurchase.
  final Map<String, Map<String, Object?>> oneTime =
      <String, Map<String, Object?>>{};
  final List<String> acknowledged = <String>[];
  final List<String> requests = <String>[];

  /// Access tokens Google issued and still accepts.
  final Set<String> liveTokens = <String>{};

  Future<(int, String)> fetch(
      String method, Uri url, Map<String, String> headers, String? body) async {
    requests.add('$method ${url.path}');
    if (unavailable) return (503, '{"error":"backend"}');
    if (url.host == 'oauth2.googleapis.com') {
      final Map<String, String> form = Uri.splitQueryString(body!);
      expect(form['grant_type'], 'urn:ietf:params:oauth:grant-type:jwt-bearer');
      final String assertion = form['assertion']!;
      final RSAPublicKey public =
          RSAPublicKey(serviceKey.modulus!, serviceKey.publicExponent!);
      if (!verifyRs256(public, assertion)) return (400, '{"error":"invalid_grant"}');
      final Map<String, Object?> claims = claimsOf(assertion);
      expect(claims['iss'], serviceAccount);
      expect(claims['scope'], 'https://www.googleapis.com/auth/androidpublisher');
      expect(claims['aud'], 'https://oauth2.googleapis.com/token');
      tokensMinted += 1;
      final String token = 'ya29.test-$tokensMinted';
      liveTokens.add(token);
      return (200, jsonEncode(<String, Object?>{
        'access_token': token,
        'expires_in': 3600,
        'token_type': 'Bearer',
      }));
    }
    if (url.host == 'www.googleapis.com' && url.path == '/oauth2/v3/certs') {
      certificateFetches += 1;
      return (200, jsonEncode(<String, Object?>{
        'keys': <Object?>[
          <String, Object?>{
            'kid': currentKid,
            'kty': 'RSA',
            'alg': 'RS256',
            'use': 'sig',
            'n': bigIntBase64Url(googleKey.modulus!),
            'e': bigIntBase64Url(googleKey.publicExponent!),
          },
        ],
      }));
    }
    expect(url.host, 'androidpublisher.googleapis.com');
    final String? bearer = headers['authorization'];
    if (bearer == null || !liveTokens.contains(bearer.replaceFirst('Bearer ', ''))) {
      return (401, '{"error":"unauthenticated"}');
    }
    final String prefix =
        '/androidpublisher/v3/applications/$packageName/purchases/';
    expect(url.path, startsWith(prefix));
    final List<String> rest = url.path.substring(prefix.length).split('/');
    if (method == 'POST' && url.path.endsWith(':acknowledge')) {
      acknowledged.add(url.path.substring(prefix.length));
      return (200, '{}');
    }
    if (rest[0] == 'subscriptionsv2') {
      final Map<String, Object?>? found = subscriptions[rest[2]];
      return found == null ? (404, '{"error":"not found"}') : (200, jsonEncode(found));
    }
    if (rest[0] == 'products') {
      final Map<String, Object?>? found = oneTime['${rest[1]} ${rest[3]}'];
      return found == null ? (400, '{"error":"invalid"}') : (200, jsonEncode(found));
    }
    return (404, '{}');
  }
}

Map<String, Object?> subscription({
  String productId = 'pro',
  String state = 'SUBSCRIPTION_STATE_ACTIVE',
  bool acknowledged = false,
  String? account,
  Duration expiresIn = const Duration(days: 30),
}) =>
    <String, Object?>{
      'kind': 'androidpublisher#subscriptionPurchaseV2',
      'startTime': '2026-10-09T11:00:00Z',
      'subscriptionState': state,
      'acknowledgementState': acknowledged
          ? 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'
          : 'ACKNOWLEDGEMENT_STATE_PENDING',
      if (account != null)
        'externalAccountIdentifiers': <String, Object?>{
          'obfuscatedExternalAccountId': account,
        },
      'lineItems': <Object?>[
        <String, Object?>{
          'productId': productId,
          'expiryTime': now.add(expiresIn).toIso8601String(),
          'latestSuccessfulOrderId': 'GPA.1234-5678',
        },
      ],
    };

Map<String, Object?> productPurchase({
  int state = 0,
  int acknowledgement = 0,
  String? account,
}) =>
    <String, Object?>{
      'kind': 'androidpublisher#productPurchase',
      'purchaseTimeMillis': '${now.millisecondsSinceEpoch}',
      'purchaseState': state,
      'consumptionState': 0,
      'orderId': 'GPA.9999-0000',
      'acknowledgementState': acknowledgement,
      if (account != null) 'obfuscatedExternalAccountId': account,
      'quantity': 1,
    };

String receipt(String token, String productId, String type) =>
    jsonEncode(<String, Object?>{
      'purchaseToken': token,
      'productId': productId,
      'type': type,
      'orderId': 'GPA.device',
    });

void main() {
  late FakeGoogle google;
  late DVPlayStoreAdapter play;
  late DateTime clock;

  DVPlayStoreAdapter adapter({bool push = true}) => DVPlayStoreAdapter(
        packageName: packageName,
        serviceAccountEmail: serviceAccount,
        serviceAccountPrivateKeyPem: fixture('service_account_test_key.pem'),
        fetch: google.fetch,
        clock: () => clock,
        pushAudience: push ? pushAudience : null,
        pushServiceAccountEmail: push ? pushAccount : null,
      );

  setUp(() {
    google = FakeGoogle();
    clock = now;
    play = adapter();
    play.useCatalog(const <String, DVPurchaseKind>{
      'pro': DVPurchaseKind.subscription,
      'coins': DVPurchaseKind.consumable,
      'lifetime': DVPurchaseKind.nonConsumable,
    });
  });

  /// A Pub/Sub push as Google delivers it, signed by [key].
  DVSignedStoreNotification push(
    Map<String, Object?> developerNotification, {
    RSAPrivateKey? key,
    String audience = pushAudience,
    String email = pushAccount,
    String kid = 'google-1',
    bool signed = true,
    String messageId = 'msg-1',
    Duration expiresIn = const Duration(minutes: 30),
  }) {
    final String body = jsonEncode(<String, Object?>{
      'message': <String, Object?>{
        'data': base64.encode(utf8.encode(jsonEncode(<String, Object?>{
          'version': '1.0',
          'packageName': packageName,
          'eventTimeMillis': '${clock.millisecondsSinceEpoch}',
          ...developerNotification,
        }))),
        'messageId': messageId,
        'publishTime': clock.toIso8601String(),
      },
      'subscription': 'projects/example/subscriptions/play',
    });
    final int issued = clock.millisecondsSinceEpoch ~/ 1000;
    final String jwt = signJwt(
      key ?? googleKey,
      <String, Object?>{
        'iss': 'https://accounts.google.com',
        'aud': audience,
        'email': email,
        'email_verified': true,
        'iat': issued,
        'exp': issued + expiresIn.inSeconds,
        'sub': '1234',
      },
      kid: kid,
    );
    return DVSignedStoreNotification(
      body: body,
      headers: <String, String>{if (signed) 'Authorization': 'Bearer $jwt'},
    );
  }

  group('the service account', () {
    test('mints a token with a signed assertion and reuses it', () async {
      google.subscriptions['tok_1'] = subscription();
      await play.verifyReceipt(receipt('tok_1', 'pro', 'subs'));
      await play.verifyReceipt(receipt('tok_1', 'pro', 'subs'));
      expect(google.tokensMinted, 1);
    });

    test('mints a new token once the old one is near its end', () async {
      google.subscriptions['tok_1'] = subscription();
      await play.verifyReceipt(receipt('tok_1', 'pro', 'subs'));
      clock = now.add(const Duration(minutes: 59, seconds: 30));
      await play.verifyReceipt(receipt('tok_1', 'pro', 'subs'));
      expect(google.tokensMinted, 2);
    });

    test('a token Google stopped accepting is replaced once', () async {
      google.subscriptions['tok_1'] = subscription();
      await play.verifyReceipt(receipt('tok_1', 'pro', 'subs'));
      google.liveTokens.clear();
      await play.verifyReceipt(receipt('tok_1', 'pro', 'subs'));
      expect(google.tokensMinted, 2);
    });

    test('an error never carries the key or the token', () async {
      google.subscriptions['tok_1'] = subscription();
      await play.verifyReceipt(receipt('tok_1', 'pro', 'subs'));
      google.unavailable = true;
      try {
        await play.verifyReceipt(receipt('tok_1', 'pro', 'subs'));
        fail('an outage must throw');
      } on DVStoreUnavailable catch (error) {
        expect('$error', isNot(contains('ya29')));
        expect('$error', isNot(contains('PRIVATE KEY')));
      }
    });
  });

  group('a subscription receipt', () {
    test('is read back from Google, field by field', () async {
      final String account = DVPurchases.accountTokenFor('alice');
      google.subscriptions['tok_1'] =
          subscription(account: account, acknowledged: true);

      final DVStoreTransaction transaction =
          await play.verifyReceipt(receipt('tok_1', 'pro', 'subs'));

      expect(transaction.store, DVStore.play);
      expect(transaction.originalTransactionId, 'tok_1');
      expect(transaction.transactionId, 'GPA.1234-5678');
      expect(transaction.storeProductId, 'pro');
      expect(transaction.expiresAt, now.add(const Duration(days: 30)));
      expect(transaction.purchasedAt, DateTime.utc(2026, 10, 9, 11));
      expect(transaction.appAccountToken, account);
      expect(transaction.acknowledged, isTrue);
      expect(transaction.signedAt, now);
      expect(transaction.revokedAt, isNull);
    });

    test('the product is Google\'s, not the device\'s', () async {
      google.subscriptions['tok_1'] = subscription(productId: 'pro');
      final DVStoreTransaction transaction =
          await play.verifyReceipt(receipt('tok_1', 'lifetime', 'subs'));
      expect(transaction.storeProductId, 'pro');
    });

    test('a pending payment is refused until it is paid', () async {
      google.subscriptions['tok_1'] =
          subscription(state: 'SUBSCRIPTION_STATE_PENDING');
      await expectLater(play.verifyReceipt(receipt('tok_1', 'pro', 'subs')),
          throwsA(isA<DVStoreRefusal>()));
    });

    test('a token Google does not know is refused, not an outage', () async {
      await expectLater(play.verifyReceipt(receipt('tok_x', 'pro', 'subs')),
          throwsA(isA<DVStoreRefusal>()));
    });

    test('a receipt that is not one is refused', () async {
      await expectLater(play.verifyReceipt('not json'),
          throwsA(isA<DVStoreRefusal>()));
    });
  });

  group('a one-time receipt', () {
    test('a purchased product maps without an end', () async {
      google.oneTime['lifetime tok_2'] = productPurchase(acknowledgement: 1);
      final DVStoreTransaction transaction =
          await play.verifyReceipt(receipt('tok_2', 'lifetime', 'inapp'));
      expect(transaction.storeProductId, 'lifetime');
      expect(transaction.expiresAt, isNull);
      expect(transaction.acknowledged, isTrue);
      expect(transaction.transactionId, 'GPA.9999-0000');
      expect(transaction.purchasedAt, now);
    });

    test('a canceled purchase reads as revoked', () async {
      google.oneTime['lifetime tok_2'] = productPurchase(state: 1);
      final DVStoreTransaction transaction =
          await play.verifyReceipt(receipt('tok_2', 'lifetime', 'inapp'));
      expect(transaction.revokedAt, now);
    });

    test('a pending one-time purchase is refused', () async {
      google.oneTime['lifetime tok_2'] = productPurchase(state: 2);
      await expectLater(play.verifyReceipt(receipt('tok_2', 'lifetime', 'inapp')),
          throwsA(isA<DVStoreRefusal>()));
    });
  });

  group('acknowledgement', () {
    test('a subscription is acknowledged at the subscriptions endpoint',
        () async {
      await play.acknowledge(
          originalTransactionId: 'tok_1',
          transactionId: 'GPA.1',
          storeProductId: 'pro');
      expect(google.acknowledged, <String>['subscriptions/pro/tokens/tok_1:acknowledge']);
    });

    test('a consumable and a non-consumable at the products endpoint',
        () async {
      await play.acknowledge(
          originalTransactionId: 'tok_2',
          transactionId: 'GPA.2',
          storeProductId: 'coins');
      await play.acknowledge(
          originalTransactionId: 'tok_3',
          transactionId: 'GPA.3',
          storeProductId: 'lifetime');
      expect(google.acknowledged, <String>[
        'products/coins/tokens/tok_2:acknowledge',
        'products/lifetime/tokens/tok_3:acknowledge',
      ]);
    });

    test('an acknowledgement Google did not take is an outage', () async {
      google.unavailable = true;
      await expectLater(
          play.acknowledge(
              originalTransactionId: 'tok_1',
              transactionId: 'GPA.1',
              storeProductId: 'pro'),
          throwsA(isA<DVStoreUnavailable>()));
    });
  });

  group('a push', () {
    final Map<String, Object?> test1 = <String, Object?>{
      'testNotification': <String, Object?>{'version': '1.0'},
    };

    test('is refused unsigned', () async {
      final DVSignedStoreNotification signed = push(test1, signed: false);
      await expectLater(play.verifyNotification(signed.body, signed.headers),
          throwsA(isA<DVStoreRefusal>()));
    });

    test('is refused when somebody else signed it', () async {
      final DVSignedStoreNotification signed = push(test1, key: forgerKey);
      await expectLater(play.verifyNotification(signed.body, signed.headers),
          throwsA(isA<DVStoreRefusal>()));
    });

    test('is refused for another endpoint', () async {
      final DVSignedStoreNotification signed =
          push(test1, audience: 'https://elsewhere.example/push');
      await expectLater(play.verifyNotification(signed.body, signed.headers),
          throwsA(isA<DVStoreRefusal>()));
    });

    test('is refused from another service account', () async {
      final DVSignedStoreNotification signed =
          push(test1, email: 'someone@example.com');
      await expectLater(play.verifyNotification(signed.body, signed.headers),
          throwsA(isA<DVStoreRefusal>()));
    });

    test('is refused once its token has expired', () async {
      final DVSignedStoreNotification signed =
          push(test1, expiresIn: const Duration(minutes: -1));
      await expectLater(play.verifyNotification(signed.body, signed.headers),
          throwsA(isA<DVStoreRefusal>()));
    });

    test('is refused when no push authentication is configured', () async {
      final DVPlayStoreAdapter open = adapter(push: false);
      final DVSignedStoreNotification signed = push(test1);
      await expectLater(open.verifyNotification(signed.body, signed.headers),
          throwsA(isA<DVStoreRefusal>()));
    });

    test('is refused for another application', () async {
      final DVSignedStoreNotification signed =
          push(<String, Object?>{...test1, 'packageName': 'com.other'});
      await expectLater(play.verifyNotification(signed.body, signed.headers),
          throwsA(isA<DVStoreRefusal>()));
    });

    test('a test notification has nothing to apply', () async {
      final DVSignedStoreNotification signed = push(test1);
      await expectLater(play.verifyNotification(signed.body, signed.headers),
          throwsA(isA<DVStoreNothingToApply>()));
    });

    test('a rotated Google key is fetched again, not refused', () async {
      final DVSignedStoreNotification first = push(test1);
      await expectLater(play.verifyNotification(first.body, first.headers),
          throwsA(isA<DVStoreNothingToApply>()));
      google.currentKid = 'google-2';
      final DVSignedStoreNotification second = push(test1, kid: 'google-2');
      await expectLater(play.verifyNotification(second.body, second.headers),
          throwsA(isA<DVStoreNothingToApply>()));
      expect(google.certificateFetches, 2);
      final DVSignedStoreNotification third = push(test1, kid: 'google-2');
      await expectLater(play.verifyNotification(third.body, third.headers),
          throwsA(isA<DVStoreNothingToApply>()));
      expect(google.certificateFetches, 2, reason: 'a known key is cached');
    });
  });

  group('through DV.Purchases', () {
    late List<DVPurchaseChange> changes;
    late DVPurchases purchases;

    setUp(() {
      changes = <DVPurchaseChange>[];
      play = adapter();
      purchases = DVPurchases(
        products: const <DVPurchaseProduct>[monthly, coins, lifetime],
        stores: <DVStoreAdapter>[play],
        ledger: DVMemoryPurchaseLedger(),
        clock: () => clock,
        onChange: changes.add,
        logger: DVLogger(sinks: <DVLogSink>[DVMemoryLogSink()]),
      );
    });

    Future<DVPurchaseResult> deliver(DVSignedStoreNotification signed) =>
        purchases.acceptNotification(DVContext(), DVStore.play,
            body: signed.body, headers: signed.headers);

    test('a subscription is granted, acknowledged, then revoked by a push',
        () async {
      google.subscriptions['tok_1'] =
          subscription(account: DVPurchases.accountTokenFor('alice'));
      await purchases.verifyPurchase(DVStore.play,
          receipt('tok_1', 'pro', 'subs'),
          customer: 'alice');
      expect(await purchases.entitled('alice', pro), isTrue);
      expect(google.acknowledged,
          <String>['subscriptions/pro/tokens/tok_1:acknowledge'],
          reason: 'DVPurchases told the adapter the product is a subscription');

      clock = now.add(const Duration(hours: 1));
      google.subscriptions['tok_1'] = subscription(
          account: DVPurchases.accountTokenFor('alice'),
          state: 'SUBSCRIPTION_STATE_EXPIRED',
          acknowledged: true);
      final DVPurchaseResult result = await deliver(push(<String, Object?>{
        'subscriptionNotification': <String, Object?>{
          'version': '1.0',
          'notificationType': 12,
          'purchaseToken': 'tok_1',
        },
      }));

      expect(result.handled, isTrue);
      expect(await purchases.entitled('alice', pro), isFalse);
      expect(changes.last.revokedAt, clock,
          reason: 'a revocation is money going back, not a lapse');
    });

    test('a voided one-time purchase is revoked, its product found by token',
        () async {
      google.oneTime['lifetime tok_9'] = productPurchase();
      await purchases.verifyPurchase(DVStore.play,
          receipt('tok_9', 'lifetime', 'inapp'),
          customer: 'alice');
      expect(await purchases.entitled('alice', const Entitlement('exports')),
          isTrue);

      clock = now.add(const Duration(hours: 2));
      google.oneTime['lifetime tok_9'] = productPurchase(state: 1, acknowledgement: 1);
      await deliver(push(<String, Object?>{
        'voidedPurchaseNotification': <String, Object?>{
          'purchaseToken': 'tok_9',
          'orderId': 'GPA.9999-0000',
          'productType': 2,
          'refundType': 1,
        },
      }, messageId: 'void-1'));

      expect(await purchases.entitled('alice', const Entitlement('exports')),
          isFalse);
      expect(changes.last.revokedAt, clock);
    });

    test('a consumable is credited once and its refund reported', () async {
      google.oneTime['coins tok_c'] = productPurchase();
      final DVPurchaseResult bought = await purchases.verifyPurchase(
          DVStore.play, receipt('tok_c', 'coins', 'inapp'),
          customer: 'alice');
      expect(bought.consumed, <String>{'coins_100'});
      expect(google.acknowledged, <String>['products/coins/tokens/tok_c:acknowledge']);

      clock = now.add(const Duration(hours: 3));
      google.oneTime['coins tok_c'] = productPurchase(state: 1, acknowledgement: 1);
      await deliver(push(<String, Object?>{
        'oneTimeProductNotification': <String, Object?>{
          'version': '1.0',
          'notificationType': 2,
          'purchaseToken': 'tok_c',
          'sku': 'coins',
        },
      }, messageId: 'cancel-1'));

      expect(changes.last.refunded, <String>{'coins_100'});
    });
  });
}
