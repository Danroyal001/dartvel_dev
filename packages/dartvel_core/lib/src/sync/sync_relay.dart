/// The server end of the sync carrier: accepts WebSocket connections and
/// fans each change out to every other connection of the same tenant.
///
/// The framework's own; hidden from the barrel an application imports.
library dartvel_core.sync.sync_relay;

import 'dart:async';

import '../tenancy/tenants.dart';
import 'model_sync.dart';
import 'presence.dart';
import 'sync_socket.dart';
import 'sync_wire.dart';

class _Peer {
  final DVSyncWire wire;
  final String tenant;
  Timer? idle;

  _Peer(this.wire, this.tenant);
}

/// Fans changes out between connected clients and the server process.
///
/// It is also a transport for the server's own hubs: what clients send
/// arrives on [incoming], and what the server publishes through [send] goes
/// to every client of that change's tenant.
class DVSyncRelay implements DVModelSyncTransport, DVPresenceTransport {
  /// How long a connection may say nothing -- not even a heartbeat ping --
  /// before it is closed. A client that vanished without closing would
  /// otherwise be written to forever. Null keeps silent connections.
  final Duration? idleTimeout;

  final Set<_Peer> _peers = <_Peer>{};
  final StreamController<Map<String, Object?>> _incoming =
      StreamController<Map<String, Object?>>.broadcast();

  DVSyncRelay({this.idleTimeout = const Duration(seconds: 60)});

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
    if (_peers.remove(peer)) unawaited(peer.wire.close());
  }

  void _onFrame(_Peer from, String text) {
    final Map<String, Object?>? frame = DVSyncFrames.decode(text);
    if (frame == null) return;
    switch (frame['op']) {
      case DVSyncFrames.ping:
        from.wire.send(DVSyncFrames.encodeOp(DVSyncFrames.pong));
      case DVSyncFrames.change:
        final Object? claimed = frame['envelope'];
        if (claimed is! Map<String, Object?>) return;
        final Map<String, Object?> envelope = Map<String, Object?>.of(claimed)
          ..['tenant'] = from.tenant;
        _fanOut(envelope, from.tenant, except: from);
        if (!_incoming.isClosed) _incoming.add(envelope);
    }
  }

  void _fanOut(Map<String, Object?> envelope, String tenant, {_Peer? except}) {
    final String frame = DVSyncFrames.encodeChange(envelope);
    for (final _Peer peer in _peers.toList()) {
      if (identical(peer, except) || peer.tenant != tenant) continue;
      peer.wire.send(frame);
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
