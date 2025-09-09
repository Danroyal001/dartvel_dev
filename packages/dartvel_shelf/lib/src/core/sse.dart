import 'dart:convert';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' as pkgffi;
import '../ffi/runtime.dart' as gen;

class SseSink {
  final int _requestId;
  bool _closed = false;
  SseSink(this._requestId);
  Future<void> event(
      {Object? data, String? event, String? id, int? retryMs}) async {
    final b = StringBuffer();
    if (id != null) b.writeln('id: $id');
    if (event != null) b.writeln('event: $event');
    if (retryMs != null) b.writeln('retry: $retryMs');
    final payload =
        data == null ? '' : (data is String ? data : jsonEncode(data));
    for (final line in payload.split('\n')) {
      b.writeln('data: $line');
    }
    b.writeln();
    final bytes = utf8.encode(b.toString());
    final p = pkgffi.malloc.allocate<ffi.Uint8>(bytes.length);
    p.asTypedList(bytes.length).setAll(0, bytes);
    gen.dv_response_write_for_request(_requestId, p, bytes.length);
    pkgffi.malloc.free(p);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
  }
}
