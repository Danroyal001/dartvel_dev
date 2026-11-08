/// The WebSocket carrier that takes model sync and presence envelopes
/// between processes: a client connected to the framework's relay.
///
/// The framework's own; hidden from the barrel an application imports. A
/// model opted into syncing is read and written like any other, and this is
/// what carries the change underneath.
library dartvel_core.sync.sync_socket;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'model_sync.dart';
import 'presence.dart';
import 'reconnect_policy.dart';
import 'sync_wire.dart';

export 'reconnect_policy.dart';

/// Frame operations on the sync wire.
///
/// Every frame is a JSON object with an `op`:
///
/// - `hello` `{client}` opens each connection, naming the client across
///   reconnects so repeats can be told apart;
/// - `change` `{id, envelope}` carries one envelope, exactly as
///   `DVModelSync` or `DVPresence` produced it, numbered per sender;
/// - `ack` `{upTo}` acknowledges every change up to that number, and is
///   what opens the sender's window again;
/// - `ping` and `pong` are the heartbeat.
abstract final class DVSyncFrames {
  static const String hello = 'hello';
  static const String change = 'change';
  static const String ack = 'ack';
  static const String ping = 'ping';
  static const String pong = 'pong';

  static String encodeChange(Map<String, Object?> envelope, {int? id}) =>
      jsonEncode(<String, Object?>{
        'op': change,
        if (id != null) 'id': id,
        'envelope': envelope,
      });

  static String encodeAck(int upTo) =>
      jsonEncode(<String, Object?>{'op': ack, 'upTo': upTo});

  static String encodeHello(String client) =>
      jsonEncode(<String, Object?>{'op': hello, 'client': client});

  static String encodeOp(String op) => jsonEncode(<String, Object?>{'op': op});

