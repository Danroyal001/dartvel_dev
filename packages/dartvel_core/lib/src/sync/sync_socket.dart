/// The WebSocket carrier that takes model sync and presence envelopes
/// between processes: a client connected to the framework's relay.
///
/// The framework's own; hidden from the barrel an application imports. A
/// model opted into syncing is read and written like any other, and this is
/// what carries the change underneath.
library dartvel_core.sync.sync_socket;

import 'dart:async';
import 'dart:convert';

import 'model_sync.dart';
import 'presence.dart';
import 'reconnect_policy.dart';
import 'sync_wire.dart';

export 'reconnect_policy.dart';

/// Frame operations on the sync wire.
///
/// Every frame is a JSON object with an `op`. A change carries one envelope,
/// exactly as `DVModelSync` or `DVPresence` produced it; `ping` and `pong`
/// are the heartbeat.
abstract final class DVSyncFrames {
  static const String change = 'change';
  static const String ping = 'ping';
  static const String pong = 'pong';

  static String encodeChange(Map<String, Object?> envelope) =>
      jsonEncode(<String, Object?>{'op': change, 'envelope': envelope});

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

  /// Open; sends go straight out.
  connected,

  /// The connection dropped and the reconnect policy is bringing it back;
  /// sends are held until it is.
  reconnecting,

  /// The reconnect policy gave up. Sends throw.
  failed,

  /// Closed by its owner. Sends throw.
  closed,
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
class DVSyncSocket implements DVModelSyncTransport, DVPresenceTransport {
  /// The relay endpoint, `ws://` or `wss://`.
  final Uri url;

  final DVReconnectPolicy reconnect;

  /// How often to ping; null turns the heartbeat off.
  final Duration? heartbeat;

  /// How long the connection may stay silent before it counts as dropped.
  final Duration heartbeatTimeout;

  final Future<DVSyncWire> Function(Uri url) _connector;
  final StreamController<Map<String, Object?>> _incoming =
      StreamController<Map<String, Object?>>.broadcast();
  final List<String> _held = <String>[];
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
    Future<DVSyncWire> Function(Uri url)? connector,
  })  : heartbeatTimeout = heartbeatTimeout ??
            (heartbeat == null ? Duration.zero : heartbeat * 3),
        _connector = connector ?? DVSyncWire.connect;

  DVSyncSocketState get state => _state;

  /// Whether a connection is open now.
  bool get isConnected => _state == DVSyncSocketState.connected;

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
      onDone: () => _dropped(wire),
      onError: (Object _) => _dropped(wire),
    );
    for (final String frame in _held) {
      wire.send(frame);
    }
    _held.clear();
    final Duration? interval = heartbeat;
    if (interval != null) {
      _heartbeatTimer = Timer.periodic(interval, (_) {
        if (DateTime.now().difference(_lastHeard) > heartbeatTimeout) {
          _dropped(wire);
          return;
        }
        wire.send(DVSyncFrames.encodeOp(DVSyncFrames.ping));
      });
    }
  }

  void _dropped(DVSyncWire wire) {
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
      _held.clear();
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
      case DVSyncFrames.ping:
        _wire?.send(DVSyncFrames.encodeOp(DVSyncFrames.pong));
    }
  }

  @override
  Future<void> send(Map<String, Object?> envelope) async {
    final String frame = DVSyncFrames.encodeChange(envelope);
    switch (_state) {
      case DVSyncSocketState.connected:
        _wire!.send(frame);
      case DVSyncSocketState.connecting:
      case DVSyncSocketState.reconnecting:
        _held.add(frame);
      case DVSyncSocketState.idle:
        throw StateError('The sync socket to $url is not connected.');
      case DVSyncSocketState.failed:
        throw StateError('The sync socket to $url gave up reconnecting.');
      case DVSyncSocketState.closed:
        throw StateError('The sync socket to $url is closed.');
    }
  }

  @override
  Stream<Map<String, Object?>> get incoming => _incoming.stream;

  /// Closes the connection for good: no further reconnects.
  Future<void> close() async {
    if (_state == DVSyncSocketState.closed) return;
    _state = DVSyncSocketState.closed;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _held.clear();
    final DVSyncWire? wire = _wire;
    _wire = null;
    await wire?.close();
    await _incoming.close();
  }
}
