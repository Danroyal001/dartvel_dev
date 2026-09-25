/// The device half of every offline data model, run by the framework.
///
/// A data model that declares `offline:` is read and written like any other.
/// Its generated `save()` and `destroy()` write to this device's store at
/// once and queue the change; this runs the queue. It replays when the
/// runtime starts, after each write, when `DV.Platform.network` says the
/// server can be reached again, and on a backoff after a send fails -- and
/// never because an application asked it to.
///
/// Not in the barrel an application imports: the generated models and the
/// generated runtime are what name it.
library dartvel_core.data.offline_sync;

import 'dart:async';
import 'dart:convert';

import '../annotations/annotations.dart' show DVCSRF;
import '../database/adapter.dart';
import '../http/transport.dart';
import '../observability/logging.dart' show DVLogLevel;
import '../observability/observability.dart' show DVObservability;
import 'offline_store.dart';

/// What the replay route answered: its status and its JSON body.
class DVOfflineReply {
  const DVOfflineReply(this.status, [this.body]);

  final int status;
  final Map<String, Object?>? body;
}

/// Sends one replay request -- `{model, mutations}` -- to the server.
///
/// Throwing means the server was not reached, which is transient.
typedef DVOfflineSend = Future<DVOfflineReply> Function(
  Map<String, Object?> body,
);

/// Posts replay requests to [endpoint] as JSON, with the session [headers]
/// the generated client sends on every call and a CSRF token, because a
/// browser is one of the clients that replays and the route checks one.
DVOfflineSend dvOfflineSendOverHttp({
  required Uri Function() endpoint,
  Map<String, String> Function()? headers,
}) {
  return (Map<String, Object?> body) async {
    final DVHttpResponse response = await dvSendHttpRequest(DVHttpRequest(
      url: endpoint(),
      method: 'POST',
      headers: <String, String>{
        ...?headers?.call(),
        'content-type': 'application/json; charset=utf-8',
        DVCSRF.headerName: const DVCSRF().token(),
      },
      body: utf8.encode(jsonEncode(body)),
    ));
    Map<String, Object?>? decoded;
    try {
      final Object? parsed = jsonDecode(response.body);
      if (parsed is Map<String, Object?>) decoded = parsed;
    } on FormatException {
      decoded = null;
    }
    return DVOfflineReply(response.statusCode, decoded);
  };
}

/// One offline model's queue, sent to the replay route one mutation at a
/// time so a transient failure stops it exactly where it is.
class _RouteRemote implements DVOfflineRemote {
  _RouteRemote(this.model, this.store, this.send);

  final String model;
  final DVOfflineStore store;
  final DVOfflineSend send;

  @override
  Set<String> get sensitiveColumns => store.table.sensitive;

  @override
  Future<DVRemoteOutcome> apply(DVMutation mutation) async {
    final DVOfflineReply reply = await send(<String, Object?>{
      'model': model,
      'mutations': <Object?>[mutation.toJson()],
    });
    final Map<String, Object?>? body = reply.body;
    if (reply.status == 400) {
      // The server read the request and says it will never be one. Sending
      // it again cannot change that, so it goes to the dead letters rather
      // than holding up every write behind it for ever.
      return const DVRemoteOutcome.rejected('not accepted by the server');
    }
    if (reply.status != 200 || body == null) {
      // Signed out, forbidden by CSRF, a proxy's 404, a server restarting:
      // none of them is an answer about this write. Transient, so the write
      // stays queued and later ones stay behind it.
      throw StateError('replay answered ${reply.status}');
    }
    final Object? at = body['serverTime'];
    if (at is String) {
      final DateTime? parsed = DateTime.tryParse(at);
      if (parsed != null) store.clock.observeServerTime(parsed);
    }
    final Object? outcomes = body['outcomes'];
    if (outcomes is! List<Object?> || outcomes.length != 1) {
      throw StateError('replay answered without an outcome');
    }
    return dvOutcomeFromJson(
      (outcomes.single! as Map<Object?, Object?>)
          .map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v)),
    );
  }
}

/// A database opened on first use, so a generated model can name its table
/// synchronously while the device store is still being opened.
class _Deferred implements DVDatabaseAdapter {
  _Deferred(this._open);

  final Future<DVDatabaseAdapter> Function() _open;

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) async =>
      (await _open()).query(sql, params);

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async =>
      (await _open()).execute(sql, params);
}

/// Runs every offline data model's queue on this device.
class DVOfflineSync {
  DVOfflineSync._();

  static final Map<String, DVOfflineStore Function(DVDatabaseAdapter)>
      _builders = <String, DVOfflineStore Function(DVDatabaseAdapter)>{};
  static final Map<String, Future<DVOfflineStore>> _stores =
      <String, Future<DVOfflineStore>>{};

  static Future<DVDatabaseAdapter> Function()? _openDatabase;
  static Future<DVDatabaseAdapter>? _database;
  static DVOfflineSend? _send;
  static bool Function() _canReach = () => true;
  static StreamSubscription<bool>? _reachability;
  static Duration _firstRetry = const Duration(seconds: 2);
  static Duration _maxRetry = const Duration(minutes: 5);
  static Duration? _nextRetry;
  static Timer? _retry;
  static Future<void>? _running;
  static bool _again = false;

