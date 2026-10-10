// The generated /_dartvel/purchases endpoints, driven the way a device and a
// store drive them.
//
// What must not happen: a receipt granted to whoever the request body names
// rather than the signed-in session; an unsigned store notification applied;
// a refusal answered with a status a store reads as "retry for ever"; a
// device told nothing about why its purchase was refused.
import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const Entitlement pro = Entitlement('pro');

const DVPurchaseProduct monthly = DVPurchaseProduct(
  'pro_monthly',
  billable: DVBillable.digital(appStore: 'com.example.pro', play: 'pro'),
  entitlements: <Entitlement>{pro},
);

final DateTime start = DateTime.utc(2026, 10, 9, 12);

DVSessionPrincipal signedIn(String userId) => DVSessionPrincipal(
      session: DVSession(
        id: 'ses_$userId',
        userId: userId,
        tenant: 'default',
        createdAt: start,
        lastSeenAt: start,
      ),
    );

Request request(String method, String path,
        {Object? body, Map<String, String> headers = const <String, String>{}}) =>
    Request(
      method: method,
      url: Uri.parse('http://localhost/api$path'),
      headers: Headers(<String, Object?>{
        'content-type': 'application/json',
        ...headers,
      }),
      bodyStream: Stream<List<int>>.value(
          body == null ? const <int>[] : utf8.encode(jsonEncode(body))),
    );

Future<(int, Map<String, Object?>)> answer(Future<Response> response) async {
  final Response done = await response;
  final String text = await done.body?.text() ?? '';
  Object? json;
  try {
    json = text.isEmpty ? null : jsonDecode(text);
  } on FormatException {
    json = null;
  }
  return (
    done.status,
    json is Map ? json.cast<String, Object?>() : const <String, Object?>{}
  );
}

