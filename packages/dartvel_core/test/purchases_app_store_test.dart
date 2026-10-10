// The App Store adapter believes a signed transaction only when Apple signed
// it.
//
// StoreKit 2 hands the device a JWS whose header carries the certificate
// chain that signed it. Everything that can go wrong with checking one is
// silent: a chain that is never compared with Apple's root accepts a
// signature from any certificate anybody can mint; a leaf that is not
// checked for Apple's marker accepts any certificate Apple ever issued; an
// expiry not checked accepts a revoked signing key for ever; a bundle id not
// checked accepts another application's purchase as this one's. Each of those
// is a free subscription, and none of them throws on its own.
//
// The chain under test/fixtures/app_store is generated for these tests and
// signs nothing outside them. It mirrors Apple's shape: a P-384 root, a P-256
// intermediate carrying Apple's intermediate marker, and a P-256 leaf
// carrying Apple's receipt-signing marker.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

const String fixtures = 'test/fixtures/app_store';
const String bundleId = 'com.example.books';
const Entitlement pro = Entitlement('pro');

List<int> certificateDer(String name) {
  final String pem = File('$fixtures/$name').readAsStringSync();
  final String body = pem
      .split('\n')
      .where((String line) => !line.startsWith('-----'))
      .join();
  return base64.decode(body);
}

Uint8List leafKey() => dvEcPrivateScalarFromPkcs8Pem(
    File('$fixtures/test_only_leaf.key.pem').readAsStringSync());

