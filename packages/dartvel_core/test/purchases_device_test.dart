// The device half of DV.Purchases: open the sheet, hand the receipt to the
// server, finish only what the server accepted, and rebuild from what it says
// the person now holds.
//
// The silent failures here are the ones stores punish. A transaction
// finished before the server saw it is a purchase nobody can grant again. A
// consumable never consumed cannot be bought a second time on Play. An Ask to
// Buy approval that arrives a day later, on another screen, is lost if only
// the purchase call listens for it. A web build that has no checkout and
// shows a button anyway takes clicks and sells nothing.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const Entitlement pro = Entitlement('pro');
const Entitlement lifetimeExports = Entitlement('exports');

const DVPurchaseProduct monthly = DVPurchaseProduct(
  'pro_monthly',
  billable: DVBillable.digital(appStore: 'com.example.pro', play: 'pro'),
  entitlements: <Entitlement>{pro},
);

const DVPurchaseProduct lifetime = DVPurchaseProduct(
  'exports_lifetime',
  billable: DVBillable.digital(appStore: 'com.example.exports', play: 'exports'),
  entitlements: <Entitlement>{lifetimeExports},
  kind: DVPurchaseKind.nonConsumable,
);

const DVPurchaseProduct coins = DVPurchaseProduct(
  'coins_100',
  billable: DVBillable.digital(
    appStore: 'com.example.coins',
    play: 'coins',
    telegram: 'coins',
    telegramStars: 50,
  ),
  entitlements: <Entitlement>{},
  kind: DVPurchaseKind.consumable,
);

const List<DVPurchaseProduct> catalogue = <DVPurchaseProduct>[
  monthly,
  lifetime,
  coins,
];

final DateTime start = DateTime.utc(2026, 10, 9, 12);

/// A Telegram adapter for tests: the invoice it writes is "paid" by the
/// test, which then makes the receipt verify.
class _FakeStars extends DVFakeStoreAdapter implements DVStoreInvoiceIssuer {
  _FakeStars() : super(DVStore.telegram, signingKey: 'stars');
  final List<String> invoices = <String>[];

  @override
  Future<DVStoreInvoice> createInvoice({
    required String storeProductId,
    required String title,
    required int amount,
    required String appAccountToken,
  }) async {
    final String receipt = 'invoice_${invoices.length + 1}';
    invoices.add('$storeProductId:$amount');
    issue(
      receipt,
      DVStoreTransaction(
        store: DVStore.telegram,
        originalTransactionId: 'charge_${invoices.length}',
        transactionId: 'charge_${invoices.length}',
        storeProductId: storeProductId,
        purchasedAt: start,
        signedAt: start,
        appAccountToken: appAccountToken,
        acknowledged: true,
      ),
    );
    return DVStoreInvoice(
        url: Uri.parse('https://t.me/\$invoice/$receipt'), receipt: receipt);
  }
}

/// A backend that answers like the real one does when the store is down.
class _DownBackend extends DVInProcessPurchaseBackend {
  _DownBackend(super.server, {required super.customer});
  bool down = false;

  @override
  Future<DVPurchaseVerdict> verify(DVStore store, List<String> receipts) {
    if (down) throw const DVStoreUnavailable('the backend is unreachable');
    return super.verify(store, receipts);
  }
}

