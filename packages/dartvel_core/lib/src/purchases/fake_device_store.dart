/// A device store for tests, paired with the server's [DVFakeStoreAdapter].
///
/// A purchase here issues a receipt into the paired adapter, so the receipt
/// the device presents is one the server can verify -- and one it can refuse.
/// A fake that skipped the server would let a test pass against code that
/// finishes a transaction nobody verified, which is the bug this half exists
/// to prevent.
library dartvel.purchases.fake_device_store;

import 'dart:async';

import 'device.dart';
import 'fake_store.dart';
import 'purchases.dart';

/// What the fake sheet does when it is opened.
enum DVFakeStoreResponse { purchase, cancel, pending, fail }

class DVFakeStoreClient implements DVStoreClient {
  DVFakeStoreClient(
    this.server, {
    DateTime Function()? clock,
    List<DVStoreListing> listings = const <DVStoreListing>[],
    this.subscriptionPeriod = const Duration(days: 30),
  })  : _clock = clock ?? DateTime.now,
        _listings = listings;

  /// The server adapter receipts are issued into.
  final DVFakeStoreAdapter server;
  final Duration subscriptionPeriod;
  final DateTime Function() _clock;
  final List<DVStoreListing> _listings;

  @override
  DVStore get store => server.store;

  /// What the next purchase sheet does.
  DVFakeStoreResponse respondWith = DVFakeStoreResponse.purchase;

  /// Makes the server refuse every receipt this issues.
  bool refuseOnServer = false;

  /// Whether the store can sell.
  bool isAvailable = true;

  /// Every request the sheet was opened with.
  final List<DVStorePurchaseRequest> requests = <DVStorePurchaseRequest>[];

  /// Transactions finished, and those consumed, in order.
  final List<DVStoreDeviceTransaction> finished = <DVStoreDeviceTransaction>[];
  final List<DVStoreDeviceTransaction> consumed = <DVStoreDeviceTransaction>[];

  /// Whether a restore asked the store to sync.
  bool synced = false;

  final StreamController<DVStoreDeviceTransaction> _updates =
      StreamController<DVStoreDeviceTransaction>.broadcast();
  final List<DVStoreDeviceTransaction> _owned = <DVStoreDeviceTransaction>[];
  final List<DVStorePurchaseRequest> _pending = <DVStorePurchaseRequest>[];
  int _issued = 0;

  @override
  Future<bool> available() async => isAvailable;

  @override
  Future<List<DVStoreListing>> listings(Set<String> storeProductIds) async =>
      <DVStoreListing>[
        for (final DVStoreListing listing in _listings)
          if (storeProductIds.contains(listing.storeProductId)) listing,
      ];

  @override
  Stream<DVStoreDeviceTransaction> get updates => _updates.stream;

  @override
  Future<DVStorePurchaseOutcome> purchase(DVStorePurchaseRequest request) async {
    requests.add(request);
    switch (respondWith) {
      case DVFakeStoreResponse.cancel:
        return const DVStoreCancelled();
      case DVFakeStoreResponse.fail:
        return const DVStoreFailed('the fake store failed');
      case DVFakeStoreResponse.pending:
        _pending.add(request);
        return const DVStorePending();
      case DVFakeStoreResponse.purchase:
        return DVStorePurchased(_issue(request.storeProductId, request.kind,
            accountToken: request.appAccountToken));
    }
  }

  /// Approves every pending purchase, as a parent approving Ask to Buy does:
  /// the transactions arrive on [updates], not from the purchase call.
  void approvePending() {
    for (final DVStorePurchaseRequest request in _pending) {
      _updates.add(_issue(request.storeProductId, request.kind,
          accountToken: request.appAccountToken));
    }
    _pending.clear();
  }

  /// A purchase made outside this application session -- on another device,
  /// or before a reinstall. With [emit] false it is only owned, for restore.
  DVStoreDeviceTransaction deliverExternally(
    String storeProductId,
    DVPurchaseKind kind, {
    String? accountToken,
    bool emit = true,
  }) {
    final DVStoreDeviceTransaction transaction =
        _issue(storeProductId, kind, accountToken: accountToken);
    if (emit) _updates.add(transaction);
    return transaction;
  }

  DVStoreDeviceTransaction _issue(
    String storeProductId,
    DVPurchaseKind kind, {
    String? accountToken,
  }) {
    _issued += 1;
    final String id = '${store.name}_tx_$_issued';
    final String receipt = '${store.name}_receipt_$_issued';
    final DateTime now = _clock().toUtc();
    if (refuseOnServer) {
      server.refuse(receipt, 'the fake store refused it');
    } else {
      server.issue(
        receipt,
        DVStoreTransaction(
          store: store,
          originalTransactionId: id,
          transactionId: id,
          storeProductId: storeProductId,
          purchasedAt: now,
          signedAt: now,
          expiresAt: kind == DVPurchaseKind.subscription
              ? now.add(subscriptionPeriod)
              : null,
          appAccountToken: accountToken,
        ),
      );
    }
    final DVStoreDeviceTransaction transaction = DVStoreDeviceTransaction(
      store: store,
      storeProductId: storeProductId,
      transactionId: id,
      receipt: receipt,
    );
    _owned.add(transaction);
    return transaction;
  }

  @override
  Future<List<DVStoreDeviceTransaction>> owned({bool sync = false}) async {
    if (sync) synced = true;
    return List<DVStoreDeviceTransaction>.of(_owned);
  }

  @override
  Future<void> finish(DVStoreDeviceTransaction transaction,
      {required bool consume}) async {
    finished.add(transaction);
    if (consume) {
      consumed.add(transaction);
      _owned.removeWhere(
          (DVStoreDeviceTransaction t) => t.transactionId == transaction.transactionId);
    }
  }
}
