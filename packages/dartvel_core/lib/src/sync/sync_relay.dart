/// The server end of the sync carrier: accepts WebSocket connections and
/// fans each change out to every other connection of the same tenant.
///
/// The framework's own; hidden from the barrel an application imports.
library dartvel_core.sync.sync_relay;

import 'dart:async';
import 'dart:collection';

import '../tenancy/tenants.dart';
import 'model_sync.dart';
import 'presence.dart';
import 'sync_socket.dart';
import 'sync_wire.dart';

class _Peer {
  final DVSyncWire wire;
  final String tenant;
  String? client;
  Timer? idle;
  int nextId = 1;
  final List<int> unacked = <int>[];
  final Queue<(int, String)> pending = Queue<(int, String)>();

  _Peer(this.wire, this.tenant);
}

/// Fans changes out between connected clients and the server process.
///
/// It is also a transport for the server's own hubs: what clients send
/// arrives on [incoming], and what the server publishes through [send] goes
/// to every client of that change's tenant.
///
/// Delivery to each connection is flow-controlled: at most [window] changes
/// unacknowledged on its wire and [maxPending] more queued for it. A client
/// that falls further behind than that is closed -- it reconnects and
/// carries on -- rather than having the server buffer for it without limit,
/// and it never slows delivery to anybody else. Changes a client sends again
/// after a reconnect are acknowledged and not delivered twice.
class DVSyncRelay implements DVModelSyncTransport, DVPresenceTransport {
  /// How long a connection may say nothing -- not even a heartbeat ping --
  /// before it is closed. A client that vanished without closing would
  /// otherwise be written to forever. Null keeps silent connections.
  final Duration? idleTimeout;

  /// Changes allowed unacknowledged on one connection's wire.
  final int window;

  /// Changes allowed to queue for one connection behind its window.
  final int maxPending;

  /// Clients whose last change number is remembered for dropping repeats.
  final int rememberedClients;

  final Set<_Peer> _peers = <_Peer>{};
  final StreamController<Map<String, Object?>> _incoming =
      StreamController<Map<String, Object?>>.broadcast();
  // ignore: prefer_collection_literals
  final LinkedHashMap<String, int> _lastSeen = LinkedHashMap<String, int>();

  DVSyncRelay({
    this.idleTimeout = const Duration(seconds: 60),
    this.window = 256,
    this.maxPending = 4096,
    this.rememberedClients = 100000,
  });

  /// How many connections are open.
  int get connections => _peers.length;

  /// Takes a connection whose request was authenticated as [tenant].
  ///
  /// The tenant is the server's decision, never the client's: every change
  /// the connection sends is stamped with it, whatever the envelope claimed,
  /// and it only receives changes of that tenant.
  void accept(DVSyncWire wire, {required String tenant}) {
    final _Peer peer = _Peer(wire, tenant);
    _peers.add(peer);
    _heard(peer);
    wire.messages.listen(
      (String text) {
        _heard(peer);
        _onFrame(peer, text);
      },
      onDone: () => _drop(peer),
      onError: (Object _) => _drop(peer),
    );
  }

  void _heard(_Peer peer) {
    final Duration? timeout = idleTimeout;
    if (timeout == null) return;
    peer.idle?.cancel();
    peer.idle = Timer(timeout, () => _drop(peer));
  }

  void _drop(_Peer peer) {
    peer.idle?.cancel();
    peer.pending.clear();
    if (_peers.remove(peer)) unawaited(peer.wire.close());
  }

  void _onFrame(_Peer from, String text) {
    final Map<String, Object?>? frame = DVSyncFrames.decode(text);
    if (frame == null) return;
    switch (frame['op']) {
      case DVSyncFrames.ping:
        from.wire.send(DVSyncFrames.encodeOp(DVSyncFrames.pong));
      case DVSyncFrames.hello:
        final Object? client = frame['client'];
        if (client is String && client.isNotEmpty) {
          // Scoped by tenant, so one tenant's client id cannot shadow
          // another's.
          from.client = '${from.tenant}\u0000$client';
        }
      case DVSyncFrames.ack:
        final Object? upTo = frame['upTo'];
        if (upTo is! int) return;
        from.unacked.removeWhere((int id) => id <= upTo);
        _pump(from);
      case DVSyncFrames.change:
        final Object? id = frame['id'];
        if (id is int) {
          from.wire.send(DVSyncFrames.encodeAck(id));
          if (_isRepeat(from, id)) return;
        }
        final Object? claimed = frame['envelope'];
        if (claimed is! Map<String, Object?>) return;
        final Map<String, Object?> envelope = Map<String, Object?>.of(claimed)
          ..['tenant'] = from.tenant;
        _fanOut(envelope, from.tenant, except: from);
        if (!_incoming.isClosed) _incoming.add(envelope);
    }
  }

  bool _isRepeat(_Peer from, int id) {
    final String? client = from.client;
    if (client == null) return false;
    final int? last = _lastSeen.remove(client);
    if (last != null && id <= last) {
      _lastSeen[client] = last;
      return true;
    }
    _lastSeen[client] = id;
    while (_lastSeen.length > rememberedClients) {
      _lastSeen.remove(_lastSeen.keys.first);
    }
    return false;
  }

  void _deliver(_Peer peer, Map<String, Object?> envelope) {
    final int id = peer.nextId++;
    peer.pending.add((id, DVSyncFrames.encodeChange(envelope, id: id)));
    if (peer.pending.length > maxPending) {
      _drop(peer);
      return;
    }
    _pump(peer);
  }

  void _pump(_Peer peer) {
    while (peer.unacked.length < window && peer.pending.isNotEmpty) {
      final (int id, String frame) = peer.pending.removeFirst();
      peer.unacked.add(id);
      peer.wire.send(frame);
    }
  }

  void _fanOut(Map<String, Object?> envelope, String tenant, {_Peer? except}) {
    for (final _Peer peer in _peers.toList()) {
      if (identical(peer, except) || peer.tenant != tenant) continue;
      _deliver(peer, envelope);
    }
  }

  /// Sends a change the server process published to every client of its
  /// tenant.
  @override
  Future<void> send(Map<String, Object?> envelope) async {
    final Object? stated = envelope['tenant'];
    final String tenant =
        stated is String ? stated : const DVTenants().currentTenant;
    _fanOut(<String, Object?>{...envelope, 'tenant': tenant}, tenant);
  }

  @override
  Stream<Map<String, Object?>> get incoming => _incoming.stream;

  /// Closes every connection.
  Future<void> close() async {
    final List<_Peer> peers = _peers.toList();
    _peers.clear();
    for (final _Peer peer in peers) {
      peer.idle?.cancel();
    }
    await Future.wait(peers.map((_Peer peer) => peer.wire.close()));
    if (!_incoming.isClosed) await _incoming.close();
  }
}
