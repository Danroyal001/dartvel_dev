/// Purchases through a store, and the entitlements they write.
///
/// On iOS and Android a digital good sold inside the application goes through
/// StoreKit or Play Billing, and the device then says what it bought. This is
/// the half that decides whether it did: a receipt is believed only from the
/// store's own answer to a server-side verification, store server
/// notifications land in the same ledger a purchase does, and what reaches a
/// device is a snapshot with an end.
///
/// Every rule here exists because its failure is silent. A receipt checked
/// on the device is checked by the code an attacker controls. A notification
/// applied in arrival order hands a refunded customer their access back when
/// a retried renewal lands behind the refund. A Play purchase granted and not
/// acknowledged is refunded by Play three days later while the application
/// goes on granting it. None of those throws, and each costs money.
///
/// What is not here: the StoreKit and Play Billing client bindings that open
/// a purchase sheet, the adapters that talk to Apple's and Google's servers,
/// and the generated entitlement models and endpoints. [DVStoreAdapter] is the
/// seam each of those adapters implements.
library dartvel.purchases;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../dartvel.dart' show Entitlement, dvBillingCustomerKey;
import '../billing/money.dart';
import '../observability/observability.dart';
import '../transaction/transaction.dart';

/// A store that sells digital goods inside an application.
enum DVStore { appStore, play }

/// What a store product is, which decides whether it has an end.
enum DVPurchaseKind {
  /// Renews, lapses and can be refunded: access ends at the paid period.
  subscription,

  /// Bought once and kept, until a refund or a revocation takes it back.
  nonConsumable,
}

/// Where the running build sells from.
///
/// Known at build time, never guessed at run time: a store build and a web
/// build of the same application are different binaries.
enum DVPurchaseChannel {
  /// iOS, iPadOS, tvOS, or macOS distributed through the App Store.
  appStore,

  /// Android distributed through Google Play.
  play,

  /// The web.
  web,

  /// Desktop outside a store.
  desktop,
}

/// Where a purchase goes.
enum DVPurchaseRoute {
  /// The store's own purchase flow.
  store,

  /// Billing's payment gateway.
  gateway,
}

/// Whether a good is digital or physical, declared rather than guessed.
///
/// A classifier that guessed from a model's fields would be wrong in both
/// directions: a physical good sent through a store loses its commission on a
/// margin that cannot carry it, and a digital good sent through a gateway is a
/// rejected submission.
sealed class DVBillable {
  const DVBillable();

  /// A digital good, with the product identifier each store knows it by.
  const factory DVBillable.digital({String? appStore, String? play}) =
      DVDigitalBillable;

  /// A physical good, sold through Billing's gateway on every platform.
  const factory DVBillable.physical({int? nativePrice, String? nativeCurrency}) =
      DVPhysicalBillable;
}

/// See [DVBillable.digital].
final class DVDigitalBillable extends DVBillable {
  const DVDigitalBillable({this.appStore, this.play});

  /// The App Store Connect product identifier.
  final String? appStore;

  /// The Play Console product identifier.
  final String? play;

  /// The identifier [store] knows this product by, or null when none was
  /// declared.
  String? identifierOn(DVStore store) => switch (store) {
        DVStore.appStore => appStore,
        DVStore.play => play,
      };
}

/// See [DVBillable.physical].
final class DVPhysicalBillable extends DVBillable {
  const DVPhysicalBillable({this.nativePrice, this.nativeCurrency});

  /// The gateway price in [nativeCurrency]'s minor units. Never a store price.
  final int? nativePrice;
  final String? nativeCurrency;
}

/// Something the application sells, and what owning it unlocks.
///
/// Normally generated from a model's `billable:` declaration. [id] is the
/// application's name for the product; the stores' names for it are on
/// [billable].
class DVPurchaseProduct {
  const DVPurchaseProduct(
    this.id, {
    required this.billable,
    required this.entitlements,
    this.kind = DVPurchaseKind.subscription,
  });

  final String id;
  final DVBillable billable;
  final Set<Entitlement> entitlements;
  final DVPurchaseKind kind;

  /// The identifier [store] sells this under, or null for a physical good or
  /// one not declared on that store.
  String? identifierOn(DVStore store) => switch (billable) {
        final DVDigitalBillable digital => digital.identifierOn(store),
        DVPhysicalBillable() => null,
      };

  @override
  String toString() => 'DVPurchaseProduct($id)';
}

/// A purchase as the store's server describes it.
///
/// Produced only by a [DVStoreAdapter] from a verified answer. Nothing a
/// device sends becomes one of these without passing through the store.
class DVStoreTransaction {
  const DVStoreTransaction({
    required this.store,
    required this.originalTransactionId,
    required this.transactionId,
    required this.storeProductId,
    required this.purchasedAt,
    required this.signedAt,
    this.expiresAt,
    this.graceEndsAt,
    this.revokedAt,
    this.appAccountToken,
    this.acknowledged = false,
    this.price,
  });

  final DVStore store;

  /// What stays the same across renewals: Apple's `originalTransactionId`,
  /// Play's purchase token. The ledger keeps one grant per value.
  final String originalTransactionId;

  /// This period's transaction: Apple's `transactionId`, Play's order id.
  final String transactionId;

  /// The store's product identifier, not the application's.
  final String storeProductId;

  final DateTime purchasedAt;

