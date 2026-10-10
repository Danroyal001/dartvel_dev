/// Google Play Billing behind `DV.Purchases`, over JNI.
///
/// The billing work is the generated `DartvelBilling` Java class, which
/// `dartvel build android` writes for a project that declares
/// `dartvel.purchases`. This file starts an operation there, polls for the
/// answer, and drains the purchases that arrived outside one -- the shape
/// the capture bridge uses, and for the same reason: a callback into Dart
/// from whichever Android thread Play picks is the part of JNI hardest to
/// get right and hardest to see going wrong, and nothing here needs one.
///
/// What the bridge answers is read by the top-level functions below, which
/// are tested off a device. They are where a wrong answer still looks like
/// an answer: a price read through a double, a pending purchase read as
/// paid.
library dartvel_flutter.purchases.play_billing_jni;

import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:jni/jni.dart';

/// Play Billing as a [DVStoreClient].
class DVPlayBillingClient implements DVStoreClient {
  DVPlayBillingClient();

  /// Why the bridge cannot be reached, or null when it can.
  ///
  /// An APK built with plain `flutter build`, or from a project that does
  /// not declare `dartvel.purchases`, has no `DartvelBilling` class, and
  /// that is worth naming before anybody presses a buy button.
  static String? lastFailure;

  /// How long an operation is given. Long, because a purchase includes a
  /// person choosing a payment method; bounded, because a process killed
  /// behind the sheet takes the pending answer with it.
  static const Duration _patience = Duration(minutes: 10);

  /// How often purchases that arrived outside a call are collected while
  /// something listens for them.
  static const Duration _updateInterval = Duration(seconds: 2);

  JClass? _bridge;
  bool _looked = false;
  StreamController<DVStoreDeviceTransaction>? _updates;
  Timer? _drain;

  @override
  DVStore get store => DVStore.play;

  JClass? _class() {
    if (!_looked) {
      _looked = true;
      try {
        _bridge = JClass.forName(dvAndroidBillingBridgeClass);
        lastFailure = null;
      } on Object catch (error) {
        _bridge = null;
        lastFailure = 'the class $dvAndroidBillingBridgeClass is not in this '
            'application ($error). `dartvel build android` writes it for a '
            'project that declares dartvel.purchases in pubspec.yaml.';
      }
    }
    return _bridge;
  }

  JClass _required() =>
      _class() ?? (throw StateError(lastFailure ?? 'no billing bridge'));

  /// Starts [request] in the bridge and waits for its JSON answer.
  Future<Map<String, Object?>> _call(Map<String, Object?> request) async {
    final JClass bridge = _required();
    final JString argument = jsonEncode(request).toJString();
    final String id;
    try {
      id = bridge
          .staticMethodId('start', '(Ljava/lang/String;)Ljava/lang/String;')
          .call(bridge, JString.type, <dynamic>[argument])
          .toDartString(releaseOriginal: true);
    } finally {
      argument.release();
    }
    final JStaticMethodId poll = bridge.staticMethodId(
        'poll', '(Ljava/lang/String;)Ljava/lang/String;');
    final DateTime deadline = DateTime.now().add(_patience);
    // Short at first: a listing answers in a few frames, a purchase in
    // however long a person takes.
    Duration gap = const Duration(milliseconds: 25);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(gap);
      final JString key = id.toJString();
      final JString? answer;
      try {
        answer = poll.callNullable(bridge, JString.type, <dynamic>[key]);
      } finally {
        key.release();
      }
      if (answer != null) {
        final Object? decoded =
            jsonDecode(answer.toDartString(releaseOriginal: true));
        return decoded is Map
            ? decoded.cast<String, Object?>()
            : const <String, Object?>{'error': 'the bridge answered nothing'};
      }
      if (gap < const Duration(milliseconds: 100)) gap = gap * 2;
    }
    throw const DVStoreUnavailable('Play Billing never answered');
  }

  @override
  Future<bool> available() async {
    if (_class() == null) return false;
    final Map<String, Object?> answer =
        await _call(<String, Object?>{'op': 'available'});
    if (answer['available'] == true) return true;
    lastFailure = answer['error'] as String?;
    return false;
  }

  @override
  Future<List<DVStoreListing>> listings(Set<String> storeProductIds) async {
    final Map<String, Object?> answer = await _call(<String, Object?>{
      'op': 'listings',
      'ids': storeProductIds.toList(),
    });
    final Object? error = answer['error'];
    if (error != null) throw DVStoreUnavailable('$error');
    return dvPlayListings(jsonEncode(answer));
  }

  @override
  Future<DVStorePurchaseOutcome> purchase(DVStorePurchaseRequest request) async {
    final Map<String, Object?> answer = await _call(<String, Object?>{
      'op': 'purchase',
      ...request.toJson(),
    });
    return dvPlayPurchaseOutcome(jsonEncode(answer));
  }

  @override
  Stream<DVStoreDeviceTransaction> get updates {
    // Closed by dispose().
    // ignore: close_sinks
    final StreamController<DVStoreDeviceTransaction> controller =
        _updates ??= StreamController<DVStoreDeviceTransaction>.broadcast(
      onListen: () {
        _drain ??= Timer.periodic(_updateInterval, (_) => _collect());
      },
      onCancel: () {
        _drain?.cancel();
        _drain = null;
      },
    );
    return controller.stream;
  }

  /// Stops collecting updates. For a test, or an application tearing its
  /// purchases down.
  Future<void> dispose() async {
    _drain?.cancel();
    _drain = null;
    await _updates?.close();
    _updates = null;
  }

  void _collect() {
    final JClass? bridge = _class();
    final StreamController<DVStoreDeviceTransaction>? controller = _updates;
    if (bridge == null || controller == null) return;
    final String drained = bridge
        .staticMethodId('drainUpdates', '()Ljava/lang/String;')
        .call(bridge, JString.type, const <dynamic>[])
        .toDartString(releaseOriginal: true);
    for (final DVStoreDeviceTransaction transaction
        in dvPlayTransactions(drained)) {
      controller.add(transaction);
    }
  }

  @override
  Future<List<DVStoreDeviceTransaction>> owned({bool sync = false}) async {
    // Play has no sync step: queryPurchasesAsync reads the store's own
    // cache, which Play keeps current.
    final Map<String, Object?> answer =
        await _call(<String, Object?>{'op': 'owned'});
    final Object? error = answer['error'];
    if (error != null) throw DVStoreUnavailable('$error');
    return dvPlayTransactions(jsonEncode(answer['transactions'] ?? <Object?>[]));
  }

  @override
  Future<void> finish(DVStoreDeviceTransaction transaction,
      {required bool consume}) async {
    final Map<String, Object?> answer = await _call(<String, Object?>{
      'op': 'finish',
      'consume': consume,
      'purchaseToken': dvPlayPurchaseTokenOf(transaction.receipt),
    });
    final Object? error = answer['error'];
    if (error != null) throw DVStoreUnavailable('$error');
  }
}

