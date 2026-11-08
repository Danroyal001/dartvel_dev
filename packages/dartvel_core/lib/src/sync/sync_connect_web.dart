// The WHATWG WebSocket, which browsers, Node and Deno share.
import 'dart:async';
import 'dart:js_interop';

import 'sync_wire.dart';

@JS('WebSocket')
extension type _WebSocket._(JSObject _) implements JSObject {
  external factory _WebSocket(JSString url);
  external int get readyState;
  external int get bufferedAmount;
  external void send(JSString data);
  external void close();
  external set onopen(JSFunction? handler);
  external set onmessage(JSFunction? handler);
  external set onclose(JSFunction? handler);
  external set onerror(JSFunction? handler);
}

extension type _MessageEvent._(JSObject _) implements JSObject {
  external JSAny? get data;
}

const int _open = 1;

Future<DVSyncWire> dvConnectSyncWire(Uri url) {
  final Completer<DVSyncWire> opened = Completer<DVSyncWire>();
  final _WebSocket socket = _WebSocket(url.toString().toJS);
  final _BrowserWire wire = _BrowserWire(socket);
  socket.onopen = ((JSAny? _) {
    if (!opened.isCompleted) opened.complete(wire);
  }).toJS;
  socket.onerror = ((JSAny? _) {
    if (!opened.isCompleted) {
      opened.completeError(
        StateError('The WebSocket to $url was refused.'),
      );
    }
  }).toJS;
  socket.onclose = ((JSAny? _) {
    if (!opened.isCompleted) {
      opened.completeError(StateError('The WebSocket to $url closed.'));
    }
    wire._finish();
  }).toJS;
  socket.onmessage = ((_MessageEvent event) {
    final JSAny? data = event.data;
    if (data.isA<JSString>()) wire._messages.add((data as JSString).toDart);
  }).toJS;
  return opened.future;
}

class _BrowserWire implements DVSyncWire {
  final _WebSocket _socket;
  final StreamController<String> _messages = StreamController<String>();

  _BrowserWire(this._socket);

  @override
  Stream<String> get messages => _messages.stream;

  @override
  int get bufferedBytes => _socket.bufferedAmount;

  @override
  void send(String frame) {
    if (_socket.readyState != _open) return;
    _socket.send(frame.toJS);
  }

  void _finish() {
    if (!_messages.isClosed) unawaited(_messages.close());
  }

  @override
  Future<void> close() async {
    _socket.close();
    _finish();
  }
}
