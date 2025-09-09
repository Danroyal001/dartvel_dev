import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' as pkgffi;
import '../ffi/runtime.dart' as gen;

class WebSocketChannel {
  final int _wsId;
  final _controller = StreamController<dynamic>();
  WebSocketChannel(this._wsId);
  Stream<dynamic> get stream => _controller.stream;
  void sendText(String text) {
    final bytes = utf8.encode(text);
    final p = pkgffi.malloc.allocate<ffi.Uint8>(bytes.length);
    p.asTypedList(bytes.length).setAll(0, bytes);
    gen.dv_ws_send_text(_wsId, p, bytes.length);
    pkgffi.malloc.free(p);
  }

  void sendBinary(List<int> data) {
    final p = pkgffi.malloc.allocate<ffi.Uint8>(data.length);
    p.asTypedList(data.length).setAll(0, data);
    gen.dv_ws_send_bin(_wsId, p, data.length);
    pkgffi.malloc.free(p);
  }

  Future<void> close([int code = 1000, String reason = '']) async {
    final rb = utf8.encode(reason);
    final p = pkgffi.malloc.allocate<ffi.Uint8>(rb.length);
    p.asTypedList(rb.length).setAll(0, rb);
    gen.dv_ws_close(_wsId, code, p, rb.length);
    pkgffi.malloc.free(p);
  }

  void _onMessage(dynamic msg) => _controller.add(msg);
  void _onDone() => _controller.close();
}
