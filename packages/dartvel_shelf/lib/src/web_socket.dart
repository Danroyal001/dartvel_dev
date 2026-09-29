import 'dart:async';
import 'dart:collection';
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

typedef ConnectionCallback = void Function(
  WebSocketChannel channel,
  String? protocol,
);

/// Shelf-style callback and options, with bounded native message queues.
/// Use sink.addStream (or NativeWebSocketChannel.send) for backpressure.
/// sink.add buffers in Dart and applies backpressure to the network,
/// matching dart:io WebSocket semantics without throwing on a full queue.
/// Messages default to at most 1 MiB.
Future<Response> Function(Request) webSocketHandler(
  ConnectionCallback onConnection, {
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
    if (request.method != 'GET' ||
        request.headers.get('upgrade')?.toLowerCase() != 'websocket') {
      return Response.text('WebSocket upgrade required', status: 404);
    }
    final origin = request.headers.get('origin');
    if (origin != null &&
        origins != null &&
        !origins.contains(origin.toLowerCase())) {
      return Response.text('Origin refused', status: 403);
    }
    final tokens = request.headers
        .get('connection')
        ?.toLowerCase()
        .split(',')
        .map((v) => v.trim());
    final key = request.headers.get('sec-websocket-key');
    var validKey = false;
    try {
      validKey = key != null && base64.decode(key).length == 16;
    } on FormatException {
      /* refused below */
    }
    if (tokens?.contains('upgrade') != true ||
        !validKey ||
        request.headers.get('sec-websocket-version') != '13') {
      return Response.text('Invalid WebSocket handshake', status: 400);
    }
    String? protocol;
    for (final value
        in (request.headers.get('sec-websocket-protocol') ?? '').split(',')) {
      if (supported.contains(value.trim())) {
        protocol = value.trim();
        break;
      }
    }
    return WebSocketResponse(
      onConnection,
      protocol,
      maxMessageSize,
      pingInterval,
    );
  };
}

/// Connects Dartvel's structured message/room API to this same transport.
Future<Response> Function(Request) wsHandler(
  WsHandler handler, {
  int maxMessageSize = 1024 * 1024,
}) => webSocketHandler((channel, _) {
  final connection = _Connection(channel as NativeWebSocketChannel);
  WsManager.instance.registerConnection(connection);
  () async {
    try {
      await for (final message in connection.messages) {
        await handler(connection, message);
      }
    } finally {
      WsManager.instance.unregisterConnection(connection.id);
      await connection.close();
    }
  }().catchError((Object _) {
    channel.sink.close(1011, 'Handler failed');
  });
}, maxMessageSize: maxMessageSize);

class WebSocketResponse extends Response {
  WebSocketResponse(this.callback, this.protocol, this.max, this.pingInterval)
    : super(101);
  final ConnectionCallback callback;
  final String? protocol;
  final int max;
  final Duration? pingInterval;
}