  /// When the store produced this answer. Orders the answers about one
  /// purchase, since neither store delivers them in order.
  final DateTime signedAt;

  /// The end of the paid period, or null for a purchase that does not expire.
  final DateTime? expiresAt;

  /// The end of the store's billing grace period, when it is in one.
  final DateTime? graceEndsAt;

  /// When the store took the purchase back: a refund, a chargeback, a family
  /// sharing revocation. Null while it stands.
  final DateTime? revokedAt;

  /// The application account the purchase was made for: Apple's
  /// `appAccountToken`, Play's obfuscated account id. The client sets it from
  /// [DVPurchases.accountTokenFor] when it opens the purchase sheet.
  final String? appAccountToken;

  /// Whether the store has recorded an acknowledgement.
  final bool acknowledged;

  /// What the customer paid, in integer minor units, when the store says.
  final DVMoney? price;

  /// The end of access: the paid period with the store's grace added.
  DateTime? get notAfter {
    final DateTime? expires = expiresAt;
    if (expires == null) return null;
    final DateTime? grace = graceEndsAt;
    return grace != null && grace.isAfter(expires) ? grace : expires;
  }
}

/// A store server notification, after its signature was verified.
class DVStoreNotification {
  const DVStoreNotification({
    required this.notificationId,
    required this.type,
    required this.signedAt,
    required this.transaction,
  });

  /// Apple's `notificationUUID`, the Pub/Sub message id for Play.
  final String notificationId;

  /// The store's notification type, kept for the record. What changes is read
  /// from [transaction] rather than from this, so a type Dartvel has never
  /// heard of still lands correctly.
  final String type;
  final DateTime signedAt;

  /// The purchase's state as of this notification, from the store.
  final DVStoreTransaction transaction;
}

/// A notification body with the headers that sign it.
class DVSignedStoreNotification {
  const DVSignedStoreNotification({required this.body, required this.headers});
  final String body;
  final Map<String, String> headers;
}

/// The store looked at a receipt or notification and said no.
///
/// A verdict, which is different from [DVStoreUnavailable]: a refusal is
/// final, an outage is retried.
class DVStoreRefusal implements Exception {
  const DVStoreRefusal(this.store, this.reason);
  final DVStore store;
  final String reason;

  @override
  String toString() => 'DVStoreRefusal(${store.name}): $reason';
}

/// The store could not be asked. Nothing was decided and nothing written.
class DVStoreUnavailable implements Exception {
  const DVStoreUnavailable(this.message);
  final String message;

  @override
  String toString() => 'DVStoreUnavailable: $message';
}

/// Dartvel refused to grant anything for a purchase, and why.
class DVPurchaseRefused implements Exception {
  const DVPurchaseRefused(this.reason, {this.code});
  final String reason;

  /// The diagnostic code, when there is one.
  final String? code;

  @override
  String toString() =>
      'DVPurchaseRefused: ${code == null ? '' : '$code: '}$reason';
}

/// One store's server-side verification.
///
/// An implementation calls the store's own endpoints with credentials from
/// Secrets and Environments. There is deliberately no implementation that
/// runs on a device: the code checking a receipt there is the code an
/// attacker controls.
abstract class DVStoreAdapter {
  DVStore get store;

  /// How long the store waits for an acknowledgement before refunding, or
  /// null when it needs none. Play: three days. The App Store: null.
  Duration? get acknowledgementWindow;

  /// Asks the store about [receipt] -- a StoreKit signed transaction or a Play
  /// purchase token -- and returns its answer.
  ///
  /// Throws [DVStoreRefusal] when the store refuses it and
  /// [DVStoreUnavailable] when the store cannot be reached.
  Future<DVStoreTransaction> verifyReceipt(String receipt);

  /// Verifies a store server notification's signature and returns what it
  /// says, re-reading the purchase from the store where the notification does
  /// not carry it (Play's do not).
  ///
  /// Throws [DVStoreRefusal] for a signature that does not verify.
  Future<DVStoreNotification> verifyNotification(
    String body,
    Map<String, String> headers,
  );

  /// Tells the store the purchase was granted.
  Future<void> acknowledge({
    required String originalTransactionId,
    required String transactionId,
    required String storeProductId,
  });
}

/// One purchase's standing in the ledger: who holds it and until when.
///
/// Server-authored. A device never writes one, because the only evidence that
/// would justify it is a receipt the server validates.
class DVPurchaseGrant {
  const DVPurchaseGrant({
    required this.store,
    required this.originalTransactionId,
    required this.transactionId,
    required this.customerKey,
    required this.productId,
    required this.storeProductId,
    required this.purchasedAt,
    required this.notAfter,
    required this.acknowledged,
    required this.lastEventAt,
    this.revokedAt,
  });

  final DVStore store;
  final String originalTransactionId;
  final String transactionId;

  /// The holder, as [dvBillingCustomerKey] names them.
  final String customerKey;

  /// The application's product id.
  final String productId;
  final String storeProductId;
  final DateTime purchasedAt;

  /// The end of access, or null for a purchase that does not expire.
  final DateTime? notAfter;
  final DateTime? revokedAt;

  /// Whether the store has been told. False past the store's window is
  /// `DV-PURCHASE-006`.
  final bool acknowledged;

  /// The store time of the newest answer applied. An older one is stale.
  final DateTime lastEventAt;

