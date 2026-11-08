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
import 'sync_wire.dart';

/// Frame operations on the sync wire.
///
/// Every frame is a JSON object with an `op`. A change carries one envelope,
/// exactly as `DVModelSync` or `DVPresence` produced it.
abstract final class DVSyncFrames {
  static const String change = 'change';

  static String encodeChange(Map<String, Object?> envelope) =>
      jsonEncode(<String, Object?>{'op': change, 'envelope': envelope});

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

/// A WebSocket client of the sync relay, usable as the transport for both
/// model sync and presence.
class DVSyncSocket implements DVModelSyncTransport, DVPresenceTransport {
  /// The relay endpoint, `ws://` or `wss://`.
  final Uri url;

  final Future<DVSyncWire> Function(Uri url) _connector;
  final StreamController<Map<String, Object?>> _incoming =
      StreamController<Map<String, Object?>>.broadcast();
  DVSyncWire? _wire;
  bool _closed = false;

  DVSyncSocket(this.url, {Future<DVSyncWire> Function(Uri url)? connector})
      : _connector = connector ?? DVSyncWire.connect;

  /// Whether a connection is open now.
  bool get isConnected => _wire != null;

  /// Opens the connection. Throws when the relay refuses it.
  Future<void> connect() async {
    if (_closed) throw StateError('This sync socket is closed.');
    final DVSyncWire wire = await _connector(url);
    _wire = wire;
    wire.messages.listen(_onFrame, onDone: () {
      if (identical(_wire, wire)) _wire = null;
    }, onError: (Object _) {});
  }

  void _onFrame(String text) {
    final Map<String, Object?>? frame = DVSyncFrames.decode(text);
    if (frame == null) return;
    if (frame['op'] == DVSyncFrames.change) {
      final Object? envelope = frame['envelope'];
      if (envelope is Map<String, Object?> && !_incoming.isClosed) {
        _incoming.add(envelope);
      }
    }
  }

  @override
  Future<void> send(Map<String, Object?> envelope) async {
    final DVSyncWire? wire = _wire;
    if (wire == null) {
      throw StateError('The sync socket to $url is not connected.');
    }
    wire.send(DVSyncFrames.encodeChange(envelope));
  }

  @override
  Stream<Map<String, Object?>> get incoming => _incoming.stream;

  /// Closes the connection for good.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final DVSyncWire? wire = _wire;
    _wire = null;
    await wire?.close();
    await _incoming.close();
  }
}
