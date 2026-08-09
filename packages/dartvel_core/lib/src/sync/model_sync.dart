import 'dart:async';

import '../tenancy/tenants.dart';

/// What happened to a model.
enum DVModelChangeKind { created, updated, deleted, restored, synced }

/// One model change, as delivered to watchers.
class DVModelChange<T> {
  final DVModelChangeKind kind;
  final T model;

  /// The tenant the change belongs to, captured when it was published.
  final String tenant;

  final DateTime at;

  DVModelChange({
    required this.kind,
    required this.model,
    String? tenant,
    DateTime? at,
  })  : tenant = tenant ?? const DVTenants().currentTenant,
        at = at ?? DateTime.now();
}

/// Where sync events cross process boundaries.
///
/// The hub itself delivers within one process; a transport carries envelopes
/// between processes or clients (WebSocket fanout, Redis pub/sub). Incoming
/// envelopes are injected back into the local hub so watchers see remote
/// changes exactly like local ones.
abstract class DVModelSyncTransport {
  /// Sends a locally published change outward.
  Future<void> send(Map<String, Object?> envelope);

  /// Changes arriving from elsewhere.
  Stream<Map<String, Object?>> get incoming;
}

/// A running `Model.watch(...)`. Cancel it when the watcher goes away.
class DVModelWatch {
  final StreamSubscription<Object?> _subscription;

  DVModelWatch(this._subscription);

  Future<void> cancel() => _subscription.cancel();
}

/// The model sync hub.
///
/// Not a realtime facade — the spec forbids one. This is the delivery
/// mechanism generated model `watch`/`sync` APIs are built on: typed change
/// streams per model type, with tenant filtering and policy checks applied
/// before delivery.
class DVModelSync {
  DVModelSync._();

  static final Map<Type, StreamController<Object?>> _controllers = {};
  static final Map<Type, bool Function(Object? model)> _policies = {};
  static final Map<String, Object? Function(Map<String, Object?>)> _decoders =
      {};
  static final Map<Type, Map<String, Object?> Function(Object?)> _encoders =
      {};
  /// The model types with a live sync channel, and the wire names their
  /// codecs are registered under.
  ///
  /// Sync failures are usually a missing codec or a channel nobody opened,
  /// and neither is visible from the outside without this.
  static Set<Type> get syncedTypes => Set<Type>.unmodifiable(_controllers.keys);

  /// Wire names that can be decoded from an incoming envelope.
  static Set<String> get decodableNames => Set<String>.unmodifiable(_decoders.keys);

  static DVModelSyncTransport? _transport;
  static StreamSubscription<Map<String, Object?>>? _transportSubscription;

  /// Registers a policy filter for [T]. A change whose model fails the check
  /// is not delivered — policy runs before delivery, not in the UI.
  static void registerPolicy<T>(bool Function(T model) canSee) {
    _policies[T] = (Object? model) => model is T && canSee(model);
  }

  /// Registers the codec a transport needs to carry [T] across the wire.
  /// In-process delivery works without one.
  static void registerCodec<T>({
    required String name,
    required Map<String, Object?> Function(T model) encode,
    required T Function(Map<String, Object?> json) decode,
  }) {
    _encoders[T] = (Object? model) => encode(model as T);
    _decoders[name] = decode;
    _codecNames[T] = name;
  }

  /// Connects the cross-process transport. Locally published changes are
  /// forwarded outward; arriving envelopes are republished locally.
  static void useTransport(DVModelSyncTransport transport) {
    unawaited(_transportSubscription?.cancel());
    _transport = transport;
    _transportSubscription = transport.incoming.listen(_receive);
  }

  static void _receive(Map<String, Object?> envelope) {
    final type = envelope['type'];
    final decoder = type is String ? _decoders[type] : null;
    final data = envelope['model'];
    if (decoder == null || data is! Map<String, Object?>) return;
    final model = decoder(data);
    if (model == null) return;

    final kindName = envelope['kind'];
    final kind = DVModelChangeKind.values.firstWhere(
      (DVModelChangeKind k) => k.name == kindName,
      orElse: () => DVModelChangeKind.synced,
    );
    _controllers[model.runtimeType]?.add(
      DVModelChange<Object?>(
        kind: kind,
        model: model,
        tenant: envelope['tenant'] as String?,
      ),
    );
  }

  static StreamController<Object?> _controllerFor(Type type) =>
      _controllers.putIfAbsent(
        type,
        () => StreamController<Object?>.broadcast(),
      );

  /// Publishes a change to local watchers and, when a transport is
  /// connected and a codec is registered, outward.
  static Future<void> publish<T>(
    T model, {
    DVModelChangeKind kind = DVModelChangeKind.updated,
  }) async {
    final change = DVModelChange<T>(kind: kind, model: model);
    _controllerFor(T).add(change);

    final transport = _transport;
    final encode = _encoders[T];
    final name = _codecNames[T];
    if (transport != null && encode != null && name != null) {
      await transport.send(<String, Object?>{
        'type': name,
        'kind': kind.name,
        'tenant': change.tenant,
        'model': encode(model),
      });
    }
  }

  static final Map<Type, String> _codecNames = {};

  /// Typed change stream for [T].
  ///
  /// Delivery is filtered before the watcher sees anything: changes from
  /// another tenant are dropped unless [allTenants] is set, and a registered
  /// policy must accept the model.
  static Stream<DVModelChange<T>> changes<T>({bool allTenants = false}) {
    return _controllerFor(T).stream.where((Object? event) {
      if (event is! DVModelChange<T>) {
        // Transport-injected events arrive as DVModelChange<Object?>; match
        // on the model's runtime type instead.
        return event is DVModelChange<Object?> && event.model is T;
      }
      return true;
    }).map((Object? event) {
      final raw = event! as DVModelChange<Object?>;
      return event is DVModelChange<T>
          ? event
          : DVModelChange<T>(
              kind: raw.kind,
              model: raw.model as T,
              tenant: raw.tenant,
              at: raw.at,
            );
    }).where((DVModelChange<T> change) {
      if (!allTenants &&
          change.tenant != const DVTenants().currentTenant) {
        return false;
      }
      final policy = _policies[T];
      return policy == null || policy(change.model);
    });
  }

  /// Drops all registrations and closes streams. Intended for tests.
  static Future<void> reset() async {
    await _transportSubscription?.cancel();
    _transportSubscription = null;
    _transport = null;
    _policies.clear();
    _decoders.clear();
    _encoders.clear();
    _codecNames.clear();
    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();
  }
}