  /// Whether this grant gives access at [now].
  bool activeAt(DateTime now) {
    if (revokedAt != null) return false;
    final DateTime? end = notAfter;
    return end == null || now.isBefore(end);
  }

  DVPurchaseGrant _acknowledged() => DVPurchaseGrant(
        store: store,
        originalTransactionId: originalTransactionId,
        transactionId: transactionId,
        customerKey: customerKey,
        productId: productId,
        storeProductId: storeProductId,
        purchasedAt: purchasedAt,
        notAfter: notAfter,
        revokedAt: revokedAt,
        acknowledged: true,
        lastEventAt: lastEventAt,
      );
}

/// Where grants are kept.
///
/// This is the server-side table the generated entitlement models are read
/// from. It is not a second entitlement store: there is no `DV.Entitlements`,
/// and nothing on a device reads it directly.
abstract class DVPurchaseLedger {
  Future<DVPurchaseGrant?> find(DVStore store, String originalTransactionId);

  /// Writes [grant], replacing any grant for the same purchase.
  Future<void> put(DVPurchaseGrant grant);
  Future<void> remove(DVStore store, String originalTransactionId);
  Future<List<DVPurchaseGrant>> forCustomer(String customerKey);
  Future<List<DVPurchaseGrant>> unacknowledged();

  /// Records that [notificationId] is being applied. False when it already
  /// was: a replay.
  Future<bool> claimNotification(DVStore store, String notificationId);

  /// Undoes a claim whose application failed, so the store's retry applies.
  Future<void> releaseNotification(DVStore store, String notificationId);
}

/// A ledger in memory, for tests and development. A restart loses it.
class DVMemoryPurchaseLedger implements DVPurchaseLedger {
  final Map<String, DVPurchaseGrant> _grants = <String, DVPurchaseGrant>{};
  final Set<String> _claims = <String>{};

  static String _key(DVStore store, String id) => '${store.name} $id';

  @override
  Future<DVPurchaseGrant?> find(
          DVStore store, String originalTransactionId) async =>
      _grants[_key(store, originalTransactionId)];

  @override
  Future<void> put(DVPurchaseGrant grant) async {
    _grants[_key(grant.store, grant.originalTransactionId)] = grant;
  }

  @override
  Future<void> remove(DVStore store, String originalTransactionId) async {
    _grants.remove(_key(store, originalTransactionId));
  }

  @override
  Future<List<DVPurchaseGrant>> forCustomer(String customerKey) async =>
      <DVPurchaseGrant>[
        for (final DVPurchaseGrant grant in _grants.values)
          if (grant.customerKey == customerKey) grant,
      ];

  @override
  Future<List<DVPurchaseGrant>> unacknowledged() async => <DVPurchaseGrant>[
        for (final DVPurchaseGrant grant in _grants.values)
          if (!grant.acknowledged) grant,
      ];

  @override
  Future<bool> claimNotification(DVStore store, String notificationId) async =>
      _claims.add(_key(store, notificationId));

  @override
  Future<void> releaseNotification(DVStore store, String notificationId) async {
    _claims.remove(_key(store, notificationId));
  }
}

/// Entitlements a customer gained or lost, after the change committed.
class DVPurchaseChange {
  const DVPurchaseChange({
    required this.customerKey,
    required this.store,
    required this.originalTransactionId,
    required this.granted,
    required this.revoked,
    this.notificationId,
    this.revokedAt,
  });

  final String customerKey;
  final DVStore store;
  final String originalTransactionId;
  final Set<String> granted;
  final Set<String> revoked;

  /// The notification that caused it, or null for a verified receipt.
  final String? notificationId;

  /// When the store took the purchase back -- a refund, a chargeback, a
  /// revocation -- or null.
  ///
  /// What separates a refund from a lapse. Both revoke the same entitlements,
  /// and only one of them is money going back: a handler that reversed stock
  /// and credits on every revocation would reverse them for every
  /// subscription that simply ran out.
  final DateTime? revokedAt;
}

/// What a verification or notification did.
class DVPurchaseResult {
  const DVPurchaseResult({
    this.handled = false,
    this.replayed = false,
    this.stale = false,
    this.undeclared = false,
    this.unattributed = false,
    this.refused = false,
    this.reason,
    this.customerKey,
    this.granted = const <Entitlement>{},
    this.revoked = const <Entitlement>{},
  });

  /// Whether the ledger was written.
  final bool handled;

  /// The notification was already applied.
  final bool replayed;

  /// The answer is older than one already applied to the same purchase.
  final bool stale;

  /// The store named a product the project does not declare:
  /// `DV-PURCHASE-004`.
  final bool undeclared;

  /// A notification for a purchase no application user has presented yet.
  /// Nothing is granted; the purchase is granted when its receipt is
  /// verified, from the store's state at that moment.
  final bool unattributed;

  /// Refused, with [reason]. Only restore reports refusals as results.
  final bool refused;
  final String? reason;
  final String? customerKey;
  final Set<Entitlement> granted;
  final Set<Entitlement> revoked;

  /// Each of these is acknowledged to the store: none is a reason for the
  /// store to retry.
  static const DVPurchaseResult _replayed = DVPurchaseResult(replayed: true);
  static const DVPurchaseResult _stale = DVPurchaseResult(stale: true);
  static const DVPurchaseResult _undeclared = DVPurchaseResult(undeclared: true);
  static const DVPurchaseResult _unattributed =
      DVPurchaseResult(unattributed: true);
}

