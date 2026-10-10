/// The StoreKit 2 bridge's JSON, read into `DV.Purchases`' own types.
///
/// Pure Dart, apart from `storekit_ffi.dart` which carries the strings to
/// and from the generated Swift class, so the whole contract between the two
/// halves is tested on a machine with no Apple device.
library dartvel_flutter.purchases.storekit_json;

import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';

/// One request to the Swift class: `{"op": operation, ...arguments}`.
String dvStoreKitRequest(String operation, Map<String, Object?> arguments) =>
    jsonEncode(<String, Object?>{'op': operation, ...arguments});

/// The answer's `error`, thrown as the store being unreachable.
///
/// A StoreKit error (offline, a sandbox account signed out) is not an empty
/// catalogue or an empty purchase history, and reading it as one would show
/// no prices with no reason, or restore nothing and say it succeeded.
void _throwIfError(Object? answer) {
  if (answer is Map && answer['error'] != null) {
    throw DVStoreUnavailable('StoreKit: ${answer['error']}');
  }
}

/// A price the shim reported in milliunits, as exact minor units, or null
/// when it is not a whole number of them.
DVMoney? _price(Map<Object?, Object?> json) {
  final Object? milliunits = json['priceMilliunits'];
  final Object? currency = json['currency'];
  if (milliunits is! int || currency is! String || currency.isEmpty) {
    return null;
  }
  try {
    return DVStoreMoney.fromMilliunits(milliunits, currency);
  } on ArgumentError {
    // DV-PURCHASE-007's rule: no price rather than a rounded one. The
    // store's own displayPrice still shows what the sheet charges.
    return null;
  }
}

DVStoreOfferKind _offerKind(Object? kind) => switch (kind) {
      'freeTrial' => .freeTrial,
      'promotional' => .promotional,
      'winBack' => .winBack,
      _ => .introductory,
    };

/// The answer to a `listings` request.
List<DVStoreListing> dvStoreKitListings(Object? answer) {
  _throwIfError(answer);
  final Object? listed = answer is Map ? answer['listings'] : null;
  return <DVStoreListing>[
    if (listed is List)
      for (final Object? entry in listed)
        if (entry is Map)
          DVStoreListing(
            storeProductId: '${entry['storeProductId']}',
            title: '${entry['title'] ?? ''}',
            description: '${entry['description'] ?? ''}',
            displayPrice: '${entry['displayPrice'] ?? ''}',
            price: _price(entry),
            period: entry['period'] as String?,
            offers: <DVStoreOffer>[
              if (entry['offers'] case final List<Object?> offers)
                for (final Object? offer in offers)
                  if (offer is Map)
                    DVStoreOffer(
                      id: '${offer['id']}',
                      kind: _offerKind(offer['kind']),
                      price: _price(offer),
                      displayPrice: offer['displayPrice'] as String?,
                      period: offer['period'] as String?,
                      periods: (offer['periods'] as int?) ?? 1,
                      eligible: offer['eligible'] != false,
                    ),
            ],
          ),
  ];
}

DVStoreDeviceTransaction _transaction(Map<Object?, Object?> json) =>
    DVStoreDeviceTransaction.fromJson(
        DVStore.appStore, json.cast<String, Object?>());

/// The transactions in an `owned` answer's `transactions`, or in what
/// `drainUpdates` returns.
List<DVStoreDeviceTransaction> dvStoreKitTransactions(Object? list) {
  _throwIfError(list);
  return <DVStoreDeviceTransaction>[
    if (list is List)
      for (final Object? entry in list)
        if (entry is Map) _transaction(entry),
  ];
}

/// The answer to a `purchase` request.
///
/// Anything that is not one of the three outcomes StoreKit has is a failure
/// with a reason: read as a cancel, a purchase StoreKit charged for would
/// be one nobody grants and nobody is told about.
DVStorePurchaseOutcome dvStoreKitOutcome(Object? answer) {
  if (answer is! Map) return const DVStoreFailed('StoreKit gave no answer');
  if (answer['error'] != null) return DVStoreFailed('StoreKit: ${answer['error']}');
  switch (answer['outcome']) {
    case 'purchased':
      final Object? transaction = answer['transaction'];
      if (transaction is! Map) {
        return const DVStoreFailed('StoreKit reported a purchase with no transaction');
      }
      return DVStorePurchased(_transaction(transaction));
    case 'pending':
      return const DVStorePending();
    case 'cancelled':
      return const DVStoreCancelled();
    case 'failed':
      return DVStoreFailed('${answer['reason'] ?? 'the purchase failed'}');
    default:
      return DVStoreFailed('StoreKit answered "${answer['outcome']}"');
  }
}