class NativeWebSocketChannel(
  this.id,
  this._api,
  this.protocol,
  this.maxMessageSize,
  Duration? pingInterval,
) extends StreamChannelMixin<Object?> implements WebSocketChannel {
  final int id;
  final gen.DartvelShelfBindings _api;
  @override
  final String? protocol;
  final int maxMessageSize;
  @override
  int? closeCode;
  @override
  String? closeReason;
  bool _closed = false;
  bool _paused = false;
  bool _listening = false;
  bool _awaitingPong = false;
  int _pongCount = 0;
  Timer? _timer;
  Timer? _ping;
  late final StreamController<Object?> _controller = StreamController<Object?>(
    sync: true,
    onListen: () {
      _listening = true;
      _drain();
    },
    onPause: () {
      _paused = true;
    },
    onResume: () {
      _paused = false;
      _drain();
    },
    onCancel: () {
      dispose();
    },
  );
  late final _NativeSink _sink = _NativeSink(this);
  final Completer<void> _done = Completer<void>();
  @override
  Future<void> get ready => Future<void>.value();
  @override
  Stream<Object?> get stream => _controller.stream;
  @override
  WebSocketSink get sink => _sink;

  static const int _scratchSize = 64 * 1024;
  late final ffi.Pointer<ffi.Uint8> _scratchPtr = malloc<ffi.Uint8>(_scratchSize);
  late final ffi.Pointer<gen.FfiBuf> _scratchBuf = calloc<gen.FfiBuf>();

  void start(Duration? interval) {
    _drain();
    _sink._pumpOutgoing();
    if (interval != null) {
      _ping = Timer.periodic(interval, (_) {
        final count = _api.aw_ws_pong_count(id);
        if (_awaitingPong && count == _pongCount) {
          dispose();
          return;
        }
        _pongCount = count;
        _awaitingPong = true;
        if (_sendDirect(9, Uint8List(0)) < 0) {
          dispose();
        }
      });
    }
  }

  void onWakeup() {
    _drain();
    _sink._pumpOutgoing();
  }

  void _drain() {
    if (_closed) return;
    while (!_closed) {
      // Once the native task ends, drain its bounded tail even if nobody ever
      // listened. This lets sink.done release the server's channel reference.
      if ((!_listening || _paused) && _api.aw_ws_closed(id) == 0) return;
      final frame = _api.aw_ws_receive(id);
      if (frame.kind == 0) {
        if (_api.aw_ws_closed(id) != 0) {
          closeCode ??= 1006;
          dispose();
        }
        return;
      }
      if (frame.kind < 0) {
        closeCode ??= 1006;
        dispose();
        return;
      }
      switch (frame.kind) {
        case 1:
          final text = utf8.decode(frame.data.ptr.asTypedList(frame.data.len));
          _api.aw_ws_free(frame.data);
          _controller.add(text);
        case 2:
          final bytes = Uint8List.fromList(
            frame.data.ptr.asTypedList(frame.data.len),
          );
          _api.aw_ws_free(frame.data);
          _controller.add(bytes);
        case 9:
          final bytes = Uint8List.fromList(
            frame.data.ptr.asTypedList(frame.data.len),
          );
          _api.aw_ws_free(frame.data);
          if (_sendDirect(10, bytes) < 0) {
            dispose();
          }
        case 10:
          _api.aw_ws_free(frame.data);
          _awaitingPong = false;
        case 8:
          final bytes = Uint8List.fromList(
            frame.data.ptr.asTypedList(frame.data.len),
          );
          _api.aw_ws_free(frame.data);
          if (bytes.length >= 2) {
            closeCode = (bytes[0] << 8) | bytes[1];
            closeReason = utf8.decode(bytes.sublist(2));
          } else {
            closeCode = 1005;
          }
          dispose();
          return;
      }
    }
  }

  /// Waits for native queue capacity. Await each send or use sink.addStream.
  Future<void> send(Object? message) => _sink.send(message);

  int _sendDirect(int kind, Uint8List bytes) {
    if (_closed) return -1;
    if ((kind == 1 || kind == 2) && bytes.length > maxMessageSize) {
      return -1;
    }
    if (bytes.length <= _scratchSize) {
      if (bytes.isNotEmpty) {
        _scratchPtr.asTypedList(bytes.length).setAll(0, bytes);
      }
      _scratchBuf.ref
        ..ptr = _scratchPtr
        ..len = bytes.length;
      return _api.aw_ws_send(id, kind, _scratchBuf.ref);
    }
    final ptr = malloc<ffi.Uint8>(bytes.length);
    final data = calloc<gen.FfiBuf>();
    try {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      data.ref
        ..ptr = ptr
        ..len = bytes.length;
      return _api.aw_ws_send(id, kind, data.ref);
    } finally {
      malloc.free(ptr);
      calloc.free(data);
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _ping?.cancel();
    _sink._onDisposed();
    _api.aw_ws_dispose(id);
    _controller.close();
    _done.complete();
    malloc.free(_scratchPtr);
    calloc.free(_scratchBuf);
  }
}

class _QueuedMessage {
  _QueuedMessage(this.kind, this.bytes, [this.completer]);
  final int kind;
  final Uint8List bytes;
  final Completer<void>? completer;
}

class _NativeSink implements WebSocketSink {
  _NativeSink(this.channel);

  final NativeWebSocketChannel channel;
  final Queue<_QueuedMessage> _outgoing = Queue<_QueuedMessage>();
  bool _closing = false;
  bool _pumping = false;

  Future<void> send(Object? value) {
    if (_closing || channel._closed) {
      throw StateError('WebSocket is closed');
    }
    final int kind;
    final Uint8List bytes;
    if (value is String) {
      kind = 1;
      bytes = utf8.encode(value);
    } else if (value is Uint8List) {
      kind = 2;
      bytes = value;
    } else if (value is List<int>) {
      kind = 2;
      bytes = Uint8List.fromList(value);
    } else {
      throw ArgumentError('WebSocket messages must be String or List<int>');
    }
    if (bytes.length > channel.maxMessageSize) {
      throw ArgumentError('Message exceeds maxMessageSize');
    }
    final completer = Completer<void>.sync();
    _outgoing.add(_QueuedMessage(kind, bytes, completer));
    _pumpOutgoing();
    return completer.future;
  }

  @override
  void add(Object? data) {
    if (_closing || channel._closed) {
      throw StateError('WebSocket is closed');
    }
    final int kind;
    final Uint8List bytes;
    if (data is String) {
      kind = 1;
      bytes = utf8.encode(data);
    } else if (data is Uint8List) {
      kind = 2;
      bytes = data;
    } else if (data is List<int>) {
      kind = 2;
      bytes = Uint8List.fromList(data);
    } else {
      throw ArgumentError('WebSocket messages must be String or List<int>');
    }
    if (bytes.length > channel.maxMessageSize) {
      throw ArgumentError('Message exceeds maxMessageSize');
    }
    _outgoing.add(_QueuedMessage(kind, bytes));
    _pumpOutgoing();
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    channel.dispose();
  }

  @override
  Future<void> addStream(Stream stream) async {
    await for (final value in stream) {
      await send(value);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (_closing || channel._closed) return;
    final code = closeCode ?? 1000;
    if (!(code == 1000 ||
        (code >= 1001 &&
            code <= 1014 &&
            code != 1004 &&
            code != 1005 &&
            code != 1006) ||
        (code >= 3000 && code <= 4999))) {
      throw ArgumentError.value(code, 'closeCode');
    }
    final reason = utf8.encode(closeReason ?? '');
    if (reason.length > 123) {
      throw ArgumentError('Close reason exceeds 123 bytes');
    }
    _closing = true;
    final closeBytes = Uint8List(2 + reason.length);
    closeBytes[0] = code >> 8;
    closeBytes[1] = code & 255;
    closeBytes.setRange(2, closeBytes.length, reason);

    final closeCompleter = Completer<void>();
    _outgoing.add(_QueuedMessage(8, closeBytes, closeCompleter));
    _pumpOutgoing();
    try {
      await closeCompleter.future;
    } finally {
      // Allow the native writer to flush the close before disposing queues.
      Timer(const Duration(seconds: 1), channel.dispose);
    }
  }

  @override
  Future<void> get done => channel._done.future;

  void _pumpOutgoing() {
    if (_pumping || channel._closed || _outgoing.isEmpty) return;
    _pumping = true;
    try {
      while (_outgoing.isNotEmpty && !channel._closed) {
        final msg = _outgoing.first;
        final result = channel._sendDirect(msg.kind, msg.bytes);
        if (result == 0) {
          _outgoing.removeFirst();
          msg.completer?.complete();
        } else if (result == 1) {
          // Native queue full, wait for capacity (via wakeup or timer)
          break;
        } else {
          _outgoing.removeFirst();
          msg.completer?.completeError(
            StateError('WebSocket is closed or message invalid'),
          );
          channel.dispose();
          break;
        }
      }
    } catch (e, st) {
      if (_outgoing.isNotEmpty) {
        final msg = _outgoing.removeFirst();
        msg.completer?.completeError(e, st);
      }
      channel.dispose();
    } finally {
      _pumping = false;
    }
  }

  void _onDisposed() {
    while (_outgoing.isNotEmpty) {
      final msg = _outgoing.removeFirst();
      msg.completer?.completeError(StateError('WebSocket is closed'));
    }
  }
}


class _Connection(this.channel) implements WsConnection {
  final NativeWebSocketChannel channel;
  @override
  String get id => channel.id.toString();
  @override
  bool get isOpen => !channel._closed;
  @override
  Stream<WsMessage> get messages => channel.stream.map(
    (value) => WsMessage.fromJson(
      (jsonDecode(value as String) as Map).cast<String, Object?>(),
    ),
  );
  @override
  void send(WsMessage message) => channel.sink.add(message.toJsonString());
  @override
  void sendRaw(String data) => channel.sink.add(data);
  @override
  Future<void> close([int? code, String? reason]) async {
    await channel.sink.close(code, reason);
  }
}