/// An entitlement as a device holds it: what, and until when.
class DVEntitlementSnapshot {
  const DVEntitlementSnapshot({
    required this.entitlement,
    required this.notAfter,
  });

  /// The entitlement's id.
  final String entitlement;

  /// The moment access stops without a fresh sync. Always present: a snapshot
  /// with no end is a refunded subscription that keeps working on a device
  /// that never reconnects.
  final DateTime notAfter;

  Map<String, Object?> toJson() => <String, Object?>{
        'entitlement': entitlement,
        'notAfter': notAfter.toUtc().toIso8601String(),
      };
}

/// The entitlement snapshots a device holds, checked against its clock.
class DVEntitlementSnapshots {
  DVEntitlementSnapshots(
    List<DVEntitlementSnapshot> snapshots, {
    DateTime Function()? clock,
    DVLogger? logger,
  })  : snapshots = List<DVEntitlementSnapshot>.unmodifiable(snapshots),
        _clock = clock ?? DateTime.now,
        _logger = logger;

  final List<DVEntitlementSnapshot> snapshots;
  final DateTime Function() _clock;
  final DVLogger? _logger;

  /// Whether a snapshot for [entitlement] is still inside its `notAfter`.
  ///
  /// At `notAfter` itself access has stopped. A snapshot that has passed it
  /// refuses with `DV-PURCHASE-005`; an entitlement never held refuses
  /// silently, since that is not news.
  bool entitled(Entitlement entitlement) {
    final DateTime now = _clock();
    DVEntitlementSnapshot? lapsed;
    for (final DVEntitlementSnapshot snapshot in snapshots) {
      if (snapshot.entitlement != entitlement.id) continue;
      if (now.isBefore(snapshot.notAfter)) return true;
      lapsed = snapshot;
    }
    if (lapsed != null) {
      (_logger ?? DVObservability.logger).log(
        'DV-PURCHASE-005: the "${entitlement.id}" snapshot passed its '
        'notAfter (${lapsed.notAfter.toUtc().toIso8601String()}) without a '
        'fresh sync; access refused',
        level: DVLogLevel.info,
        code: 'DV-PURCHASE-005',
        context: <String, Object?>{'entitlement': entitlement.id},
      );
    }
    return false;
  }
}

/// Reads prices from a store, on the device.
abstract class DVStorePriceSource {
  /// The price of each of [ids] in the customer's own currency, as [store]
  /// quotes it. An id missing from the answer has no price.
  Future<Map<String, DVMoney>> prices(DVStore store, Set<String> ids);
}

/// The price a purchase button shows.
class DVStorePrices {
  DVStorePrices(this.source, {DVLogger? logger}) : _logger = logger;

  final DVStorePriceSource source;
  final DVLogger? _logger;

  /// [product]'s price as [store] quotes it, or null.
  ///
  /// Never converted, and never a fallback: a page showing a converted price
  /// above a sheet charging the store's tier is a mismatch the customer sees
  /// at the exact moment they decide to pay. When the store cannot be read,
  /// no price is shown (`DV-PURCHASE-007`).
  Future<DVMoney?> displayPrice(DVPurchaseProduct product, DVStore store) async {
    if (product.billable is! DVDigitalBillable) {
      throw ArgumentError.value(
        product.id,
        'product',
        'a physical good has no store price; it is sold through the gateway',
      );
    }
    final String? id = product.identifierOn(store);
    if (id == null) {
      throw ArgumentError.value(
        product.id,
        'product',
        'DV-PURCHASE-002: no ${store.name} product identifier is declared',
      );
    }
    final Map<String, DVMoney> answer;
    try {
      answer = await source.prices(store, <String>{id});
    } on Exception catch (error) {
      _report(product, store, 'the store could not be read ($error)');
      return null;
    }
    final DVMoney? price = answer[id];
    if (price == null) {
      _report(product, store, 'the store returned no price for "$id"');
    }
    return price;
  }

  void _report(DVPurchaseProduct product, DVStore store, String why) {
    (_logger ?? DVObservability.logger).log(
      'DV-PURCHASE-007: $why; no price is shown for ${product.id} rather '
      'than a converted one',
      level: DVLogLevel.warn,
      code: 'DV-PURCHASE-007',
      context: <String, Object?>{'product': product.id, 'store': store.name},
    );
  }
}

/// Store amounts in integer minor units, exactly.
///
/// The App Store reports prices in milliunits and Play in micros. Both are
/// integers, and the conversion stays in integers: a price that passed
/// through a double is occasionally 9.999999999999998, and one that needed
/// rounding was misread, so it is refused rather than rounded.
class DVStoreMoney {
  const DVStoreMoney._();

  /// An App Store `price`: thousandths of the currency's major unit.
  static DVMoney fromMilliunits(int milliunits, String currency) =>
      _scaled(BigInt.from(milliunits), 3, currency, 'milliunits');

  /// A Play `priceAmountMicros`: millionths of the major unit, as the decimal
  /// string Play sends. A string, because the JSON number a parser would make
  /// of it is a double past 2^53.
  static DVMoney fromMicros(String micros, String currency) {
    if (!RegExp(r'^-?[0-9]+$').hasMatch(micros)) {
      throw FormatException('micros are an integer count', micros);
    }
    return _scaled(BigInt.parse(micros), 6, currency, 'micros');
  }

