/// The device half of `DV.Purchases`: the purchase sheet, the receipt handed
/// to the server, and the entitlements the server sends back.
///
/// Nothing here decides whether a purchase happened. The store's sheet says
/// it did, the device sends the receipt to its own backend, the backend asks
/// the store, and only then is the transaction finished and the entitlement
/// shown. Each step exists because skipping it is silent:
///
/// * A transaction finished before the server saw it is one StoreKit never
///   delivers again, so a crash in between is a purchase nobody can grant.
/// * A Play purchase the server never accepted is left unacknowledged on
///   purpose: Play refunds it after three days, which is the right answer
///   for a receipt that did not verify.
/// * A consumable never consumed cannot be bought a second time on Play.
/// * Ask to Buy and slow payment methods finish later, often on another
///   screen. They arrive on the store's update stream, which is listened to
///   for the life of the application rather than only during a purchase.
library dartvel.purchases.device;

import 'dart:async';
import 'dart:convert';

import '../../dartvel.dart' show Entitlement;
import '../billing/money.dart';
import '../observability/observability.dart';
import 'purchases.dart';

/// What kind of offer a store lists against a product.
enum DVStoreOfferKind {
  /// A first-time price: pay as you go or pay up front, for new subscribers.
  introductory,

  /// A first-time period at no charge.
  freeTrial,

  /// An App Store promotional offer, opened with a server signature, or a
  /// Play developer-determined offer.
  promotional,

  /// An App Store win-back offer for lapsed subscribers.
  winBack,

  /// A Play base plan with no offer on it.
  basePlan,
}

/// One offer a store lists for a product, with its own price and period.
class DVStoreOffer {
  const DVStoreOffer({
    required this.id,
    required this.kind,
    this.price,
    this.displayPrice,
    this.period,
    this.periods = 1,
    this.token,
    this.eligible = true,
  });

  /// The offer identifier the store knows: the App Store offer id, the Play
  /// offer id (or base plan id for [DVStoreOfferKind.basePlan]).
  final String id;
  final DVStoreOfferKind kind;

  /// Each period's price in the customer's currency, from the store. Null
  /// for a free trial.
  final DVMoney? price;

  /// The store's own formatting of [price]. Shown as is.
  final String? displayPrice;

  /// ISO 8601 duration of one period, such as `P1W`.
  final String? period;

  /// How many [period]s the offer lasts.
  final int periods;

  /// Play's `offerToken`, which the purchase must carry. Null on the App
  /// Store.
  final String? token;

  /// Whether the store says the signed-in store account can take it. An
  /// introductory offer already used is listed and not eligible.
  final bool eligible;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.name,
        if (price != null)
          'price': <String, Object?>{
            'amount': price!.amount,
            'currency': price!.currency,
          },
        if (displayPrice != null) 'displayPrice': displayPrice,
        if (period != null) 'period': period,
        'periods': periods,
        if (token != null) 'token': token,
        'eligible': eligible,
      };

  static DVStoreOffer fromJson(Map<String, Object?> json) => DVStoreOffer(
        id: json['id']! as String,
        kind: DVStoreOfferKind.values.byName(json['kind']! as String),
        price: dvMoneyFromJson(json['price']),
        displayPrice: json['displayPrice'] as String?,
        period: json['period'] as String?,
        periods: (json['periods'] as int?) ?? 1,
        token: json['token'] as String?,
        eligible: json['eligible'] != false,
      );
}

/// A store product as this device's store lists it.
class DVStoreListing {
  const DVStoreListing({
    required this.storeProductId,
    required this.title,
    required this.displayPrice,
    this.productId,
    this.description = '',
    this.price,
    this.period,
    this.offers = const <DVStoreOffer>[],
  });

  /// The application's product id, set when the listing is matched to a
  /// declared product.
  final String? productId;
  final String storeProductId;
  final String title;
  final String description;

  /// The store's price in the customer's own currency, exactly, when it can
  /// be read as integer minor units. Never converted.
  final DVMoney? price;

  /// The store's own formatting of the price. What a button shows.
  final String displayPrice;

  /// A subscription's ISO 8601 billing period, or null.
  final String? period;
  final List<DVStoreOffer> offers;

  DVStoreListing _matched(String productId) => DVStoreListing(
        productId: productId,
        storeProductId: storeProductId,
        title: title,
        description: description,
        price: price,
        displayPrice: displayPrice,
        period: period,
        offers: offers,
      );