void main() {
  late DVFakeStoreAdapter play;
  late DVPurchases server;

  setUp(() {
    play = DVFakeStoreAdapter(DVStore.play,
        signingKey: 'k', acknowledgementWindow: const Duration(days: 3));
    server = DVPurchases(
      products: const <DVPurchaseProduct>[monthly],
      stores: <DVStoreAdapter>[play],
      ledger: DVMemoryPurchaseLedger(),
      clock: () => start,
      logger: DVLogger(sinks: <DVLogSink>[DVMemoryLogSink()]),
    );
    DVPurchases.configure(server);
    play.issue(
      'r1',
      DVStoreTransaction(
        store: DVStore.play,
        originalTransactionId: 'tok_1',
        transactionId: 'GPA.1',
        storeProductId: 'pro',
        purchasedAt: start,
        signedAt: start,
        expiresAt: start.add(const Duration(days: 30)),
        appAccountToken: DVPurchases.accountTokenFor('alice'),
      ),
    );
  });

  tearDown(DVPurchases.unconfigure);

  test('verify grants to the session, never to a name in the body', () async {
    final (int status, Map<String, Object?> body) = await answer(
      DVSessionPrincipal.actingAs(
        signedIn('alice'),
        () => DVPurchaseEndpoints.verify(request('POST', DVHttpPurchaseBackend.verifyPath,
            body: <String, Object?>{
              'store': 'play',
              'receipts': <String>['r1'],
              'customer': 'mallory',
            })),
      ),
    );
    expect(status, 200);
    final DVPurchaseVerdict verdict = DVPurchaseVerdict.fromJson(body);
    expect(verdict.results.single.granted.single.id, 'pro');
    expect(verdict.snapshots.single.entitlement, 'pro');
    expect(await server.entitled('alice', pro), isTrue);
    expect(await server.entitled('mallory', pro), isFalse);
    expect(jsonEncode(body), isNot(contains('alice')),
        reason: 'the customer key stays on the server');
  });

  test('verify without a session is 401 and grants nothing', () async {
    final (int status, _) = await answer(DVPurchaseEndpoints.verify(request(
        'POST', DVHttpPurchaseBackend.verifyPath,
        body: <String, Object?>{'store': 'play', 'receipts': <String>['r1']})));
    expect(status, 401);
    expect(await server.entitled('alice', pro), isFalse);
  });

  test('a receipt bought for another account is refused in the verdict',
      () async {
    final (int status, Map<String, Object?> body) = await answer(
      DVSessionPrincipal.actingAs(
        signedIn('bob'),
        () => DVPurchaseEndpoints.verify(request('POST', DVHttpPurchaseBackend.verifyPath,
            body: <String, Object?>{'store': 'play', 'receipts': <String>['r1']})),
      ),
    );
    expect(status, 200);
    expect(DVPurchaseVerdict.fromJson(body).results.single.refused, isTrue);
  });

  test('an unknown store is a 400, not a crash', () async {
    final (int status, _) = await answer(DVSessionPrincipal.actingAs(
      signedIn('alice'),
      () => DVPurchaseEndpoints.verify(request('POST', DVHttpPurchaseBackend.verifyPath,
          body: <String, Object?>{'store': 'steam', 'receipts': <String>['r1']})),
    ));
    expect(status, 400);
  });

  test('the account token is the session\'s', () async {
    final (int status, Map<String, Object?> body) = await answer(
        DVSessionPrincipal.actingAs(signedIn('alice'),
            () => DVPurchaseEndpoints.accountToken(
                request('GET', DVHttpPurchaseBackend.accountTokenPath))));
    expect(status, 200);
    expect(body['token'], DVPurchases.accountTokenFor('alice'));
  });

  test('checkout with no gateway answers the refusal and its code', () async {
    final (int status, Map<String, Object?> body) = await answer(
        DVSessionPrincipal.actingAs(
            signedIn('alice'),
            () => DVPurchaseEndpoints.checkout(request(
                'POST', DVHttpPurchaseBackend.checkoutPath,
                body: <String, Object?>{'product': 'pro_monthly'}))));
    expect(status, 409);
    expect(body['code'], 'DV-PURCHASE-009');
  });

  group('store notifications', () {
    test('a signed notification is applied and answered 200', () async {
      await DVSessionPrincipal.actingAs(
          signedIn('alice'),
          () => DVPurchaseEndpoints.verify(request(
              'POST', DVHttpPurchaseBackend.verifyPath,
              body: <String, Object?>{'store': 'play', 'receipts': <String>['r1']})));
      final DVSignedStoreNotification signed = play.sign(DVStoreNotification(
        notificationId: 'm1',
        type: 'SUBSCRIPTION_REVOKED',
        signedAt: start.add(const Duration(minutes: 5)),
        transaction: DVStoreTransaction(
          store: DVStore.play,
          originalTransactionId: 'tok_1',
          transactionId: 'GPA.1',
          storeProductId: 'pro',
          purchasedAt: start,
          signedAt: start.add(const Duration(minutes: 5)),
          expiresAt: start.add(const Duration(days: 30)),
          revokedAt: start.add(const Duration(minutes: 5)),
          acknowledged: true,
        ),
      ));
      final Request delivered = Request(
        method: 'POST',
        url: Uri.parse('http://localhost/api${DVHttpPurchaseBackend.playNotificationsPath}'),
        headers: Headers(signed.headers),
        bodyStream: Stream<List<int>>.value(utf8.encode(signed.body)),
      );
      final (int status, _) =
          await answer(DVPurchaseEndpoints.notification(delivered, DVStore.play));
      expect(status, 200);
      expect(await server.entitled('alice', pro), isFalse);
    });

    test('an unsigned notification is a 400 and changes nothing', () async {
      final (int status, _) = await answer(DVPurchaseEndpoints.notification(
          request('POST', DVHttpPurchaseBackend.playNotificationsPath,
              body: <String, Object?>{'forged': true}),
          DVStore.play));
      expect(status, 400);
    });

    test('a store that cannot be reached is a 503, so the store retries',
        () async {
      play.unavailable = true;
      final DVSignedStoreNotification signed = play.sign(DVStoreNotification(
        notificationId: 'm2',
        type: 'x',
        signedAt: start,
        transaction: DVStoreTransaction(
          store: DVStore.play,
          originalTransactionId: 'tok_1',
          transactionId: 'GPA.1',
          storeProductId: 'pro',
          purchasedAt: start,
          signedAt: start,
        ),
      ));
      final (int status, _) = await answer(DVPurchaseEndpoints.notification(
          Request(
            method: 'POST',
            url: Uri.parse('http://localhost/x'),
            headers: Headers(signed.headers),
            bodyStream: Stream<List<int>>.value(utf8.encode(signed.body)),
          ),
          DVStore.play));
      expect(status, 503);
    });
  });

  test('nothing is served before DV.Purchases is configured', () async {
    DVPurchases.unconfigure();
    final (int status, _) = await answer(DVSessionPrincipal.actingAs(
        signedIn('alice'),
        () => DVPurchaseEndpoints.entitlements(
            request('GET', DVHttpPurchaseBackend.entitlementsPath))));
    expect(status, 404);
  });
}
