/// One WebSocket connection as the sync carrier and relay see it: text
/// frames in, text frames out, and a close.
///
/// The framework's own; hidden from the barrel an application imports.
library dartvel_core.sync.sync_wire;

import 'dart:async';
import 'dart:convert';

import 'sync_connect_unsupported.dart'
    if (dart.library.io) 'sync_connect_io.dart'
    if (dart.library.js_interop) 'sync_connect_web.dart' as platform;

/// A connected WebSocket, whichever platform opened it.
abstract class DVSyncWire {
  /// Text frames as they arrive. Done when the connection closes, for
  /// whatever reason. Listen once.
  Stream<String> get messages;

  /// Sends one text frame. Ignored once the connection has closed.
  void send(String frame);

  /// Bytes accepted by [send] and not yet handed to the network, where the
  /// platform reports it (a browser's `bufferedAmount`); `0` where it does
  /// not.
  int get bufferedBytes => 0;

  /// Closes the connection. Safe to call more than once.
  Future<void> close();

  /// Wraps anything that is a stream of frames and a sink for them: a
  /// `dart:io` `WebSocket` upgraded by a server is both.
  factory DVSyncWire.of(Stream<Object?> incoming, StreamSink<Object?> outgoing) =
      _StreamWire;

  /// Opens a WebSocket to [url] on this platform: `dart:io` on the VM, the
  /// WHATWG `WebSocket` on the web. Throws when the handshake is refused.
  static Future<DVSyncWire> connect(Uri url) => platform.dvConnectSyncWire(url);
}

class _StreamWire implements DVSyncWire {
  final StreamSink<Object?> _outgoing;
  bool _closed = false;

  @override
  late final Stream<String> messages;

  _StreamWire(Stream<Object?> incoming, this._outgoing) {
    messages = incoming
        .map<String?>((Object? frame) => switch (frame) {
              final String text => text,
              final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
              _ => null,
            })
        .where((String? frame) => frame != null)
        .cast<String>()
        .transform(StreamTransformer<String, String>.fromHandlers(
          handleDone: (EventSink<String> sink) {
            _closed = true;
            sink.close();
          },
        ));
  }

  @override
  int get bufferedBytes => 0;

  @override
  void send(String frame) {
    if (_closed) return;
    try {
      _outgoing.add(frame);
    } on StateError {
      _closed = true;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _outgoing.close().timeout(const Duration(seconds: 2));
    } on Object {
      // Closing a connection the peer already dropped is not an error here.
    }
  }
}