  static DVMoney _scaled(
    BigInt value,
    int places,
    String currency,
    String unit,
  ) {
    if (value.isNegative) {
      throw ArgumentError.value(
          value, unit, 'a price is not negative; a refund is not a price');
    }
    final int exponent = dvCurrencyExponent(currency);
    BigInt minor;
    if (exponent >= places) {
      minor = value * BigInt.from(10).pow(exponent - places);
    } else {
      final BigInt divisor = BigInt.from(10).pow(places - exponent);
      if (value % divisor != BigInt.zero) {
        throw ArgumentError.value(
          value,
          unit,
          'is not a whole number of ${currency.toUpperCase()} minor units; '
              'rounding it would charge or display a different price',
        );
      }
      minor = value ~/ divisor;
    }
    if (!minor.isValidInt) {
      throw ArgumentError.value(value, unit, 'is too large to hold');
    }
    return DVMoney(amount: minor.toInt(), currency: currency);
  }
}

/// Decides where a purchase goes.
///
/// Which goods may be sold outside a store, and whether an application may
/// link to its own checkout, are decided by courts and regulators and change
/// between releases of this framework. None of it is compiled in: an
/// application under a regime that permits an external link supplies its own
/// policy and carries that decision itself.
abstract class DVStorePolicy {
  const DVStorePolicy();

  DVPurchaseRoute route({
    required DVPurchaseProduct product,
    required DVPurchaseChannel channel,
    String? jurisdiction,
  });
}

/// The conservative default: every digital good sold in a store build goes to
/// that store, whatever the jurisdiction; everything else goes to the gateway.
class DVConservativeStorePolicy extends DVStorePolicy {
  const DVConservativeStorePolicy();

  @override
  DVPurchaseRoute route({
    required DVPurchaseProduct product,
    required DVPurchaseChannel channel,
    String? jurisdiction,
  }) {
    final DVStore? store = switch (channel) {
      DVPurchaseChannel.appStore => DVStore.appStore,
      DVPurchaseChannel.play => DVStore.play,
      DVPurchaseChannel.web || DVPurchaseChannel.desktop => null,
    };
    if (store == null) return DVPurchaseRoute.gateway;
    switch (product.billable) {
      case DVPhysicalBillable():
        return DVPurchaseRoute.gateway;
      case final DVDigitalBillable digital:
        if (digital.identifierOn(store) == null) {
          throw StateError(
            'DV-PURCHASE-002: ${product.id} is digital and declares no '
            '${store.name} product identifier, so a ${channel.name} build '
            'cannot sell it. Sending it to the gateway instead would be a '
            'rejected submission.',
          );
        }
        return DVPurchaseRoute.store;
    }
  }
}

/// The App Store's conservative default policy.
class DVAppleStorePolicy extends DVConservativeStorePolicy {
  const DVAppleStorePolicy();
}

/// Google Play's conservative default policy.
class DVPlayStorePolicy extends DVConservativeStorePolicy {
  const DVPlayStorePolicy();
}

/// `DV.Purchases`: store purchases, verified on the server, written to the
/// ledger entitlements are read from.
class DVPurchases {
  DVPurchases({
    required List<DVPurchaseProduct> products,
    required List<DVStoreAdapter> stores,
    required this.ledger,
    DVStorePolicy? policy,
    DateTime Function()? clock,
    DVLogger? logger,
    void Function(DVPurchaseChange change)? onChange,
    this.perpetualSnapshotLifetime = const Duration(days: 7),
  })  : products = List<DVPurchaseProduct>.unmodifiable(products),
        policy = policy ?? const DVConservativeStorePolicy(),
        _clock = clock ?? DateTime.now,
        _logger = logger,
        _onChange = onChange {
    for (final DVStoreAdapter adapter in stores) {
      if (_stores.containsKey(adapter.store)) {
        throw ArgumentError(
            'two adapters for ${adapter.store.name}; a purchase would be '
            'verified by whichever happened to be listed last');
      }
      _stores[adapter.store] = adapter;
    }
    final Set<String> ids = <String>{};
    for (final DVPurchaseProduct product in products) {
      if (!ids.add(product.id)) {
        throw ArgumentError('product "${product.id}" is declared twice');
      }
      for (final DVStore store in DVStore.values) {
        final String? storeId = product.identifierOn(store);
        if (storeId == null) continue;
        final DVPurchaseProduct? other = _byStoreId[(store, storeId)];
        if (other != null) {
          throw ArgumentError(
            '${other.id} and ${product.id} are both "$storeId" on '
            '${store.name}; a purchase of one would grant the other',
          );
        }
        _byStoreId[(store, storeId)] = product;
      }
      for (final Entitlement entitlement in product.entitlements) {
        _entitlements[entitlement.id] = entitlement;
      }
    }
  }

  final List<DVPurchaseProduct> products;
  final DVPurchaseLedger ledger;
  final DVStorePolicy policy;

  /// The `notAfter` a snapshot of a purchase that never expires carries.
  ///
  /// A non-consumable still has to end on a device, because a refund reaches
  /// the device only when it syncs. A week covers being offline for a trip
  /// and not for a year.
  final Duration perpetualSnapshotLifetime;