  static DVStoreListing fromJson(Map<String, Object?> json) => DVStoreListing(
        storeProductId: json['storeProductId']! as String,
        title: (json['title'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        displayPrice: (json['displayPrice'] as String?) ?? '',
        price: dvMoneyFromJson(json['price']),
        period: json['period'] as String?,
        offers: <DVStoreOffer>[
          for (final Object? offer
              in (json['offers'] as List<Object?>?) ?? const <Object?>[])
            DVStoreOffer.fromJson(
                (offer! as Map<Object?, Object?>).cast<String, Object?>()),
        ],
      );
}

/// What a device asks its store to sell.
class DVStorePurchaseRequest {
  const DVStorePurchaseRequest({
    required this.storeProductId,
    required this.kind,
    required this.appAccountToken,
    this.offer,
    this.offerSignature,
    this.quantity = 1,
  });

  final String storeProductId;
  final DVPurchaseKind kind;

  /// [DVPurchases.accountTokenFor] the signed-in person, from the server:
  /// StoreKit's `appAccountToken`, Play's obfuscated account id.
  final String appAccountToken;
  final DVStoreOffer? offer;

  /// The server's signature, for an App Store promotional offer.
  final DVStoreOfferSignature? offerSignature;

  /// Consumables only; the App Store allows more than one per purchase.
  final int quantity;

  Map<String, Object?> toJson() => <String, Object?>{
        'storeProductId': storeProductId,
        'kind': kind.name,
        'appAccountToken': appAccountToken,
        if (offer != null) 'offer': offer!.toJson(),
        if (offerSignature != null) 'offerSignature': offerSignature!.toJson(),
        'quantity': quantity,
      };
}

/// Whether a store transaction has been paid for yet.
enum DVStoreTransactionState { purchased, pending }

/// A transaction as the device's store reports it. Not evidence of anything
/// until the server has verified [receipt].
class DVStoreDeviceTransaction {
  const DVStoreDeviceTransaction({
    required this.store,
    required this.storeProductId,
    required this.transactionId,
    required this.receipt,
    this.state = DVStoreTransactionState.purchased,
    this.quantity = 1,
  });

  final DVStore store;
  final String storeProductId;
  final String transactionId;

  /// What the server verifies: the StoreKit 2 signed transaction (JWS), or
  /// the Play purchase as JSON with its token, product and type.
  final String receipt;
  final DVStoreTransactionState state;
  final int quantity;

  static DVStoreDeviceTransaction fromJson(
          DVStore store, Map<String, Object?> json) =>
      DVStoreDeviceTransaction(
        store: store,
        storeProductId: json['storeProductId']! as String,
        transactionId: '${json['transactionId'] ?? ''}',
        receipt: (json['receipt'] as String?) ?? '',
        state: json['state'] == 'pending'
            ? DVStoreTransactionState.pending
            : DVStoreTransactionState.purchased,
        quantity: (json['quantity'] as int?) ?? 1,
      );
}

/// What the store's sheet ended with.
sealed class DVStorePurchaseOutcome {
  const DVStorePurchaseOutcome();
}

final class DVStorePurchased extends DVStorePurchaseOutcome {
  const DVStorePurchased(this.transaction);
  final DVStoreDeviceTransaction transaction;
}

/// Waiting for a parent's approval (Ask to Buy) or a slow payment method.
/// The transaction, when it comes, arrives on [DVStoreClient.updates].
final class DVStorePending extends DVStorePurchaseOutcome {
  const DVStorePending();
}

final class DVStoreCancelled extends DVStorePurchaseOutcome {
  const DVStoreCancelled();
}

final class DVStoreFailed extends DVStorePurchaseOutcome {
  const DVStoreFailed(this.reason);
  final String reason;
}

/// The platform's purchase sheet: StoreKit 2, Play Billing, or a fake.
///
/// An implementation never verifies anything. It opens the sheet, reports
/// what the store said, and finishes what it is told to finish.
abstract class DVStoreClient {
  DVStore get store;

  /// Whether the store can sell on this device now: Play Billing connected,
  /// StoreKit 2 present and purchases allowed.
  Future<bool> available();

  /// The store's listing of each of [storeProductIds] it knows.
  Future<List<DVStoreListing>> listings(Set<String> storeProductIds);

  Future<DVStorePurchaseOutcome> purchase(DVStorePurchaseRequest request);

  /// Transactions arriving outside a purchase call: an approved Ask to Buy,
  /// a pending payment completed, a renewal, a purchase on another device.
  Stream<DVStoreDeviceTransaction> get updates;

  /// What this store account owns now. [sync] asks the store to refresh
  /// first (`AppStore.sync()`), which may show a sign-in prompt, so only an
  /// explicit restore passes it.
  Future<List<DVStoreDeviceTransaction>> owned({bool sync = false});

  /// Finishes [transaction] once the server has accepted it: StoreKit's
  /// `finish()`, or Play's consume when [consume].
  Future<void> finish(DVStoreDeviceTransaction transaction,
      {required bool consume});
}

/// The server's answer to receipts a device presented.
class DVPurchaseVerdict {
  const DVPurchaseVerdict({required this.results, required this.snapshots});
  final List<DVPurchaseResult> results;

  /// What the signed-in person holds afterwards.
  final List<DVEntitlementSnapshot> snapshots;

  Map<String, Object?> toJson() => <String, Object?>{
        'results': <Object?>[for (final DVPurchaseResult r in results) r.toJson()],
        'snapshots': <Object?>[
          for (final DVEntitlementSnapshot s in snapshots) s.toJson()
        ],
      };

  static DVPurchaseVerdict fromJson(Map<String, Object?> json) =>
      DVPurchaseVerdict(
        results: <DVPurchaseResult>[
          for (final Object? r
              in (json['results'] as List<Object?>?) ?? const <Object?>[])
            DVPurchaseResult.fromJson(
                (r! as Map<Object?, Object?>).cast<String, Object?>()),
        ],
        snapshots: dvSnapshotsFromJson(json['snapshots']),
      );
}

/// The device's view of its own backend, for purchases.
///
/// Every call is made as the signed-in person: the server reads who from the
/// session, never from anything in the request.
abstract class DVPurchaseBackend {
  /// The account token the store must carry for the signed-in person.
  Future<String> accountToken();

  /// Verifies [receipts] from [store] and answers with what is now held.
  Future<DVPurchaseVerdict> verify(DVStore store, List<String> receipts);

  Future<List<DVEntitlementSnapshot>> entitlements();

  /// The gateway's checkout page for [productId].
  Future<Uri> checkout(String productId);

  /// A Telegram Stars invoice for [productId].
  Future<DVStoreInvoice> invoice(String productId);

  /// The server's signature for App Store promotional offer [offerId].
  Future<DVStoreOfferSignature> signOffer(String productId, String offerId);
}

/// A backend that is the server object itself, in the same process: for
/// tests, and for a desktop application that is its own server.
class DVInProcessPurchaseBackend implements DVPurchaseBackend {
  DVInProcessPurchaseBackend(this.server, {required this.customer});

  final DVPurchases server;
  final Object customer;

  DVPurchaseProduct _product(String id) =>
      server.productById(id) ??
      (throw DVPurchaseRefused('"$id" is not a declared product',
          code: 'DV-PURCHASE-004'));

  @override
  Future<String> accountToken() async => DVPurchases.accountTokenFor(customer);

  @override
  Future<DVPurchaseVerdict> verify(DVStore store, List<String> receipts) async {
    final List<DVPurchaseResult> results = await server.restore(
        customer: customer, store: store, receipts: receipts);
    return DVPurchaseVerdict(
        results: results, snapshots: await server.snapshots(customer));
  }

  @override
  Future<List<DVEntitlementSnapshot>> entitlements() =>
      server.snapshots(customer);

  @override
  Future<Uri> checkout(String productId) =>
      server.checkout(_product(productId), customer: customer);

  @override
  Future<DVStoreInvoice> invoice(String productId) =>
      server.invoice(_product(productId), customer: customer);

  @override
  Future<DVStoreOfferSignature> signOffer(String productId, String offerId) =>
      server.signOffer(_product(productId), offerId, customer: customer);
}

/// Sends one request to the application's backend as the signed-in person
/// and answers with the status and body. `dartvel_flutter` supplies one that
/// carries the session.
typedef DVPurchaseSend = Future<(int status, String body)> Function(
    String method, String path, Map<String, Object?>? body);

/// [DVPurchaseBackend] over the generated `/_dartvel/purchases` endpoints.
class DVHttpPurchaseBackend implements DVPurchaseBackend {
  DVHttpPurchaseBackend(this.send);

  final DVPurchaseSend send;

  /// The endpoint paths, under the API base path. One list, read by the
  /// generated server and by this client.
  static const String accountTokenPath = '/_dartvel/purchases/account-token';
  static const String verifyPath = '/_dartvel/purchases/verify';
  static const String entitlementsPath = '/_dartvel/purchases/entitlements';
  static const String checkoutPath = '/_dartvel/purchases/checkout';
  static const String invoicePath = '/_dartvel/purchases/invoice';
  static const String offerSignaturePath = '/_dartvel/purchases/offer-signature';
  static const String appleNotificationsPath =
      '/_dartvel/purchases/notifications/apple';
  static const String playNotificationsPath =
      '/_dartvel/purchases/notifications/play';
  static const String telegramNotificationsPath =
      '/_dartvel/purchases/notifications/telegram';

  String? _token;

  Future<Map<String, Object?>> _call(
      String method, String path, Map<String, Object?>? body) async {
    final (int status, String text) = await send(method, path, body);
    Object? json;
    try {
      json = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      json = null;
    }
    final Map<String, Object?> map = json is Map
        ? json.cast<String, Object?>()
        : const <String, Object?>{};
    if (status >= 200 && status < 300) return map;
    if (status == 409 || status == 422) {
      throw DVPurchaseRefused(
          (map['reason'] as String?) ?? 'the server refused the purchase',
          code: map['code'] as String?);
    }
    if (status == 401) {
      throw const DVPurchaseRefused(
          'nobody is signed in; a purchase is made for an account');
    }
    throw DVStoreUnavailable('the purchases endpoint answered $status');
  }

  @override
  Future<String> accountToken() async => _token ??=
      (await _call('GET', accountTokenPath, null))['token']! as String;

  @override
  Future<DVPurchaseVerdict> verify(DVStore store, List<String> receipts) async =>
      DVPurchaseVerdict.fromJson(await _call('POST', verifyPath,
          <String, Object?>{'store': store.name, 'receipts': receipts}));

  @override
  Future<List<DVEntitlementSnapshot>> entitlements() async =>
      dvSnapshotsFromJson(
          (await _call('GET', entitlementsPath, null))['snapshots']);

  @override
  Future<Uri> checkout(String productId) async => Uri.parse((await _call(
          'POST', checkoutPath, <String, Object?>{'product': productId}))['url']!
      as String);

  @override
  Future<DVStoreInvoice> invoice(String productId) async =>
      DVStoreInvoice.fromJson(await _call(
          'POST', invoicePath, <String, Object?>{'product': productId}));

  @override
  Future<DVStoreOfferSignature> signOffer(
          String productId, String offerId) async =>
      DVStoreOfferSignature.fromJson(await _call('POST', offerSignaturePath,
          <String, Object?>{'product': productId, 'offer': offerId}));
}

/// What a purchase came to, as the application sees it.
sealed class DVPurchaseOutcome {
  const DVPurchaseOutcome();
}

/// Verified by the server and finished.
final class DVPurchaseCompleted extends DVPurchaseOutcome {
  const DVPurchaseCompleted({
    this.granted = const <Entitlement>{},
    this.consumed = const <String>{},
  });
  final Set<Entitlement> granted;

  /// Consumable product ids credited by this purchase.
  final Set<String> consumed;
}

/// Waiting for approval or payment. When it completes, the entitlement
/// arrives through [DVPurchases.entitlementChanges] like any other.
final class DVPurchasePending extends DVPurchaseOutcome {
  const DVPurchasePending();
}

final class DVPurchaseCancelled extends DVPurchaseOutcome {
  const DVPurchaseCancelled();
}

/// The gateway's checkout page was opened. The grant arrives from the
/// gateway's webhook and reaches the device at its next sync.
final class DVPurchaseRedirected extends DVPurchaseOutcome {
  const DVPurchaseRedirected(this.url);
  final Uri url;
}

/// The store failed, the server refused the receipt, or the server could not
/// be reached. An unreached server leaves the transaction unfinished, so it
/// is presented again at the next launch or restore.
final class DVPurchaseFailed extends DVPurchaseOutcome {
  const DVPurchaseFailed(this.reason, {this.code});
  final String reason;
  final String? code;
}

/// The device half behind [DVPurchases.device].
class DVPurchaseDevice {
  DVPurchaseDevice({
    required List<DVPurchaseProduct> products,
    required this.policy,
    DVStoreClient? store,
    DVPurchaseBackend? backend,
    DVPurchaseChannel? channel,
    DateTime Function()? clock,
    DVLogger? logger,
    Future<void> Function(Uri url)? openUrl,
    Future<String> Function(Uri url)? openInvoice,
  })  : products = List<DVPurchaseProduct>.unmodifiable(products),
        _store = store,
        _backend = backend,
        _channel = channel,
        _clock = clock ?? DateTime.now,
        _logger = logger,
        _openUrl = openUrl,
        _openInvoice = openInvoice;

  /// Set by `dartvel_flutter` for the running platform: the store client,
  /// the backend over the signed-in session, the channel this build sells
  /// from, and how a URL and a Telegram invoice are opened.
  static DVStoreClient? Function(DVPurchaseChannel channel)? storeResolver;
  static DVPurchaseBackend? Function()? backendResolver;
  static DVPurchaseChannel Function()? channelResolver;
  static Future<void> Function(Uri url)? urlOpener;
  static Future<String> Function(Uri url)? invoiceOpener;

  final List<DVPurchaseProduct> products;
  final DVStorePolicy policy;
  final DateTime Function() _clock;
  final DVLogger? _logger;
  final Future<void> Function(Uri url)? _openUrl;
  final Future<String> Function(Uri url)? _openInvoice;

  DVStoreClient? _store;
  bool _storeResolved = false;
  DVPurchaseBackend? _backend;
  DVPurchaseChannel? _channel;
  StreamSubscription<DVStoreDeviceTransaction>? _updates;

  List<DVEntitlementSnapshot> _snapshots = const <DVEntitlementSnapshot>[];
  bool _synced = false;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  DVLogger get _log => _logger ?? DVObservability.logger;

  /// Each time what the device holds changes.
  Stream<void> get changes => _changes.stream;

  /// The channel this build sells from.
  DVPurchaseChannel get channel => _channel ??=
      channelResolver?.call() ?? DVPurchaseChannel.desktop;

  DVPurchaseBackend get _server =>
      _backend ??= backendResolver?.call() ??
          (throw const DVPurchaseRefused(
              'there is no backend to verify purchases with',
              code: 'DV-PURCHASE-009'));

  DVStoreClient? get _client {
    if (!_storeResolved) {
      _storeResolved = true;
      _store ??= storeResolver?.call(channel);
    }
    final DVStoreClient? client = _store;
    if (client != null) start();
    return client;
  }

  /// Starts listening to the store's updates, once. Called on first use and
  /// by `dartvel_flutter` at startup: StoreKit delivers transactions that
  /// completed while the application was closed only to a listener.
  void start() {
    final DVStoreClient? client = _store;
    if (client == null || _updates != null) return;
    _updates = client.updates.listen((DVStoreDeviceTransaction transaction) {
      if (transaction.state == DVStoreTransactionState.pending) return;
      unawaited(_settle(client, transaction).then((_) {}, onError: (Object e) {
        _log.log('A store update could not be settled and will be presented '
            'again: $e', level: DVLogLevel.warn);
      }));
    });
  }

  /// Stops listening to the store. For a test, or an application tearing
  /// its purchases down.
  Future<void> dispose() async {
    await _updates?.cancel();
    _updates = null;
    await _changes.close();
  }

  DVStore? _storeFor(DVPurchaseChannel channel) => switch (channel) {
        DVPurchaseChannel.appStore => DVStore.appStore,
        DVPurchaseChannel.play => DVStore.play,
        DVPurchaseChannel.telegram => DVStore.telegram,
        DVPurchaseChannel.web || DVPurchaseChannel.desktop => null,
      };

  DVPurchaseProduct? _byStoreId(DVStore store, String storeProductId) {
    for (final DVPurchaseProduct product in products) {
      if (product.identifierOn(store) == storeProductId) return product;
    }
    return null;
  }

  Never _noPath(String why) =>
      throw DVPurchaseRefused(why, code: 'DV-PURCHASE-009');

  bool holds(Entitlement entitlement) => DVEntitlementSnapshots(_snapshots,
          clock: _clock, logger: _logger)
      .entitled(entitlement);

  Future<bool> entitled(Entitlement entitlement) async {
    if (!_synced) {
      try {
        await refresh();
      } on Exception catch (error) {
        // Offline: what the device held last still holds until its notAfter.
        _log.log('Entitlements could not be refreshed: $error',
            level: DVLogLevel.info);
      }
    }
    return holds(entitlement);
  }

  /// Asks the backend what the signed-in person holds. Also starts listening
  /// to the store, so calling it at startup is what catches a transaction
  /// that completed while the application was closed.
  Future<void> refresh() async {
    _client;
    _hold(await _server.entitlements());
  }

  void _hold(List<DVEntitlementSnapshot> snapshots) {
    _synced = true;
    final String before = jsonEncode(
        <Object?>[for (final DVEntitlementSnapshot s in _snapshots) s.toJson()]);
    final String after = jsonEncode(
        <Object?>[for (final DVEntitlementSnapshot s in snapshots) s.toJson()]);
    _snapshots = List<DVEntitlementSnapshot>.unmodifiable(snapshots);
    if (before != after) _changes.add(null);
  }

  Future<List<DVStoreListing>> listings() async {
    final DVStore? store = _storeFor(channel);
    final DVStoreClient? client = _client;
    if (store == null || client == null || store == DVStore.telegram) {
      return const <DVStoreListing>[];
    }
    final Map<String, DVPurchaseProduct> wanted = <String, DVPurchaseProduct>{
      for (final DVPurchaseProduct product in products)
        if (product.identifierOn(store) case final String id) id: product,
    };
    final List<DVStoreListing> listed;
    try {
      listed = await client.listings(wanted.keys.toSet());
    } on Exception catch (error) {
      _log.log(
        'DV-PURCHASE-007: the store could not be read ($error); no price is '
        'shown rather than a converted one',
        level: DVLogLevel.warn,
        code: 'DV-PURCHASE-007',
      );
      return const <DVStoreListing>[];
    }
    return <DVStoreListing>[
      for (final DVStoreListing listing in listed)
        if (wanted[listing.storeProductId] case final DVPurchaseProduct product)
          listing._matched(product.id),
    ];
  }

  Future<DVPurchaseOutcome> buy(
    DVPurchaseProduct product, {
    DVStoreOffer? offer,
    int quantity = 1,
  }) async {
    final DVPurchaseChannel channel = this.channel;
    final DVPurchaseRoute route =
        policy.route(product: product, channel: channel);
    if (route == DVPurchaseRoute.gateway) {
      if (channel != DVPurchaseChannel.web &&
          channel != DVPurchaseChannel.desktop) {
        // A physical good in a store build: Billing's own checkout, which
        // the application opens through DV.Billing.
        _noPath('${product.id} is sold through Billing on ${channel.name}; '
            'open it with DV.Billing.checkout');
      }
      final Future<void> Function(Uri url)? open = _openUrl ?? urlOpener;
      if (open == null) _noPath('this build has no way to open a checkout page');
      final Uri url = await _server.checkout(product.id);
      await open(url);
      return DVPurchaseRedirected(url);
    }

    final DVStore store = _storeFor(channel)!;
    if (store == DVStore.telegram) return _buyWithStars(product);

    final DVStoreClient? client = _client;
    if (client == null || client.store != store) {
      _noPath('this device has no ${store.name} store to sell through');
    }
    if (!await client.available()) {
      _noPath('the ${store.name} store cannot sell on this device now');
    }
    final String token = await _server.accountToken();
    DVStoreOfferSignature? signature;
    if (offer != null &&
        store == DVStore.appStore &&
        offer.kind == DVStoreOfferKind.promotional) {
      signature = await _server.signOffer(product.id, offer.id);
    }
    final DVStorePurchaseOutcome outcome =
        await client.purchase(DVStorePurchaseRequest(
      storeProductId: product.identifierOn(store)!,
      kind: product.kind,
      appAccountToken: token,
      offer: offer,
      offerSignature: signature,
      quantity: quantity,
    ));
    switch (outcome) {
      case DVStoreCancelled():
        return const DVPurchaseCancelled();
      case DVStorePending():
        return const DVPurchasePending();
      case DVStoreFailed(:final String reason):
        return DVPurchaseFailed(reason);
      case DVStorePurchased(:final DVStoreDeviceTransaction transaction):
        if (transaction.state == DVStoreTransactionState.pending) {
          return const DVPurchasePending();
        }
        try {
          final DVPurchaseResult result = await _settle(client, transaction);
          return _outcomeOf(result);
        } on DVStoreUnavailable catch (error) {
          return DVPurchaseFailed(
              'the purchase could not be verified yet and will be presented '
              'again: ${error.message}');
        } on DVPurchaseRefused catch (refusal) {
          return DVPurchaseFailed(refusal.reason, code: refusal.code);
        }
    }
  }

  DVPurchaseOutcome _outcomeOf(DVPurchaseResult result) => result.refused
      ? DVPurchaseFailed(result.reason ?? 'the server refused the receipt',
          code: result.code)
      : DVPurchaseCompleted(granted: result.granted, consumed: result.consumed);

  Future<DVPurchaseOutcome> _buyWithStars(DVPurchaseProduct product) async {
    final Future<String> Function(Uri url)? open =
        _openInvoice ?? invoiceOpener;
    if (open == null) {
      _noPath('this build is not running inside Telegram, so it cannot open '
          'a Stars invoice');
    }
    final DVStoreInvoice invoice = await _server.invoice(product.id);
    final String status = await open(invoice.url);
    switch (status) {
      case 'paid':
        final DVPurchaseVerdict verdict =
            await _server.verify(DVStore.telegram, <String>[invoice.receipt]);
        _hold(verdict.snapshots);
        return _outcomeOf(verdict.results.single);
      case 'pending':
        return const DVPurchasePending();
      case 'cancelled':
        return const DVPurchaseCancelled();
      default:
        return DVPurchaseFailed('Telegram reported the invoice as $status');
    }
  }

  /// Hands [transaction] to the server and finishes it if the server
  /// accepted it. A refusal leaves it unfinished.
  Future<DVPurchaseResult> _settle(
      DVStoreClient client, DVStoreDeviceTransaction transaction) async {
    final DVPurchaseVerdict verdict =
        await _server.verify(client.store, <String>[transaction.receipt]);
    _hold(verdict.snapshots);
    final DVPurchaseResult result = verdict.results.single;
    if (!result.refused) {
      final DVPurchaseProduct? product =
          _byStoreId(client.store, transaction.storeProductId);
      await client.finish(transaction,
          consume: product?.kind == DVPurchaseKind.consumable);
    }
    return result;
  }

  Future<List<DVPurchaseResult>> restore() async {
    final DVStore? store = _storeFor(channel);
    final DVStoreClient? client =
        store == null || store == DVStore.telegram ? null : _client;
    if (client == null) {
      // The web, desktop and Telegram hold nothing on the device to present;
      // what the server knows is what there is.
      await refresh();
      return const <DVPurchaseResult>[];
    }
    final List<DVStoreDeviceTransaction> owned = <DVStoreDeviceTransaction>[
      for (final DVStoreDeviceTransaction t in await client.owned(sync: true))
        if (t.state == DVStoreTransactionState.purchased) t,
    ];
    if (owned.isEmpty) {
      await refresh();
      return const <DVPurchaseResult>[];
    }
    final DVPurchaseVerdict verdict = await _server.verify(client.store,
        <String>[for (final DVStoreDeviceTransaction t in owned) t.receipt]);
    _hold(verdict.snapshots);
    for (int i = 0; i < owned.length && i < verdict.results.length; i++) {
      if (verdict.results[i].refused) continue;
      final DVPurchaseProduct? product =
          _byStoreId(client.store, owned[i].storeProductId);
      await client.finish(owned[i],
          consume: product?.kind == DVPurchaseKind.consumable);
    }
    return verdict.results;
  }
}

/// A money object from `{amount, currency}`, or null.
DVMoney? dvMoneyFromJson(Object? json) {
  if (json is! Map) return null;
  final Object? amount = json['amount'];
  final Object? currency = json['currency'];
  if (amount is! int || currency is! String) return null;
  return DVMoney(amount: amount, currency: currency);
}

List<DVEntitlementSnapshot> dvSnapshotsFromJson(Object? json) =>
    <DVEntitlementSnapshot>[
      if (json is List)
        for (final Object? s in json)
          DVEntitlementSnapshot.fromJson(
              (s! as Map<Object?, Object?>).cast<String, Object?>()),
    ];
