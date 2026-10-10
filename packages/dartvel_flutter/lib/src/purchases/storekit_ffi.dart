/// StoreKit 2 behind [DVStoreClient], on iOS and macOS.
///
/// `dart:ffi` against the Objective-C runtime -- no platform channels, per
/// the native integration rule. StoreKit 2 itself is Swift-only, so what is
/// messaged is the `DartvelStoreKit` class `dartvel build` compiles into the
/// application for a project that declares `dartvel.purchases`
/// (`apple_storekit.dart` in dartvel_cli).
///
/// Every call is a request id and a poll. StoreKit 2 completes on threads of
/// its own choosing, and a block or a NativeCallable into Dart from one of
/// them is the part of an FFI bridge that is hardest to get right and
/// hardest to see going wrong; a string that is either there yet or not is
/// neither. The cost is up to one polling interval of latency on an
/// operation a person is already waiting seconds for.
library dartvel_flutter.purchases.storekit_ffi;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:dartvel_core/dartvel.dart';
import 'package:ffi/ffi.dart';

import 'storekit_json.dart';

typedef _LookupNative = Pointer<Void> Function(Pointer<Utf8> name);
typedef _LookupDart = Pointer<Void> Function(Pointer<Utf8> name);
typedef _Send0Native = Pointer<Void> Function(
    Pointer<Void> receiver, Pointer<Void> selector);
typedef _Send0Dart = Pointer<Void> Function(
    Pointer<Void> receiver, Pointer<Void> selector);
typedef _Send1Native = Pointer<Void> Function(
    Pointer<Void> receiver, Pointer<Void> selector, Pointer<Void> argument);
typedef _Send1Dart = Pointer<Void> Function(
    Pointer<Void> receiver, Pointer<Void> selector, Pointer<Void> argument);

/// The Objective-C runtime calls this client makes, looked up once.
class _ObjectiveC {
  _ObjectiveC._(DynamicLibrary runtime)
      : getClass = runtime
            .lookupFunction<_LookupNative, _LookupDart>('objc_getClass'),
        selector = runtime
            .lookupFunction<_LookupNative, _LookupDart>('sel_registerName'),
        send0 = runtime.lookupFunction<_Send0Native, _Send0Dart>('objc_msgSend'),
        send1 = runtime.lookupFunction<_Send1Native, _Send1Dart>('objc_msgSend');

  final _LookupDart getClass;
  final _LookupDart selector;
  final _Send0Dart send0;
  final _Send1Dart send1;

  static _ObjectiveC? _instance;

  /// The runtime, which on iOS and macOS is already in the process.
  static _ObjectiveC get instance =>
      _instance ??= _ObjectiveC._(DynamicLibrary.process());

  Pointer<Void> classNamed(String name) =>
      using((Arena arena) => getClass(name.toNativeUtf8(allocator: arena)));

  Pointer<Void> sel(String name) =>
      using((Arena arena) => selector(name.toNativeUtf8(allocator: arena)));

  /// A new autoreleased NSString holding [text].
  Pointer<Void> string(String text) => using((Arena arena) => send1(
      classNamed('NSString'),
      sel('stringWithUTF8String:'),
      text.toNativeUtf8(allocator: arena).cast()));

  /// The Dart string an NSString holds, or null for nil.
  String? read(Pointer<Void> nsString) {
    if (nsString == nullptr) return null;
    final Pointer<Utf8> utf8 = send0(nsString, sel('UTF8String')).cast();
    return utf8 == nullptr ? null : utf8.toDartString();
  }
}

/// [DVStoreClient] over the generated StoreKit 2 bridge.
class DVStoreKitClient implements DVStoreClient {
  DVStoreKitClient({
    this.pollInterval = const Duration(milliseconds: 80),
    this.updateInterval = const Duration(milliseconds: 500),
  }) {
    final Pointer<Void>? bridge = _bridge;
    // Started at once: StoreKit hands transactions that completed while the
    // application was closed only to a running Transaction.updates listener.
    if (bridge != null) {
      _runtime.send0(bridge, _runtime.sel(dvStoreKitListenSelector));
    }
  }

  /// How often an operation's answer is looked for.
  final Duration pollInterval;

  /// How often queued transactions are collected while somebody listens.
  final Duration updateInterval;

  /// Why the bridge cannot be reached, or null when it can.
  ///
  /// An application built with plain `flutter build`, or without
  /// `dartvel.purchases`, has no `DartvelStoreKit` class -- the one failure
  /// worth naming before anybody presses a buy button.
  static String? lastFailure;

  @override
  DVStore get store => DVStore.appStore;

  _ObjectiveC get _runtime => _ObjectiveC.instance;

  Pointer<Void>? _cachedBridge;
  bool _looked = false;