void main() {
  late DVFakeStoreAdapter appleServer;
  late DVFakeStoreAdapter playServer;
  late _FakeStars stars;
  late DVPurchases server;
  late List<DVPurchaseChange> changes;

  DVPurchases serverWith({DVBillingProvider? gateway}) => DVPurchases(
        products: catalogue,
        stores: <DVStoreAdapter>[appleServer, playServer, stars],
        ledger: DVMemoryPurchaseLedger(),
        clock: () => start,
        onChange: changes.add,
        gateway: gateway,
        gatewayPlans: const <String, BillingPlan>{
          'pro_monthly': BillingPlan(
              id: 'pro', displayName: 'Pro', priceMinorUnits: 0, currency: 'USD'),
        },
        logger: DVLogger(sinks: <DVLogSink>[DVMemoryLogSink()]),
      );

  setUp(() {
    appleServer = DVFakeStoreAdapter(DVStore.appStore, signingKey: 'a');
    playServer = DVFakeStoreAdapter(DVStore.play,
        signingKey: 'p', acknowledgementWindow: const Duration(days: 3));
    stars = _FakeStars();
    changes = <DVPurchaseChange>[];
    server = serverWith();
  });

  DVPurchases deviceOn(
    DVStoreClient? store, {
    DVPurchaseBackend? backend,
    DVPurchaseChannel channel = DVPurchaseChannel.play,
    Future<void> Function(Uri url)? openUrl,
    Future<String> Function(Uri url)? openInvoice,
  }) =>
      DVPurchases.device(
        products: catalogue,
        store: store,
        backend: backend ?? DVInProcessPurchaseBackend(server, customer: 'alice'),
        channel: channel,
        clock: () => start,
        openUrl: openUrl,
        openInvoice: openInvoice,
        logger: DVLogger(sinks: <DVLogSink>[DVMemoryLogSink()]),
      );

  group('a store purchase', () {
    test('is verified on the server, then finished, then held', () async {
      final DVFakeStoreClient play =
          DVFakeStoreClient(playServer, clock: () => start);
      final DVPurchases device = deviceOn(play);
      final List<void> rebuilt = <void>[];
      device.entitlementChanges.listen(rebuilt.add);

      final DVPurchaseOutcome outcome = await device.buy(monthly);

      expect(outcome, isA<DVPurchaseCompleted>());
      expect((outcome as DVPurchaseCompleted).granted, <Entitlement>{pro});
      expect(device.holds(pro), isTrue);
      expect(play.finished, hasLength(1));
      expect(play.consumed, isEmpty);
      expect(await server.entitled('alice', pro), isTrue,
          reason: 'the grant is the server ledger, not the device');
      await pumpEventQueue();
      expect(rebuilt, isNotEmpty, reason: 'a holder of the signal rebuilds');
    });

    test('carries the account token the server checks', () async {
      final DVFakeStoreClient play =
          DVFakeStoreClient(playServer, clock: () => start);
      await deviceOn(play).buy(monthly);
      expect(play.requests.single.appAccountToken,
          DVPurchases.accountTokenFor('alice'));
    });

    test('a consumable is credited once and consumed so it can be bought again',
        () async {
      final DVFakeStoreClient play =
          DVFakeStoreClient(playServer, clock: () => start);
      final DVPurchases device = deviceOn(play);

      final DVPurchaseOutcome first = await device.buy(coins);
      final DVPurchaseOutcome second = await device.buy(coins);

      expect((first as DVPurchaseCompleted).consumed, <String>{'coins_100'});
      expect((second as DVPurchaseCompleted).consumed, <String>{'coins_100'});
      expect(play.consumed, hasLength(2));
      expect(changes.expand((DVPurchaseChange c) => c.consumed), hasLength(2));
      expect(device.holds(pro), isFalse);
    });

    test('a cancelled sheet verifies and finishes nothing', () async {
      final DVFakeStoreClient play = DVFakeStoreClient(playServer,
          clock: () => start)
        ..respondWith = DVFakeStoreResponse.cancel;
      final DVPurchaseOutcome outcome = await deviceOn(play).buy(monthly);
      expect(outcome, isA<DVPurchaseCancelled>());
      expect(play.finished, isEmpty);
      expect(changes, isEmpty);
    });

    test('a refused receipt is reported and left unfinished', () async {
      final DVFakeStoreClient play = DVFakeStoreClient(playServer,
          clock: () => start)
        ..refuseOnServer = true;
      final DVPurchaseOutcome outcome = await deviceOn(play).buy(monthly);
      expect(outcome, isA<DVPurchaseFailed>());
      expect((outcome as DVPurchaseFailed).code, 'DV-PURCHASE-003');
      expect(play.finished, isEmpty,
          reason: 'Play refunds what is never acknowledged; finishing would '
              'hide a purchase the server did not accept');
    });

    test('an unreachable backend leaves the transaction for the next try',
        () async {
      final DVFakeStoreClient play =
          DVFakeStoreClient(playServer, clock: () => start);
      final _DownBackend backend = _DownBackend(server, customer: 'alice')
        ..down = true;
      final DVPurchases device = deviceOn(play, backend: backend);

      final DVPurchaseOutcome outcome = await device.buy(lifetime);
      expect(outcome, isA<DVPurchaseFailed>());
      expect(play.finished, isEmpty);

      backend.down = false;
      final List<DVPurchaseResult> restored = await device.restore();
      expect(restored.single.handled, isTrue);
      expect(device.holds(lifetimeExports), isTrue);
      expect(play.finished, hasLength(1));
    });
  });

  group('pending and deferred', () {
    test('Ask to Buy is pending, then granted when approved later', () async {
      final DVFakeStoreClient apple = DVFakeStoreClient(appleServer,
          clock: () => start)
        ..respondWith = DVFakeStoreResponse.pending;
      final DVPurchases device =
          deviceOn(apple, channel: DVPurchaseChannel.appStore);

      final DVPurchaseOutcome outcome = await device.buy(lifetime);
      expect(outcome, isA<DVPurchasePending>());
      expect(device.holds(lifetimeExports), isFalse);

      final Future<void> granted = device.entitlementChanges.first;
      apple.approvePending();
      await granted.timeout(const Duration(seconds: 2));

      expect(device.holds(lifetimeExports), isTrue);
      expect(apple.finished, hasLength(1));
    });

    test('a purchase finished on another device arrives through updates',
        () async {
      final DVFakeStoreClient apple =
          DVFakeStoreClient(appleServer, clock: () => start);
      final DVPurchases device =
          deviceOn(apple, channel: DVPurchaseChannel.appStore);
      await device.refreshEntitlements();

      final Future<void> granted = device.entitlementChanges.first;
      apple.deliverExternally(lifetime.identifierOn(DVStore.appStore)!,
          DVPurchaseKind.nonConsumable,
          accountToken: DVPurchases.accountTokenFor('alice'));
      await granted.timeout(const Duration(seconds: 2));
      expect(device.holds(lifetimeExports), isTrue);
    });
  });

  test('restore revalidates what the store account owns', () async {
    final DVFakeStoreClient apple =
        DVFakeStoreClient(appleServer, clock: () => start);
    apple.deliverExternally('com.example.exports', DVPurchaseKind.nonConsumable,
        accountToken: DVPurchases.accountTokenFor('alice'), emit: false);
    final DVPurchases device =
        deviceOn(apple, channel: DVPurchaseChannel.appStore);

    final List<DVPurchaseResult> results = await device.restore();

    expect(results, hasLength(1));
    expect(results.single.granted, <Entitlement>{lifetimeExports});
    expect(device.holds(lifetimeExports), isTrue);
    expect(apple.synced, isTrue, reason: 'restore asks the store to sync');
  });

  test('restore does not move somebody else\'s purchase to this account',
      () async {
    final DVFakeStoreClient apple =
        DVFakeStoreClient(appleServer, clock: () => start);
    apple.deliverExternally('com.example.exports', DVPurchaseKind.nonConsumable,
        accountToken: DVPurchases.accountTokenFor('bob'), emit: false);
    final List<DVPurchaseResult> results =
        await deviceOn(apple, channel: DVPurchaseChannel.appStore).restore();
    expect(results.single.refused, isTrue);
  });

  group('offers', () {
    test('listings carry the store price and offers, keyed to products',
        () async {
      final DVFakeStoreClient play = DVFakeStoreClient(playServer,
          clock: () => start, listings: <DVStoreListing>[
        DVStoreListing(
          storeProductId: 'pro',
          title: 'Pro',
          description: 'Everything',
          displayPrice: r'$4.99',
          price: DVMoney(amount: 499, currency: 'USD'),
          period: 'P1M',
          offers: const <DVStoreOffer>[
            DVStoreOffer(
                id: 'trial',
                kind: DVStoreOfferKind.freeTrial,
                period: 'P1W',
                token: 'tok-trial'),
          ],
        ),
      ]);
      final List<DVStoreListing> listed = await deviceOn(play).listings();
      expect(listed.single.productId, 'pro_monthly');
      expect(listed.single.offers.single.kind, DVStoreOfferKind.freeTrial);
    });

    test('a trial offer is opened as the store listed it', () async {
      final DVFakeStoreClient play =
          DVFakeStoreClient(playServer, clock: () => start);
      const DVStoreOffer trial = DVStoreOffer(
          id: 'trial', kind: DVStoreOfferKind.freeTrial, token: 'tok-trial');
      await deviceOn(play).buy(monthly, offer: trial);
      expect(play.requests.single.offer?.token, 'tok-trial');
      expect(play.requests.single.offerSignature, isNull);
    });

    test('an App Store promotional offer is signed by the server first',
        () async {
      final List<String> signed = <String>[];
      final DVFakeStoreClient apple =
          DVFakeStoreClient(appleServer, clock: () => start);
      final DVPurchases device = deviceOn(apple,
          channel: DVPurchaseChannel.appStore,
          backend: _SigningBackend(server, signed, customer: 'alice'));
      const DVStoreOffer comeBack = DVStoreOffer(
          id: 'come_back', kind: DVStoreOfferKind.promotional);

      await device.buy(monthly, offer: comeBack);

      expect(signed, <String>['pro_monthly:come_back']);
      expect(apple.requests.single.offerSignature?.nonce, 'nonce-1');
    });
  });

  group('outside a store', () {
    test('the web opens the gateway checkout', () async {
      server = serverWith(gateway: _CheckoutGateway());
      final List<Uri> opened = <Uri>[];
      final DVPurchases web = deviceOn(null,
          channel: DVPurchaseChannel.web,
          openUrl: (Uri url) async => opened.add(url));

      final DVPurchaseOutcome outcome = await web.buy(monthly);

      expect(outcome, isA<DVPurchaseRedirected>());
      expect(opened, <Uri>[Uri.parse('https://checkout.example/1')]);
    });

    test('the web refuses cleanly when the backend has no gateway', () async {
      final DVPurchases web = deviceOn(null,
          channel: DVPurchaseChannel.desktop,
          openUrl: (Uri url) async => fail('nothing should open'));
      await expectLater(
        web.buy(monthly),
        throwsA(isA<DVPurchaseRefused>()
            .having((DVPurchaseRefused r) => r.code, 'code', 'DV-PURCHASE-009')),
      );
    });

    test('a store build with no store on the device refuses cleanly', () async {
      await expectLater(
        deviceOn(null, channel: DVPurchaseChannel.play).buy(monthly),
        throwsA(isA<DVPurchaseRefused>()
            .having((DVPurchaseRefused r) => r.code, 'code', 'DV-PURCHASE-009')),
      );
    });

    test('a Telegram Mini App pays in Stars and is verified on the server',
        () async {
      final List<Uri> opened = <Uri>[];
      final DVPurchases mini = deviceOn(null,
          channel: DVPurchaseChannel.telegram, openInvoice: (Uri url) async {
        opened.add(url);
        return 'paid';
      });

      final DVPurchaseOutcome outcome = await mini.buy(coins);

      expect(stars.invoices, <String>['coins:50'],
          reason: 'the declared Stars price, never a converted one');
      expect(opened.single.toString(), contains('invoice_1'));
      expect((outcome as DVPurchaseCompleted).consumed, <String>{'coins_100'});
    });

    test('a cancelled Stars invoice grants nothing', () async {
      final DVPurchases mini = deviceOn(null,
          channel: DVPurchaseChannel.telegram,
          openInvoice: (Uri url) async => 'cancelled');
      expect(await mini.buy(coins), isA<DVPurchaseCancelled>());
      expect(changes, isEmpty);
    });
  });

  test('the server half refuses device calls with a clear message', () {
    expect(() => server.buy(monthly), throwsStateError);
  });

  test('the device half has no ledger to read', () {
    final DVPurchases device = deviceOn(null);
    expect(() => device.ledger.find(DVStore.play, 'x'), throwsStateError);
  });
}

class _SigningBackend extends DVInProcessPurchaseBackend {
  _SigningBackend(super.server, this.signed, {required super.customer});
  final List<String> signed;

  @override
  Future<DVStoreOfferSignature> signOffer(String productId, String offerId) async {
    signed.add('$productId:$offerId');
    return const DVStoreOfferSignature(
        keyId: 'KEY', nonce: 'nonce-1', timestamp: 1, signature: 'c2ln');
  }
}

class _CheckoutGateway extends DVLocalBillingProvider {
  int sessions = 0;

  @override
  Future<DVBillingCheckoutSession> checkout({
    required BillingPlan plan,
    required Object customer,
  }) async {
    sessions += 1;
    return DVBillingCheckoutSession(
      id: 'cs_$sessions',
      plan: plan,
      customer: customer,
      createdAt: start,
      checkoutUrl: Uri.parse('https://checkout.example/$sessions'),
    );
  }
}