/// The bridge's `listings` answer as listings.
///
/// Prices come as micros and a currency, never as a number: they become
/// integer minor units through [DVStoreMoney.fromMicros], and one that is not
/// a whole number of minor units keeps its display text and loses its
/// number rather than being rounded.
List<DVStoreListing> dvPlayListings(String json) {
  final Object? decoded = jsonDecode(json);
  final Object? listed = decoded is Map ? decoded['listings'] : null;
  if (listed is! List) return const <DVStoreListing>[];
  return <DVStoreListing>[
    for (final Object? entry in listed)
      if (entry is Map)
        DVStoreListing.fromJson(<String, Object?>{
          ...entry.cast<String, Object?>(),
          'price': _price(entry),
          'offers': <Object?>[
            for (final Object? offer
                in (entry['offers'] as List<Object?>?) ?? const <Object?>[])
              if (offer is Map)
                <String, Object?>{
                  ...offer.cast<String, Object?>(),
                  'price': _price(offer),
                },
          ],
        }),
  ];
}

Map<String, Object?>? _price(Map<Object?, Object?> json) {
  final Object? micros = json['priceMicros'];
  final Object? currency = json['currency'];
  if (micros is! String || currency is! String || currency.isEmpty) {
    return null;
  }
  try {
    final DVMoney money = DVStoreMoney.fromMicros(micros, currency);
    return <String, Object?>{'amount': money.amount, 'currency': money.currency};
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
}

/// The bridge's answer to a purchase.
DVStorePurchaseOutcome dvPlayPurchaseOutcome(String json) {
  final Object? decoded = jsonDecode(json);
  if (decoded is! Map) return const DVStoreFailed('the bridge answered nothing');
  final Object? error = decoded['error'];
  if (error != null) return DVStoreFailed('$error');
  switch (decoded['outcome']) {
    case 'purchased':
      final Object? transaction = decoded['transaction'];
      if (transaction is! Map) {
        return const DVStoreFailed('Play reported a purchase with no details');
      }
      return DVStorePurchased(DVStoreDeviceTransaction.fromJson(
          DVStore.play, transaction.cast<String, Object?>()));
    case 'pending':
      return const DVStorePending();
    case 'cancelled':
      return const DVStoreCancelled();
    default:
      return DVStoreFailed(
          (decoded['reason'] as String?) ?? 'Play reported a failure');
  }
}

/// A JSON array of the bridge's transactions.
List<DVStoreDeviceTransaction> dvPlayTransactions(String json) {
  final Object? decoded = jsonDecode(json);
  if (decoded is! List) return const <DVStoreDeviceTransaction>[];
  return <DVStoreDeviceTransaction>[
    for (final Object? entry in decoded)
      if (entry is Map)
        DVStoreDeviceTransaction.fromJson(
            DVStore.play, entry.cast<String, Object?>()),
  ];
}

/// The purchase token inside a Play receipt, or null.
String? dvPlayPurchaseTokenOf(String receipt) {
  try {
    final Object? decoded = jsonDecode(receipt);
    final Object? token = decoded is Map ? decoded['purchaseToken'] : null;
    return token is String && token.isNotEmpty ? token : null;
  } on FormatException {
    return null;
  }
}