  /// The frame as a map, or null when it is not a JSON object.
  static Map<String, Object?>? decode(String frame) {
    try {
      final Object? decoded = jsonDecode(frame);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}

/// Where a [DVSyncSocket] stands.
enum DVSyncSocketState {
  /// Not yet connected.
  idle,

  /// The first connection is being opened.
  connecting,

  /// Open; sends go out as the window allows.
  connected,

  /// The connection dropped and the reconnect policy is bringing it back;
  /// sends are held until it is.
  reconnecting,

  /// The reconnect policy gave up. Sends throw.
  failed,

  /// Closed by its owner. Sends throw.
  closed,
}

/// What a full send queue does to the next send.
enum DVSyncOverflow {
  /// The send waits until there is room: the publisher slows to the pace
  /// the far end acknowledges at. Nothing is lost.
  wait,

  /// The oldest queued change is shed to make room, and counted in
  /// [DVSyncSocket.dropped]. For changes a later one supersedes, such as a
  /// cursor position.
  dropOldest,
}

class _Outgoing {
  final int id;
  final String frame;

  _Outgoing(this.id, this.frame);
}

/// A WebSocket client of the sync relay, usable as the transport for both
/// model sync and presence.
///
/// A dropped connection is reopened on [reconnect]'s backoff, and changes
/// sent meanwhile are held and sent once it is back. A link that stops
/// answering without closing -- a phone that walked out of Wi-Fi, a NAT that
/// forgot the mapping -- is caught by the heartbeat: a ping every
/// [heartbeat], and a connection that has said nothing for
/// [heartbeatTimeout] is treated as dropped.
///
/// Sending is flow-controlled. At most [maxInFlight] changes are on the wire
/// unacknowledged; up to [maxQueued] more wait behind them; past that,
/// [overflow] decides. Changes still unacknowledged when a connection drops
/// are sent again, under the same number, once it is back, and the relay
/// drops the repeats.
class DVSyncSocket implements DVModelSyncTransport, DVPresenceTransport {
  /// The relay endpoint, `ws://` or `wss://`.
  final Uri url;

  final DVReconnectPolicy reconnect;

  /// How often to ping; null turns the heartbeat off.
  final Duration? heartbeat;

  /// How long the connection may stay silent before it counts as dropped.
  final Duration heartbeatTimeout;

  /// Changes allowed on the wire unacknowledged.
  final int maxInFlight;

  /// Changes allowed to wait behind the window.
  final int maxQueued;

  final DVSyncOverflow overflow;

  final Future<DVSyncWire> Function(Uri url) _connector;
  final StreamController<Map<String, Object?>> _incoming =
      StreamController<Map<String, Object?>>.broadcast();
  final String _client = _clientId();
  final List<_Outgoing> _unacked = <_Outgoing>[];
  final Queue<_Outgoing> _queued = Queue<_Outgoing>();
  final List<Completer<void>> _roomWaiters = <Completer<void>>[];
  int _nextId = 1;
  int _dropped = 0;
  DVSyncWire? _wire;
  DVSyncSocketState _state = DVSyncSocketState.idle;
  int _attempt = 0;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  DateTime _lastHeard = DateTime.now();

  DVSyncSocket(
    this.url, {
    this.reconnect = const DVReconnectPolicy(),
    this.heartbeat = const Duration(seconds: 20),
    Duration? heartbeatTimeout,
    this.maxInFlight = 64,
    this.maxQueued = 1024,
    this.overflow = DVSyncOverflow.wait,
    Future<DVSyncWire> Function(Uri url)? connector,
  })  : assert(maxInFlight >= 1),
        assert(maxQueued >= 0),
        heartbeatTimeout = heartbeatTimeout ??
            (heartbeat == null ? Duration.zero : heartbeat * 3),
        _connector = connector ?? DVSyncWire.connect;

  static String _clientId() {
    final Random random = Random.secure();
    return List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  DVSyncSocketState get state => _state;

  /// Whether a connection is open now.
  bool get isConnected => _state == DVSyncSocketState.connected;

  /// Changes shed by [DVSyncOverflow.dropOldest].
  int get dropped => _dropped;

  /// Changes sent and not yet acknowledged, plus those queued behind them.
  int get pending => _unacked.length + _queued.length;

  /// Opens the first connection. Throws when the relay refuses it; after
  /// that, drops are recovered by the reconnect policy.
  Future<void> connect() async {
    if (_state == DVSyncSocketState.closed) {
      throw StateError('This sync socket is closed.');
    }
    if (_state != DVSyncSocketState.idle) return;
    _state = DVSyncSocketState.connecting;
    final DVSyncWire wire;
    try {
      wire = await _connector(url);
    } on Object {
      if (_state == DVSyncSocketState.connecting) {
        _state = DVSyncSocketState.idle;
      }
      rethrow;
    }
    if (_state == DVSyncSocketState.closed) {
      await wire.close();
      return;
    }
    _attach(wire);
  }

  void _attach(DVSyncWire wire) {
    _wire = wire;
    _state = DVSyncSocketState.connected;
    _attempt = 0;
    _lastHeard = DateTime.now();
    wire.messages.listen(
      _onFrame,
      onDone: () => _connectionLost(wire),
      onError: (Object _) => _connectionLost(wire),
    );
    wire.send(DVSyncFrames.encodeHello(_client));
    // What the last connection never acknowledged goes again, in order and
    // under the same numbers, ahead of anything new.
    for (final _Outgoing outgoing in _unacked) {
      wire.send(outgoing.frame);
    }
    _pump();
    final Duration? interval = heartbeat;
    if (interval != null) {
      _heartbeatTimer = Timer.periodic(interval, (_) {
        if (DateTime.now().difference(_lastHeard) > heartbeatTimeout) {
          _connectionLost(wire);
          return;
        }
        wire.send(DVSyncFrames.encodeOp(DVSyncFrames.ping));
      });
    }
  }

  void _pump() {
    final DVSyncWire? wire = _wire;
    if (wire == null || _state != DVSyncSocketState.connected) return;
    while (_unacked.length < maxInFlight && _queued.isNotEmpty) {
      final _Outgoing outgoing = _queued.removeFirst();
      _unacked.add(outgoing);
      wire.send(outgoing.frame);
    }
  }

  void _wakeWaiters() {
    final List<Completer<void>> waiters = List<Completer<void>>.of(_roomWaiters);
    _roomWaiters.clear();
    for (final Completer<void> waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  void _failWaiters(Object error) {
    final List<Completer<void>> waiters = List<Completer<void>>.of(_roomWaiters);
    _roomWaiters.clear();
    for (final Completer<void> waiter in waiters) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
  }

  void _connectionLost(DVSyncWire wire) {
    if (!identical(_wire, wire)) return;
    _wire = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    unawaited(wire.close());
    if (_state == DVSyncSocketState.closed) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _attempt++;
    final Duration? delay = reconnect.delayFor(_attempt);
    if (delay == null) {
      _state = DVSyncSocketState.failed;
      _unacked.clear();
      _queued.clear();
      _failWaiters(StateError('The sync socket to $url gave up reconnecting.'));
      return;
    }
    _state = DVSyncSocketState.reconnecting;
    _reconnectTimer = Timer(delay, _tryReconnect);
  }

  Future<void> _tryReconnect() async {
    if (_state != DVSyncSocketState.reconnecting) return;
    final DVSyncWire wire;
    try {
      wire = await _connector(url);
    } on Object {
      if (_state == DVSyncSocketState.reconnecting) _scheduleReconnect();
      return;
    }
    if (_state != DVSyncSocketState.reconnecting) {
      await wire.close();
      return;
    }
    _attach(wire);
  }

  void _onFrame(String text) {
    _lastHeard = DateTime.now();
    final Map<String, Object?>? frame = DVSyncFrames.decode(text);
    if (frame == null) return;
    switch (frame['op']) {
      case DVSyncFrames.change:
        final Object? envelope = frame['envelope'];
        if (envelope is Map<String, Object?> && !_incoming.isClosed) {
          _incoming.add(envelope);
        }
        final Object? id = frame['id'];
        if (id is int) _wire?.send(DVSyncFrames.encodeAck(id));
      case DVSyncFrames.ack:
        final Object? upTo = frame['upTo'];
        if (upTo is! int) return;
        _unacked.removeWhere((_Outgoing outgoing) => outgoing.id <= upTo);
        _pump();
        _wakeWaiters();
      case DVSyncFrames.ping:
        _wire?.send(DVSyncFrames.encodeOp(DVSyncFrames.pong));
    }
  }

  void _checkSendable() {
    switch (_state) {
      case DVSyncSocketState.idle:
        throw StateError('The sync socket to $url is not connected.');
      case DVSyncSocketState.failed:
        throw StateError('The sync socket to $url gave up reconnecting.');
      case DVSyncSocketState.closed:
        throw StateError('The sync socket to $url is closed.');
      case DVSyncSocketState.connecting:
      case DVSyncSocketState.connected:
      case DVSyncSocketState.reconnecting:
        return;
    }
  }

  /// Queues [envelope] for the relay. Completes once it is on the wire or
  /// queued behind the window; when both are full it waits for room, or
  /// sheds the oldest queued change, as [overflow] says.
  @override
  Future<void> send(Map<String, Object?> envelope) async {
    _checkSendable();
    while (pending >= maxInFlight + maxQueued) {
      if (overflow == DVSyncOverflow.dropOldest && _queued.isNotEmpty) {
        _queued.removeFirst();
        _dropped++;
        break;
      }
      final Completer<void> room = Completer<void>();
      _roomWaiters.add(room);
      await room.future;
      _checkSendable();
    }
    final int id = _nextId++;
    _queued.add(_Outgoing(id, DVSyncFrames.encodeChange(envelope, id: id)));
    _pump();
  }

  @override
  Stream<Map<String, Object?>> get incoming => _incoming.stream;

  /// Closes the connection for good: no further reconnects.
  Future<void> close() async {
    if (_state == DVSyncSocketState.closed) return;
    _state = DVSyncSocketState.closed;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _unacked.clear();
    _queued.clear();
    _failWaiters(StateError('The sync socket to $url is closed.'));
    final DVSyncWire? wire = _wire;
    _wire = null;
    await wire?.close();
    await _incoming.close();
  }
}