  /// Wires the runtime to this device, once, as the application starts.
  ///
  /// [database] opens the device store; [send] carries a replay request to
  /// the server; [reachability] is `DV.Platform.network` as a stream of
  /// whether the server can be reached, and [canReachTheServer] its current
  /// answer. A replay runs as soon as this returns, so writes left queued by
  /// the last session go without anything touching their model.
  static void install({
    Future<DVDatabaseAdapter> Function()? database,
    DVOfflineSend? send,
    Stream<bool>? reachability,
    bool Function()? canReachTheServer,
    Duration firstRetry = const Duration(seconds: 2),
    Duration maxRetry = const Duration(minutes: 5),
  }) {
    if (database != null) {
      _openDatabase = database;
      _database = null;
    }
    _send = send;
    _canReach = canReachTheServer ?? () => true;
    _firstRetry = firstRetry;
    _maxRetry = maxRetry;
    unawaited(_reachability?.cancel());
    _reachability = reachability?.listen((bool reachable) {
      if (reachable) _kick();
    });
    _kick();
  }

  /// Declares [model] as an offline data model whose store [build] makes.
  ///
  /// Called from the generated model registration, so the queue of a model
  /// this session never touches is still sent.
  static void register(
    String model,
    DVOfflineStore Function(DVDatabaseAdapter database) build,
  ) {
    _builders[model] = build;
  }

  /// The device database, opened on first use.
  static DVDatabaseAdapter get database => _Deferred(_open);

  static Future<DVDatabaseAdapter> _open() => _database ??= () async {
        final Future<DVDatabaseAdapter> Function()? open = _openDatabase;
        if (open != null) return open();
        // Nothing installed: a plain Dart test, or widget tests that never
        // start the generated runtime. The database the process configured,
        // or memory, which the store reports (DV-OFFLINE-001).
        return const DVDatabase().configuredAdapter ??
            MemoryDVDatabaseAdapter();
      }();

  /// [model]'s store on this device, ready to use.
  static Future<DVOfflineStore> store(String model) =>
      _stores[model] ??= () async {
        final DVOfflineStore Function(DVDatabaseAdapter)? build =
            _builders[model];
        if (build == null) {
          throw StateError('$model is not a registered offline data model');
        }
        final DVOfflineStore store = build(await _open());
        await store.ensureSchema();
        return store;
      }();

  /// A write was queued for [model]: send it if the server can be reached.
  static void written(String model) => _kick();

  /// Completes when no replay is running.
  static Future<void> get idle async {
    while (_running != null) {
      await _running;
    }
  }

  /// Sends what can be sent, then empties every store: signing out.
  ///
  /// A device holds only what its session may read, so nothing the session
  /// wrote may stay behind it. What could not be sent is discarded with it,
  /// which is the same trade a shared kiosk makes; the attempt comes first
  /// so a person signing out on a working connection loses nothing.
  static Future<void> signedOut() async {
    _retry?.cancel();
    _retry = null;
    if (_send != null && _canReach()) {
      _kick();
      await idle.timeout(const Duration(seconds: 10), onTimeout: () {});
    }
    for (final String model in _builders.keys) {
      await (await store(model)).clear();
    }
  }

  /// Forgets everything, for a test.
  static Future<void> resetForTesting() async {
    _retry?.cancel();
    _retry = null;
    await _reachability?.cancel();
    _reachability = null;
    await idle;
    _builders.clear();
    _stores.clear();
    _openDatabase = null;
    _database = null;
    _send = null;
    _canReach = () => true;
    _nextRetry = null;
    _again = false;
  }

  static void _kick() {
    if (_send == null || _builders.isEmpty) return;
    if (_running != null) {
      // A write made during a replay, or a reconnect that fired twice: one
      // more pass after this one, never a second one beside it.
      _again = true;
      return;
    }
    _running = _replayAll().whenComplete(() {
      _running = null;
      if (_again) {
        _again = false;
        _kick();
      }
    });
  }

  static Future<void> _replayAll() async {
    final DVOfflineSend? send = _send;
    if (send == null || !_canReach()) return;
    bool stopped = false;
    for (final String model in _builders.keys.toList()) {
      try {
        final DVOfflineStore store = await DVOfflineSync.store(model);
        final DVReplayResult result =
            await store.replay(_RouteRemote(model, store, send));
        if (result.stopped) stopped = true;
      } catch (error) {
        stopped = true;
        DVObservability.log(
          'Offline sync for $model could not run: $error',
          level: DVLogLevel.warn,
        );
      }
    }
    if (stopped) {
      _scheduleRetry();
    } else {
      _nextRetry = null;
    }
  }

  static void _scheduleRetry() {
    if (_retry?.isActive ?? false) return;
    final Duration wait = _nextRetry ?? _firstRetry;
    final Duration doubled = wait * 2;
    _nextRetry = doubled > _maxRetry ? _maxRetry : doubled;
    _retry = Timer(wait, () {
      _retry = null;
      _kick();
    });
  }
}
