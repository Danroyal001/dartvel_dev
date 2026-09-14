/// A store for tests: receipts it has issued, notifications it has signed.
///
/// It verifies what it is given the way a real adapter must. A fake that
/// accepted any notification body would let a test pass against code that
/// never checks a signature, which is the exact bug a store endpoint cannot
/// afford; so notifications are signed with an HMAC and one that does not
/// match is refused.
library dartvel.purchases.fake_store;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../billing/money.dart';
import 'purchases.dart';

class DVFakeStoreAdapter implements DVStoreAdapter {
  DVFakeStoreAdapter(
    this.store, {
    required String signingKey,
    this.acknowledgementWindow,
  }) : _key = utf8.encode(signingKey) {
    if (signingKey.isEmpty) {
      throw ArgumentError.value(signingKey, 'signingKey',
          'an empty key signs everything the same way');
    }
  }

  /// The header the signature travels under.
  static const String signatureHeader = 'X-Dartvel-Store-Signature';

  @override
  final DVStore store;

  @override
  final Duration? acknowledgementWindow;

  final List<int> _key;
  final Map<String, DVStoreTransaction> _receipts =
      <String, DVStoreTransaction>{};
  final Map<String, String> _refusals = <String, String>{};

  /// Makes every acknowledgement fail, as a store outage would.
  bool failAcknowledgements = false;

  /// Makes every call fail as unreachable.
  bool unavailable = false;

  /// Transaction ids acknowledged, in order.
  final List<String> acknowledged = <String>[];

  /// Makes [receipt] verify as [transaction].
  void issue(String receipt, DVStoreTransaction transaction) {
    _refusals.remove(receipt);
    _receipts[receipt] = transaction;
  }

  /// Makes [receipt] refused, for [reason].
  void refuse(String receipt, String reason) {
    _receipts.remove(receipt);
    _refusals[receipt] = reason;
  }

  /// [notification] as this store would deliver it.
  DVSignedStoreNotification sign(DVStoreNotification notification) {
    final String body = jsonEncode(_notificationToJson(notification));
    return DVSignedStoreNotification(
      body: body,
      headers: <String, String>{signatureHeader: _signature(body)},
    );
  }

  @override
  Future<DVStoreTransaction> verifyReceipt(String receipt) async {
    if (unavailable) throw const DVStoreUnavailable('the store is unreachable');
    final String? refusal = _refusals[receipt];
    if (refusal != null) throw DVStoreRefusal(store, refusal);
    final DVStoreTransaction? transaction = _receipts[receipt];
    if (transaction == null) {
      throw DVStoreRefusal(store, 'the store has no record of this receipt');
    }
    return transaction;
  }

  @override
  Future<DVStoreNotification> verifyNotification(
    String body,
    Map<String, String> headers,
  ) async {
    if (unavailable) throw const DVStoreUnavailable('the store is unreachable');
    String? signature;
    for (final MapEntry<String, String> header in headers.entries) {
      if (header.key.toLowerCase() == signatureHeader.toLowerCase()) {
        signature = header.value;
      }
    }
    if (signature == null) {
      throw DVStoreRefusal(store, 'the notification is not signed');
    }
    if (!_constantTimeEquals(signature, _signature(body))) {
      throw DVStoreRefusal(store, 'the notification signature does not match');
    }
    try {
      return _notificationFromJson(
          (jsonDecode(body) as Map<Object?, Object?>).cast<String, Object?>());
    } on Object {
      throw DVStoreRefusal(store, 'the notification body is not readable');
    }
  }

  @override
  Future<void> acknowledge({
    required String originalTransactionId,
    required String transactionId,
    required String storeProductId,
  }) async {
    if (unavailable || failAcknowledgements) {
      throw const DVStoreUnavailable('the acknowledgement was not accepted');
    }
    acknowledged.add(transactionId);
  }

  String _signature(String body) =>
      Hmac(sha256, _key).convert(utf8.encode(body)).toString();

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int difference = 0;
    for (int i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }

  static Map<String, Object?> _notificationToJson(DVStoreNotification n) =>
      <String, Object?>{
        'notificationId': n.notificationId,
        'type': n.type,
        'signedAt': n.signedAt.microsecondsSinceEpoch,
        'transaction': <String, Object?>{
          'store': n.transaction.store.name,
          'originalTransactionId': n.transaction.originalTransactionId,
          'transactionId': n.transaction.transactionId,
          'storeProductId': n.transaction.storeProductId,
          'purchasedAt': n.transaction.purchasedAt.microsecondsSinceEpoch,
          'signedAt': n.transaction.signedAt.microsecondsSinceEpoch,
          'expiresAt': n.transaction.expiresAt?.microsecondsSinceEpoch,
          'graceEndsAt': n.transaction.graceEndsAt?.microsecondsSinceEpoch,
          'revokedAt': n.transaction.revokedAt?.microsecondsSinceEpoch,
          'appAccountToken': n.transaction.appAccountToken,
          'acknowledged': n.transaction.acknowledged,
          if (n.transaction.price != null)
            'price': <String, Object?>{
              'amount': n.transaction.price!.amount,
              'currency': n.transaction.price!.currency,
            },
        },
      };

  static DVStoreNotification _notificationFromJson(Map<String, Object?> json) {
    final Map<String, Object?> t =
        (json['transaction']! as Map<Object?, Object?>).cast<String, Object?>();
    DateTime at(Object? value) =>
        DateTime.fromMicrosecondsSinceEpoch(value! as int, isUtc: true);
    DateTime? maybe(Object? value) => value == null ? null : at(value);
    final Map<Object?, Object?>? price = t['price'] as Map<Object?, Object?>?;
    return DVStoreNotification(
      notificationId: json['notificationId']! as String,
      type: json['type']! as String,
      signedAt: at(json['signedAt']),
      transaction: DVStoreTransaction(
        store: DVStore.values.byName(t['store']! as String),
        originalTransactionId: t['originalTransactionId']! as String,
        transactionId: t['transactionId']! as String,
        storeProductId: t['storeProductId']! as String,
        purchasedAt: at(t['purchasedAt']),
        signedAt: at(t['signedAt']),
        expiresAt: maybe(t['expiresAt']),
        graceEndsAt: maybe(t['graceEndsAt']),
        revokedAt: maybe(t['revokedAt']),
        appAccountToken: t['appAccountToken'] as String?,
        acknowledged: t['acknowledged']! as bool,
        price: price == null
            ? null
            : DVMoney(
                amount: price['amount']! as int,
                currency: price['currency']! as String,
              ),
      ),
    );
  }
}
