import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:dartvel_core/http.dart';
// Framework adapter for the core's existing connection contract.
// ignore: implementation_imports
import 'package:dartvel_core/src/websocket/ws.dart';
import 'package:ffi/ffi.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'generated/bindings.dart' as gen;

typedef ConnectionCallback = void Function(WebSocketChannel channel, String? protocol);

/// Shelf-style callback and options, with bounded native message queues.
/// Use sink.addStream (or NativeWebSocketChannel.send) for backpressure.
/// sink.add refuses more than eight outstanding sends rather than buffering
/// an unlimited number of messages. Messages default to at most 1 MiB.
Future<Response> Function(Request) webSocketHandler(ConnectionCallback onConnection, {
  Iterable<String>? protocols,
  Iterable<String>? allowedOrigins,
  Duration? pingInterval,
  int maxMessageSize = 1024 * 1024,
}) {
  if (maxMessageSize <= 0 || maxMessageSize > 64 * 1024 * 1024) {
    throw ArgumentError.value(maxMessageSize, 'maxMessageSize');
  }
  if (pingInterval != null && pingInterval <= Duration.zero) {
    throw ArgumentError.value(pingInterval, 'pingInterval');
  }
  final origins = allowedOrigins?.map((o) => o.toLowerCase()).toSet();
  final supported = protocols?.toSet() ?? <String>{};
  return (request) async {
    if (request.method != 'GET' || request.headers.get('upgrade')?.toLowerCase() != 'websocket') {
      return Response.text('WebSocket upgrade required', status: 404);
    }
    final origin = request.headers.get('origin');
    if (origin != null && origins != null && !origins.contains(origin.toLowerCase())) {
      return Response.text('Origin refused', status: 403);
    }
    final tokens = request.headers.get('connection')?.toLowerCase().split(',').map((v) => v.trim());
    final key = request.headers.get('sec-websocket-key');
    var validKey = false;
    try { validKey = key != null && base64.decode(key).length == 16; } on FormatException { /* refused below */ }
    if (tokens?.contains('upgrade') != true || !validKey || request.headers.get('sec-websocket-version') != '13') {
      return Response.text('Invalid WebSocket handshake', status: 400);
    }
    String? protocol;
    for (final value in (request.headers.get('sec-websocket-protocol') ?? '').split(',')) {
      if (supported.contains(value.trim())) { protocol = value.trim(); break; }
    }
    return WebSocketResponse(onConnection, protocol, maxMessageSize, pingInterval);
  };
}

/// Connects Dartvel's structured message/room API to this same transport.
Future<Response> Function(Request) wsHandler(WsHandler handler, {
  int maxMessageSize = 1024 * 1024,
}) => webSocketHandler((channel, _) {
  final connection = _Connection(channel as NativeWebSocketChannel);
  WsManager.instance.registerConnection(connection);
  () async {
    try {
      await for (final message in connection.messages) { await handler(connection, message); }
    } finally {
      WsManager.instance.unregisterConnection(connection.id);
      await connection.close();
    }
  }().catchError((Object _) { channel.sink.close(1011, 'Handler failed'); });
}, maxMessageSize: maxMessageSize);

class WebSocketResponse extends Response {
  WebSocketResponse(this.callback, this.protocol, this.max, this.pingInterval) : super(101);
  final ConnectionCallback callback;
  final String? protocol;
  final int max;
  final Duration? pingInterval;
}