  Pointer<Void>? get _bridge {
    if (_looked) return _cachedBridge;
    _looked = true;
    try {
      final Pointer<Void> bridge = _runtime.classNamed(dvStoreKitClass);
      if (bridge == nullptr) {
        lastFailure = 'the class $dvStoreKitClass is not in this application. '
            '`dartvel build ios` (or macos) writes it when pubspec.yaml '
            'declares dartvel.purchases; an app built with plain '
            '`flutter build` has no StoreKit bridge.';
        return null;
      }
      lastFailure = null;
      return _cachedBridge = bridge;
    } on Object catch (error) {
      lastFailure = 'the Objective-C runtime could not be reached ($error)';
      return null;
    }
  }

  /// Sends [operation] and waits up to [patience] for its answer.
  Future<Object?> _call(
    String operation,
    Map<String, Object?> arguments, {
    Duration patience = const Duration(minutes: 2),
  }) async {
    final Pointer<Void>? bridge = _bridge;
    if (bridge == null) {
      throw DVStoreUnavailable(lastFailure ?? 'StoreKit is not available');
    }
    final String? id = _runtime.read(_runtime.send1(
        bridge,
        _runtime.sel(dvStoreKitStartSelector),
        _runtime.string(dvStoreKitRequest(operation, arguments))));
    if (id == null) throw const DVStoreUnavailable('StoreKit gave no request id');
    final DateTime giveUp = DateTime.now().add(patience);
    while (true) {
      final String? answer = _runtime.read(_runtime.send1(
          bridge, _runtime.sel(dvStoreKitPollSelector), _runtime.string(id)));
      if (answer != null) return jsonDecode(answer);
      if (DateTime.now().isAfter(giveUp)) {
        // A purchase that completes after this still arrives through
        // Transaction.updates, so giving up here loses no money.
        throw DVStoreUnavailable('StoreKit did not answer $operation within '
            '${patience.inSeconds} seconds');
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  @override
  Future<bool> available() async {
    if (_bridge == null) return false;
    try {
      final Object? answer = await _call('available', const <String, Object?>{});
      return answer is Map && answer['available'] == true;
    } on DVStoreUnavailable catch (error) {
      lastFailure = error.message;
      return false;
    }
  }

  @override
  Future<List<DVStoreListing>> listings(Set<String> storeProductIds) async =>
      dvStoreKitListings(await _call(
          'listings', <String, Object?>{'ids': storeProductIds.toList()}));

  @override
  Future<DVStorePurchaseOutcome> purchase(DVStorePurchaseRequest request) async {
    try {
      // A person reading the sheet, finding a password, approving with Face
      // ID: long, but not unbounded.
      return dvStoreKitOutcome(await _call('purchase', request.toJson(),
          patience: const Duration(minutes: 30)));
    } on DVStoreUnavailable catch (error) {
      return DVStoreFailed(error.message);
    }
  }

  @override
  Future<List<DVStoreDeviceTransaction>> owned({bool sync = false}) async {
    final Object? answer = await _call('owned', <String, Object?>{'sync': sync},
        // AppStore.sync() may ask the person to sign in.
        patience: sync ? const Duration(minutes: 10) : const Duration(minutes: 2));
    _throwIfStoreError(answer);
    return dvStoreKitTransactions(answer is Map ? answer['transactions'] : null);
  }

  @override
  Future<void> finish(DVStoreDeviceTransaction transaction,
      {required bool consume}) async {
    // StoreKit has no separate consume: finishing a consumable is what lets
    // it be bought again.
    _throwIfStoreError(await _call('finish',
        <String, Object?>{'transactionId': transaction.transactionId}));
  }

  void _throwIfStoreError(Object? answer) {
    if (answer is Map && answer['error'] != null) {
      throw DVStoreUnavailable('StoreKit: ${answer['error']}');
    }
  }

  Timer? _drainTimer;
  late final StreamController<DVStoreDeviceTransaction> _updates =
      StreamController<DVStoreDeviceTransaction>.broadcast(
    onListen: () {
      _drain();
      _drainTimer = Timer.periodic(updateInterval, (_) => _drain());
    },
    onCancel: () {
      _drainTimer?.cancel();
      _drainTimer = null;
    },
  );

  void _drain() {
    final Pointer<Void>? bridge = _bridge;
    if (bridge == null) return;
    final String? drained = _runtime
        .read(_runtime.send0(bridge, _runtime.sel(dvStoreKitDrainSelector)));
    if (drained == null) return;
    for (final DVStoreDeviceTransaction transaction
        in dvStoreKitTransactions(jsonDecode(drained))) {
      _updates.add(transaction);
    }
  }

  @override
  Stream<DVStoreDeviceTransaction> get updates => _updates.stream;
}