String base64UrlSegment(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// A JWS signed the way the App Store signs one, by [chain]'s leaf.
String signed(
  Map<String, Object?> payload, {
  List<String> chain = const <String>[
    'test_only_leaf.pem',
    'test_only_intermediate.pem',
    'test_only_root.pem',
  ],
}) {
  final Map<String, Object?> header = <String, Object?>{
    'alg': 'ES256',
    'x5c': <String>[
      for (final String name in chain) base64.encode(certificateDer(name)),
    ],
  };
  final String input = '${base64UrlSegment(utf8.encode(jsonEncode(header)))}.'
      '${base64UrlSegment(utf8.encode(jsonEncode(payload)))}';
  final Uint8List signature = dvWebPushSignEs256(utf8.encode(input), leafKey());
  return '$input.${base64UrlSegment(signature)}';
}

final DateTime purchased = DateTime.now().toUtc().subtract(const Duration(hours: 1));

int millis(DateTime at) => at.millisecondsSinceEpoch;

Map<String, Object?> transactionPayload({
  String bundle = bundleId,
  String environment = 'Production',
  String product = 'com.example.books.pro',
  String original = '2000000000000001',
  String transaction = '2000000000000001',
  DateTime? expires,
  DateTime? revoked,
  String? token,
  DateTime? signedDate,
}) =>
    <String, Object?>{
      'transactionId': transaction,
      'originalTransactionId': original,
      'bundleId': bundle,
      'productId': product,
      'purchaseDate': millis(purchased),
      'originalPurchaseDate': millis(purchased),
      if (expires != null) 'expiresDate': millis(expires),
      if (revoked != null) 'revocationDate': millis(revoked),
      if (revoked != null) 'revocationReason': 0,
      if (token != null) 'appAccountToken': token,
      'type': 'Auto-Renewable Subscription',
      'inAppOwnershipType': 'PURCHASED',
      'signedDate': millis(signedDate ?? purchased),
      'environment': environment,
      'price': 4990,
      'currency': 'USD',
    };

String notificationBody({
  required String type,
  String? subtype,
  String uuid = 'a5f4c3b2-0000-4000-8000-000000000001',
  Map<String, Object?>? transaction,
  Map<String, Object?>? renewal,
  String bundle = bundleId,
  DateTime? signedDate,
}) =>
    jsonEncode(<String, Object?>{
      'signedPayload': signed(<String, Object?>{
        'notificationType': type,
        if (subtype != null) 'subtype': subtype,
        'notificationUUID': uuid,
        'version': '2.0',
        'signedDate': millis(signedDate ?? DateTime.now().toUtc()),
        'data': <String, Object?>{
          'bundleId': bundle,
          'environment': 'Production',
          'appAppleId': 1234567890,
          if (transaction != null) 'signedTransactionInfo': signed(transaction),
          if (renewal != null) 'signedRenewalInfo': signed(renewal),
        },
      }),
    });

DVAppStoreAdapter adapter({
  DateTime Function()? clock,
  List<List<int>>? roots,
  String? offerKey,
}) =>
    DVAppStoreAdapter(
      bundleId: bundleId,
      appAppleId: 1234567890,
      rootCertificates:
          roots ?? <List<int>>[certificateDer('test_only_root.pem')],
      clock: clock,
      inAppKeyId: offerKey == null ? null : 'ABC123DEF4',
      inAppPrivateKeyPem: offerKey,
    );

Matcher refusedWith(String fragment) => throwsA(isA<DVStoreRefusal>()
    .having((DVStoreRefusal r) => r.reason, 'reason', contains(fragment)));

void main() {
  group('the embedded Apple root', () {
    test('is Apple Root CA - G3, pinned by fingerprint', () {
      final List<int> der = DVAppStoreAdapter.appleRootCaG3;
      expect(
        sha256.convert(der).toString(),
        '63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179',
      );
    });

    test('is the default, so a test chain is refused without configuration',
        () async {
      final DVAppStoreAdapter real = DVAppStoreAdapter(bundleId: bundleId);
      await expectLater(real.verifyReceipt(signed(transactionPayload())),
          refusedWith('root'));
    });
  });

  group('a signed transaction', () {
    test('verifies and becomes the store\'s answer', () async {
      final DateTime expires = purchased.add(const Duration(days: 30));
      final String token = DVPurchases.accountTokenFor('alice');
      final DVStoreTransaction transaction = await adapter()
          .verifyReceipt(signed(transactionPayload(expires: expires, token: token)));

      expect(transaction.store, DVStore.appStore);
      expect(transaction.originalTransactionId, '2000000000000001');
      expect(transaction.storeProductId, 'com.example.books.pro');
      expect(transaction.purchasedAt, DateTime.fromMillisecondsSinceEpoch(
          millis(purchased), isUtc: true));
      expect(transaction.expiresAt!.isUtc, isTrue);
      expect(transaction.expiresAt!.millisecondsSinceEpoch, millis(expires));
      expect(transaction.appAccountToken, token);
      expect(transaction.acknowledged, isTrue);
      expect(transaction.price, DVMoney(amount: 499, currency: 'USD'));
      expect(transaction.revokedAt, isNull);
    });

    test('with its payload altered after signing is refused', () async {
      final List<String> parts = signed(transactionPayload()).split('.');
      final String forged = base64UrlSegment(utf8.encode(jsonEncode(
          transactionPayload(product: 'com.example.books.lifetime'))));
      await expectLater(
          adapter().verifyReceipt('${parts[0]}.$forged.${parts[2]}'),
          refusedWith('signature'));
    });

    test('signed under a root that is not pinned is refused', () async {
      await expectLater(
        adapter().verifyReceipt(signed(transactionPayload(), chain: <String>[
          'test_only_other_leaf.pem',
          'test_only_other_intermediate.pem',
          'test_only_other_root.pem',
        ])),
        refusedWith('root'),
      );
    });

    test('whose chain does not link up is refused', () async {
      // The pinned root at the end, an intermediate it never signed in the
      // middle: comparing only the last certificate with the root would pass.
      await expectLater(
        adapter().verifyReceipt(signed(transactionPayload(), chain: <String>[
          'test_only_other_leaf.pem',
          'test_only_other_intermediate.pem',
          'test_only_root.pem',
        ])),
        refusedWith('intermediate'),
      );
    });

    test('by a leaf without Apple\'s receipt-signing marker is refused',
        () async {
      await expectLater(
        adapter().verifyReceipt(signed(transactionPayload(), chain: <String>[
          'test_only_leaf_without_marker.pem',
          'test_only_intermediate.pem',
          'test_only_root.pem',
        ])),
        refusedWith('marker'),
      );
    });

    test('by a leaf past its validity is refused', () async {
      final DVAppStoreAdapter later = adapter(
          clock: () => DateTime.now().toUtc().add(const Duration(days: 3)));
      await expectLater(
        later.verifyReceipt(signed(transactionPayload(), chain: <String>[
          'test_only_short_leaf.pem',
          'test_only_intermediate.pem',
          'test_only_root.pem',
        ])),
        refusedWith('valid'),
      );
    });

    test('for another application is refused', () async {
      await expectLater(
          adapter().verifyReceipt(
              signed(transactionPayload(bundle: 'com.example.other'))),
          refusedWith('bundle'));
    });

    test('from Xcode\'s local testing is refused unless allowed', () async {
      await expectLater(
          adapter().verifyReceipt(
              signed(transactionPayload(environment: 'Xcode'))),
          refusedWith('environment'));
    });

    test('that is not a JWS at all is refused, not thrown', () async {
      await expectLater(adapter().verifyReceipt('not a jws'), refusedWith(''));
    });
  });

  group('a notification', () {
    test('TEST carries nothing to apply', () async {
      await expectLater(
        adapter().verifyNotification(
            notificationBody(type: 'TEST'), const <String, String>{}),
        throwsA(isA<DVStoreNothingToApply>()),
      );
    });

    test('REFUND carries the revocation', () async {
      final DateTime refunded = DateTime.now().toUtc();
      final DVStoreNotification notification = await adapter()
          .verifyNotification(
              notificationBody(
                type: 'REFUND',
                transaction: transactionPayload(revoked: refunded),
              ),
              const <String, String>{});
      expect(notification.type, 'REFUND');
      expect(notification.notificationId,
          'a5f4c3b2-0000-4000-8000-000000000001');
      expect(notification.transaction.revokedAt!.millisecondsSinceEpoch,
          millis(refunded));
    });

    test('in a billing grace period extends access to the grace end',
        () async {
      final DateTime expires = purchased.add(const Duration(days: 30));
      final DateTime grace = expires.add(const Duration(days: 16));
      final DVStoreNotification notification = await adapter()
          .verifyNotification(
              notificationBody(
                type: 'DID_FAIL_TO_RENEW',
                subtype: 'GRACE_PERIOD',
                transaction: transactionPayload(expires: expires),
                renewal: <String, Object?>{
                  'originalTransactionId': '2000000000000001',
                  'productId': 'com.example.books.pro',
                  'gracePeriodExpiresDate': millis(grace),
                  'signedDate': millis(purchased),
                  'environment': 'Production',
                },
              ),
              const <String, String>{});
      expect(notification.type, 'DID_FAIL_TO_RENEW/GRACE_PERIOD');
      expect(notification.transaction.notAfter!.millisecondsSinceEpoch,
          millis(grace));
    });

    test('for another application is refused', () async {
      await expectLater(
        adapter().verifyNotification(
            notificationBody(
                type: 'DID_RENEW',
                bundle: 'com.example.other',
                transaction: transactionPayload()),
            const <String, String>{}),
        refusedWith('bundle'),
      );
    });

    test('whose body is not a signed payload is refused', () async {
      await expectLater(
        adapter().verifyNotification('{"hello":1}', const <String, String>{}),
        refusedWith('signedPayload'),
      );
    });
  });

  test('end to end: a purchase is granted, then a refund revokes it',
      () async {
    final DVPurchases purchases = DVPurchases(
      products: const <DVPurchaseProduct>[
        DVPurchaseProduct(
          'pro_monthly',
          billable: DVBillable.digital(appStore: 'com.example.books.pro'),
          entitlements: <Entitlement>{pro},
        ),
      ],
      stores: <DVStoreAdapter>[adapter()],
      ledger: DVMemoryPurchaseLedger(),
      logger: DVLogger(sinks: <DVLogSink>[DVMemoryLogSink()]),
    );
    final DateTime expires = DateTime.now().toUtc().add(const Duration(days: 29));
    final String token = DVPurchases.accountTokenFor('alice');

    await purchases.verifyPurchase(
      DVStore.appStore,
      signed(transactionPayload(expires: expires, token: token)),
      customer: 'alice',
    );
    expect(await purchases.entitled('alice', pro), isTrue);

    final DateTime refunded = DateTime.now().toUtc();
    final DVPurchaseResult result = await purchases.acceptNotification(
      DVContext(),
      DVStore.appStore,
      body: notificationBody(
        type: 'REFUND',
        signedDate: refunded.add(const Duration(seconds: 1)),
        transaction: transactionPayload(
          expires: expires,
          token: token,
          revoked: refunded,
          signedDate: refunded,
        ),
      ),
      headers: const <String, String>{},
    );
    expect(result.revoked, <Entitlement>{pro});
    expect(await purchases.entitled('alice', pro), isFalse);
  });

  group('a promotional offer signature', () {
    test('is refused without an In-App Purchase key', () {
      expect(
        () => adapter().signOffer(
            storeProductId: 'com.example.books.pro',
            offerId: 'come_back',
            appAccountToken: DVPurchases.accountTokenFor('alice')),
        throwsStateError,
      );
    });

    test('signs Apple\'s payload with the key, verifiably', () async {
      final String pem =
          File('$fixtures/test_only_offer_key.p8').readAsStringSync();
      final String token = DVPurchases.accountTokenFor('alice').toUpperCase();
      final DVStoreOfferSignature signature = await adapter(offerKey: pem)
          .signOffer(
              storeProductId: 'com.example.books.pro',
              offerId: 'come_back',
              appAccountToken: token);

      expect(signature.keyId, 'ABC123DEF4');
      expect(signature.nonce,
          matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      const String separator = '⁣';
      final String payload = <String>[
        bundleId,
        'ABC123DEF4',
        'com.example.books.pro',
        'come_back',
        token.toLowerCase(),
        signature.nonce,
        '${signature.timestamp}',
      ].join(separator);

      final ECDomainParameters domain = ECDomainParameters('prime256v1');
      final Uint8List scalar = dvEcPrivateScalarFromPkcs8Pem(pem);
      BigInt scalarValue = BigInt.zero;
      for (final int byte in scalar) {
        scalarValue = (scalarValue << 8) | BigInt.from(byte);
      }
      final ECPoint publicPoint = (domain.G * scalarValue)!;
      final ({BigInt r, BigInt s})? parsed =
          dvDecodeDerSignature(base64.decode(signature.signature));
      expect(parsed, isNotNull, reason: 'Apple expects a DER signature');
      final ECDSASigner verifier = ECDSASigner(SHA256Digest())
        ..init(false,
            PublicKeyParameter<ECPublicKey>(ECPublicKey(publicPoint, domain)));
      expect(
        verifier.verifySignature(Uint8List.fromList(utf8.encode(payload)),
            ECSignature(parsed!.r, parsed.s)),
        isTrue,
      );
    });
  });
}