  final DateTime Function() _clock;
  final DVLogger? _logger;
  final void Function(DVPurchaseChange change)? _onChange;
  final Map<DVStore, DVStoreAdapter> _stores = <DVStore, DVStoreAdapter>{};
  final Map<(DVStore, String), DVPurchaseProduct> _byStoreId =
      <(DVStore, String), DVPurchaseProduct>{};
  final Map<String, Entitlement> _entitlements = <String, Entitlement>{};

  DVLogger get _log => _logger ?? DVObservability.logger;
  DateTime get _now => _clock().toUtc();

  static DVPurchases? _current;

  /// Sets what `DV.Purchases` answers with.
  static void configure(DVPurchases purchases) => _current = purchases;

  static void unconfigure() => _current = null;

  static DVPurchases get current {
    final DVPurchases? purchases = _current;
    if (purchases == null) {
      throw StateError(
        'DV.Purchases is not configured. Call DVPurchases.configure('
        'DVPurchases(products: ..., stores: ..., ledger: ...)) at startup.',
      );
    }
    return purchases;
  }

  /// The account token a client passes to the store when it opens the
  /// purchase sheet for [customer].
  ///
  /// A UUID, because StoreKit's `appAccountToken` must be one, derived from
  /// the billing customer key rather than being the key: the token travels
  /// through the store and back, and an internal user id has no business
  /// doing that. A receipt carrying another customer's token grants nothing.
  static String accountTokenFor(Object customer) {
    final String key = dvBillingCustomerKey(customer);
    final List<int> bytes = sha256
        .convert(utf8.encode('dartvel.purchases.account $key'))
        .bytes
        .sublist(0, 16);
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final String hex =
        bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Where [product] is bought on [channel], as the configured policy says.
  DVPurchaseRoute route(
    DVPurchaseProduct product, {
    required DVPurchaseChannel channel,
    String? jurisdiction,
  }) =>
      policy.route(
          product: product, channel: channel, jurisdiction: jurisdiction);

  /// Verifies [receipt] with [store] and grants what it bought to [customer].
  ///
  /// The receipt is the only thing taken from the device. What was bought,
  /// until when, and whether it still stands all come from the store's answer.
  /// Refuses (throwing [DVPurchaseRefused]) when the store refuses the
  /// receipt (`DV-PURCHASE-003`), when it was bought under another
  /// application account, or when the ledger already holds it for somebody
  /// else -- two people share devices, and moving somebody's subscription to
  /// whoever is signed in is a refusal, not a merge.
  Future<DVPurchaseResult> verifyPurchase(
    DVStore store,
    String receipt, {
    required Object customer,
  }) async {
    final String customerKey = dvBillingCustomerKey(customer);
    final DVStoreAdapter adapter = _adapter(store);
    final DVStoreTransaction transaction;
    try {
      transaction = await adapter.verifyReceipt(receipt);
    } on DVStoreRefusal catch (refusal) {
      _refused(store, customerKey, refusal.reason);
      throw DVPurchaseRefused(refusal.reason, code: 'DV-PURCHASE-003');
    }
    if (transaction.store != store) {
      const String reason = 'the answer came from a different store';
      _refused(store, customerKey, reason);
      throw const DVPurchaseRefused(reason, code: 'DV-PURCHASE-003');
    }

    final DVPurchaseProduct? product =
        _byStoreId[(store, transaction.storeProductId)];
    if (product == null) {
      _undeclared(store, transaction);
      throw DVPurchaseRefused(
        'the store says this is "${transaction.storeProductId}", which the '
        'project does not declare',
        code: 'DV-PURCHASE-004',
      );
    }

    final String? token = transaction.appAccountToken;
    if (token != null && token != accountTokenFor(customerKey)) {
      throw const DVPurchaseRefused(
        'this purchase was made for another application account; nothing '
        'was granted',
      );
    }

    return _transactions<DVPurchaseResult>((DVContext context) async {
      final DVPurchaseGrant? previous =
          await ledger.find(store, transaction.originalTransactionId);
      if (previous != null && previous.customerKey != customerKey) {
        throw const DVPurchaseRefused(
          'this purchase is held by another application account; nothing '
          'was granted',
        );
      }
      if (previous != null &&
          transaction.signedAt.isBefore(previous.lastEventAt)) {
        return DVPurchaseResult._stale;
      }
      return _write(
        context,
        adapter: adapter,
        transaction: transaction,
        product: product,
        customerKey: customerKey,
        previous: previous,
        eventAt: transaction.signedAt,
      );
    });
  }

  /// Applies a store server notification delivered to [store]'s endpoint.
  ///
  /// [body] and [headers] are the request's. Throws [DVPurchaseRefused] for a
  /// signature that does not verify, having changed nothing; the endpoint
  /// answers that with a client error. Every other outcome is an
  /// acknowledgement, including a replay, a stale answer and an undeclared
  /// product (`DV-PURCHASE-004`), because a store retries what is not
  /// acknowledged. A failure part-way -- an acknowledgement the store did not
  /// take -- rolls the grant and the notification's claim back and rethrows,
  /// so the store's retry is applied rather than mistaken for a replay.
  Future<DVPurchaseResult> acceptNotification(
    DVContext context,
    DVStore store, {
    required String body,
    required Map<String, String> headers,
  }) async {
    final DVStoreAdapter adapter = _adapter(store);
    final DVStoreNotification notification;
    try {
      notification = await adapter.verifyNotification(body, headers);
    } on DVStoreRefusal catch (refusal) {
      _log.log(
        'A ${store.name} notification was refused: ${refusal.reason}',
        level: DVLogLevel.warn,
        context: <String, Object?>{'store': store.name},
      );
      throw DVPurchaseRefused(refusal.reason);
    }
    final DVStoreTransaction transaction = notification.transaction;
    if (transaction.store != store) {
      throw const DVPurchaseRefused(
          'the notification describes a purchase from a different store');
    }

    return _transactions<DVPurchaseResult>((DVContext unit) async {
      if (!await ledger.claimNotification(store, notification.notificationId)) {
        return DVPurchaseResult._replayed;
      }
      unit.compensate(
          () => ledger.releaseNotification(store, notification.notificationId));

      final DVPurchaseProduct? product =
          _byStoreId[(store, transaction.storeProductId)];
      if (product == null) {
        _undeclared(store, transaction);
        return DVPurchaseResult._undeclared;
      }

      final DVPurchaseGrant? previous =
          await ledger.find(store, transaction.originalTransactionId);
      if (previous == null) return DVPurchaseResult._unattributed;
      if (notification.signedAt.isBefore(previous.lastEventAt)) {
        return DVPurchaseResult._stale;
      }

      return _write(
        unit,
        adapter: adapter,
        transaction: transaction,
        product: product,
        customerKey: previous.customerKey,
        previous: previous,
        eventAt: notification.signedAt,
        notificationId: notification.notificationId,
      );
    });
  }

  /// Revalidates each of [receipts] with [store] for [customer].
  ///
  /// The device supplies what the store account owns; each receipt is then
  /// verified here like a new purchase. One that is refused -- by the store,
  /// or because it belongs to another application user -- is reported in its
  /// result and grants nothing, without stopping the rest.
  Future<List<DVPurchaseResult>> restore({
    required Object customer,
    required DVStore store,
    required List<String> receipts,
  }) async {
    final List<DVPurchaseResult> results = <DVPurchaseResult>[];
    for (final String receipt in receipts) {
      try {
        results.add(await verifyPurchase(store, receipt, customer: customer));
      } on DVPurchaseRefused catch (refusal) {
        results.add(DVPurchaseResult(refused: true, reason: refusal.reason));
      }
    }
    return results;
  }

  /// Whether [customer] holds [entitlement] now, from the ledger.
  Future<bool> entitled(Object customer, Entitlement entitlement) async {
    final DateTime now = _now;
    for (final DVPurchaseGrant grant
        in await ledger.forCustomer(dvBillingCustomerKey(customer))) {
      if (grant.activeAt(now) &&
          _entitlementIdsOf(grant).contains(entitlement.id)) {
        return true;
      }
    }
    return false;
  }

  /// What a device may hold for [customer]: each entitlement in force, with
  /// the moment it stops without a fresh sync.
  Future<List<DVEntitlementSnapshot>> snapshots(Object customer) async {
    final DateTime now = _now;
    final Map<String, DateTime> ends = <String, DateTime>{};
    for (final DVPurchaseGrant grant
        in await ledger.forCustomer(dvBillingCustomerKey(customer))) {
      if (!grant.activeAt(now)) continue;
      final DateTime end = grant.notAfter ?? now.add(perpetualSnapshotLifetime);
      for (final String id in _entitlementIdsOf(grant)) {
        final DateTime? held = ends[id];
        if (held == null || end.isAfter(held)) ends[id] = end;
      }
    }
    final List<String> ids = ends.keys.toList()..sort();
    return <DVEntitlementSnapshot>[
      for (final String id in ids)
        DVEntitlementSnapshot(entitlement: id, notAfter: ends[id]!),
    ];
  }

  /// Retries acknowledgements still missing inside their store's window, and
  /// reports each past it as `DV-PURCHASE-006`, returning those.
  ///
  /// A grant is acknowledged as it is written, so one found here is the
  /// residue of a crash between the two. Run it on a schedule shorter than the
  /// shortest window.
  Future<List<DVPurchaseGrant>> checkAcknowledgements() async {
    final DateTime now = _now;
    final List<DVPurchaseGrant> late = <DVPurchaseGrant>[];
    for (final DVPurchaseGrant grant in await ledger.unacknowledged()) {
      final DVStoreAdapter? adapter = _stores[grant.store];
      final Duration? window = adapter?.acknowledgementWindow;
      if (adapter == null || window == null || grant.revokedAt != null) {
        continue;
      }
      if (!now.isBefore(grant.purchasedAt.add(window))) {
        _log.log(
          'DV-PURCHASE-006: ${grant.store.name} purchase '
          '${grant.transactionId} (${grant.productId}) was granted and not '
          'acknowledged within ${window.inHours} hours; the store refunds it',
          level: DVLogLevel.error,
          code: 'DV-PURCHASE-006',
          context: <String, Object?>{
            'store': grant.store.name,
            'transaction': grant.transactionId,
            'product': grant.productId,
          },
        );
        late.add(grant);
        continue;
      }
      try {
        await adapter.acknowledge(
          originalTransactionId: grant.originalTransactionId,
          transactionId: grant.transactionId,
          storeProductId: grant.storeProductId,
        );
        await ledger.put(grant._acknowledged());
      } on Exception catch (error) {
        _log.log(
          'Acknowledging ${grant.store.name} purchase ${grant.transactionId} '
          'failed and will be retried: $error',
          level: DVLogLevel.warn,
        );
      }
    }
    return late;
  }

  // -- internals -------------------------------------------------------------

  /// Runs [body] as its own unit of work.
  ///
  /// Isolated rather than joining whatever transaction is active, because the
  /// transaction runner tracks the active one in a static rather than per
  /// zone: two notifications being applied at once would otherwise join each
  /// other, and one's failed acknowledgement would roll back the other's
  /// grant.
  Future<T> _transactions<T>(Future<T> Function(DVContext context) body) =>
      DVTransactionRunner().call<T>(body, isolated: true);

  Future<DVPurchaseResult> _write(
    DVContext context, {
    required DVStoreAdapter adapter,
    required DVStoreTransaction transaction,
    required DVPurchaseProduct product,
    required String customerKey,
    required DVPurchaseGrant? previous,
    required DateTime eventAt,
    String? notificationId,
  }) async {
    final DateTime now = _now;
    final bool alreadyAcknowledged = transaction.acknowledged ||
        adapter.acknowledgementWindow == null ||
        (previous != null &&
            previous.acknowledged &&
            previous.transactionId == transaction.transactionId);
    final DVPurchaseGrant next = DVPurchaseGrant(
      store: adapter.store,
      originalTransactionId: transaction.originalTransactionId,
      transactionId: transaction.transactionId,
      customerKey: customerKey,
      productId: product.id,
      storeProductId: transaction.storeProductId,
      purchasedAt: transaction.purchasedAt.toUtc(),
      notAfter: transaction.notAfter?.toUtc(),
      revokedAt: transaction.revokedAt?.toUtc(),
      acknowledged: alreadyAcknowledged,
      lastEventAt: eventAt.toUtc(),
    );

    final List<DVPurchaseGrant> held = await ledger.forCustomer(customerKey);
    final Set<String> before = _activeIds(held, now);
    final Set<String> after = _activeIds(<DVPurchaseGrant>[
      for (final DVPurchaseGrant grant in held)
        if (!(grant.store == next.store &&
            grant.originalTransactionId == next.originalTransactionId))
          grant,
      next,
    ], now);

    await ledger.put(next);
    context.compensate(() => previous == null
        ? ledger.remove(next.store, next.originalTransactionId)
        : ledger.put(previous));

    if (!next.acknowledged && next.revokedAt == null) {
      await adapter.acknowledge(
        originalTransactionId: next.originalTransactionId,
        transactionId: next.transactionId,
        storeProductId: next.storeProductId,
      );
      await ledger.put(next._acknowledged());
    }

    final Set<String> granted = after.difference(before);
    final Set<String> revoked = before.difference(after);
    final void Function(DVPurchaseChange change)? onChange = _onChange;
    if (onChange != null && (granted.isNotEmpty || revoked.isNotEmpty)) {
      context.afterCommit(() => onChange(DVPurchaseChange(
            customerKey: customerKey,
            store: next.store,
            originalTransactionId: next.originalTransactionId,
            granted: granted,
            revoked: revoked,
            notificationId: notificationId,
            revokedAt: next.revokedAt,
          )));
    }

    return DVPurchaseResult(
      handled: true,
      customerKey: customerKey,
      granted: <Entitlement>{for (final String id in granted) _entitlements[id]!},
      revoked: <Entitlement>{for (final String id in revoked) _entitlements[id]!},
    );
  }

  Set<String> _activeIds(Iterable<DVPurchaseGrant> grants, DateTime now) =>
      <String>{
        for (final DVPurchaseGrant grant in grants)
          if (grant.activeAt(now)) ..._entitlementIdsOf(grant),
      };

  /// What [grant]'s product unlocks under the current declarations.
  Set<String> _entitlementIdsOf(DVPurchaseGrant grant) {
    for (final DVPurchaseProduct product in products) {
      if (product.id == grant.productId) {
        return <String>{
          for (final Entitlement entitlement in product.entitlements)
            entitlement.id,
        };
      }
    }
    return const <String>{};
  }

  DVStoreAdapter _adapter(DVStore store) {
    final DVStoreAdapter? adapter = _stores[store];
    if (adapter == null) {
      throw StateError(
        'No ${store.name} adapter is configured, so nothing can verify a '
        '${store.name} purchase. Believing one unverified is the failure '
        'this refuses.',
      );
    }
    return adapter;
  }

  void _refused(DVStore store, String customerKey, String reason) {
    _log.log(
      'DV-PURCHASE-003: ${store.name} refused a receipt; no entitlement was '
      'written ($reason)',
      level: DVLogLevel.warn,
      code: 'DV-PURCHASE-003',
      context: <String, Object?>{'store': store.name, 'customer': customerKey},
    );
  }

  void _undeclared(DVStore store, DVStoreTransaction transaction) {
    _log.log(
      'DV-PURCHASE-004: ${store.name} named product '
      '"${transaction.storeProductId}", which the project does not declare. '
      'It was probably added in the store console and not in the code.',
      level: DVLogLevel.warn,
      code: 'DV-PURCHASE-004',
      context: <String, Object?>{
        'store': store.name,
        'storeProduct': transaction.storeProductId,
      },
    );
  }
}