class NativeWebSocketChannel(this.id, this._api, this.protocol, this.maxMessageSize, Duration? pingInterval)
    extends StreamChannelMixin<Object?> implements WebSocketChannel {
  final int id;
  final gen.DartvelShelfBindings _api;
  @override final String? protocol;
  final int maxMessageSize;
  @override int? closeCode;
  @override String? closeReason;
  bool _closed = false;
  bool _paused = false;
  bool _listening = false;
  bool _awaitingPong = false;
  Timer? _timer;
  Timer? _ping;
  late final StreamController<Object?> _controller = StreamController<Object?>(
    onListen: () { _listening = true; },
    onPause: () { _paused = true; },
    onResume: () { _paused = false; },
    onCancel: () { dispose(); },
  );
  late final _NativeSink _sink = _NativeSink(this);
  final Completer<void> _done = Completer<void>();
  @override Future<void> get ready => Future<void>.value();
  @override Stream<Object?> get stream => _controller.stream;
  @override WebSocketSink get sink => _sink;

  void start(Duration? interval) {
    _timer = Timer.periodic(const Duration(milliseconds: 1), (_) => _poll());
    if (interval != null) {
      _ping = Timer.periodic(interval, (_) {
        if (_awaitingPong) { dispose(); return; }
        _awaitingPong = true;
        _send(9, const []).catchError((Object _) { dispose(); });
      });
    }
  }

  void _poll() {
    if (_closed || !_listening || _paused) return;
    // One event per turn keeps a pause from allowing a burst into Dart.
    final frame = _api.aw_ws_receive(id);
    if (frame.kind == 0) return;
    if (frame.kind < 0) { closeCode ??= 1006; dispose(); return; }
    final bytes = Uint8List.fromList(frame.data.ptr.asTypedList(frame.data.len));
    _api.aw_ws_free(frame.data);
    switch (frame.kind) {
      case 1: _controller.add(utf8.decode(bytes));
      case 2: _controller.add(bytes);
      case 9: _send(10, bytes).catchError((Object _) { dispose(); });
      case 10: _awaitingPong = false;
      case 8:
        if (bytes.length >= 2) {
          closeCode = (bytes[0] << 8) | bytes[1];
          closeReason = utf8.decode(bytes.sublist(2));
        } else { closeCode = 1005; }
        dispose();
    }
  }

  /// Waits for native queue capacity. Await each send or use sink.addStream.
  Future<void> send(Object? message) => _sink.send(message);

  Future<void> _send(int kind, List<int> bytes) async {
    if (_closed) throw StateError('WebSocket is closed');
    if (bytes.length > maxMessageSize) throw ArgumentError('Message exceeds maxMessageSize');
    final ptr = malloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final data = calloc<gen.FfiBuf>();
    ptr.asTypedList(bytes.length).setAll(0, bytes);
    data.ref..ptr = ptr..len = bytes.length;
    try {
      while (!_closed) {
        final result = _api.aw_ws_send(id, kind, data.ref);
        if (result == 0) return;
        if (result < 0) throw StateError('WebSocket is closed or message invalid');
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      throw StateError('WebSocket is closed');
    } finally { malloc.free(ptr); calloc.free(data); }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel(); _ping?.cancel();
    _api.aw_ws_dispose(id);
    _controller.close();
    _done.complete();
  }
}

class _NativeSink(this.channel) implements WebSocketSink {
  final NativeWebSocketChannel channel;
  Future<void> _tail = Future<void>.value();
  int _pending = 0;
  bool _closing = false;
  Future<void> send(Object? value) {
    if (_closing || channel._closed) throw StateError('WebSocket is closed');
    if (_pending >= 8) throw StateError('WebSocket send queue full; await send or use addStream');
    final int kind;
    final List<int> bytes;
    if (value is String) { kind = 1; bytes = utf8.encode(value); }
    else if (value is List<int>) { kind = 2; bytes = List<int>.of(value); }
    else { throw ArgumentError('WebSocket messages must be String or List<int>'); }
    if (bytes.length > channel.maxMessageSize) throw ArgumentError('Message exceeds maxMessageSize');
    _pending++;
    final next = _tail.then((_) => channel._send(kind, bytes)).whenComplete(() { _pending--; });
    _tail = next.catchError((Object _) {});
    return next;
  }
  @override void add(Object? data) { send(data).catchError((Object error, StackTrace stack) {
    if (!channel._closed) channel._controller.addError(error, stack);
    channel.dispose();
  }); }
  @override void addError(Object error, [StackTrace? stackTrace]) { channel.dispose(); }
  @override Future<void> addStream(Stream stream) async {
    await for (final value in stream) { await send(value); }
  }
  @override Future<void> close([int? closeCode, String? closeReason]) async {
    if (_closing || channel._closed) return;
    final code = closeCode ?? 1000;
    if (!(code == 1000 || (code >= 1001 && code <= 1014 && code != 1004 && code != 1005 && code != 1006) || (code >= 3000 && code <= 4999))) {
      throw ArgumentError.value(code, 'closeCode');
    }
    final reason = utf8.encode(closeReason ?? '');
    if (reason.length > 123) throw ArgumentError('Close reason exceeds 123 bytes');
    _closing = true;
    await _tail;
    try { await channel._send(8, [code >> 8, code & 255, ...reason]); }
    finally {
      // Allow the native writer to flush the close before disposing queues.
      Timer(const Duration(seconds: 1), channel.dispose);
    }
  }
  @override Future<void> get done => channel._done.future;
}

class _Connection(this.channel) implements WsConnection {
  final NativeWebSocketChannel channel;
  @override String get id => channel.id.toString();
  @override bool get isOpen => !channel._closed;
  @override Stream<WsMessage> get messages => channel.stream.map((value) =>
      WsMessage.fromJson((jsonDecode(value as String) as Map).cast<String, Object?>()));
  @override void send(WsMessage message) => channel.sink.add(message.toJsonString());
  @override void sendRaw(String data) => channel.sink.add(data);
  @override Future<void> close([int? code, String? reason]) async { await channel.sink.close(code, reason); }
}
