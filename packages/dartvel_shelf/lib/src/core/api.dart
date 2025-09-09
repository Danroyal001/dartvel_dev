import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import '../ffi/runtime.dart' as gen;
import 'package:ffi/ffi.dart' as pkgffi;
import '../wintercg/request.dart' as w;
import '../wintercg/response.dart' as w;
import '../wintercg/headers.dart';
import 'sse.dart';
import 'websocket.dart';

typedef Handler = FutureOr<w.Response> Function(w.Request);
typedef WsHandler = FutureOr<void> Function(WebSocketChannel);

class DartvelShelf {
  final _routes = <_Route>[];
  final _nativeMw = <Map<String, Object?>>[];
  final _dartHandlers = <int, Handler>{};
  final _wsHandlers = <int, WsHandler>{};
  bool _http10 = true, _http11 = true, _http2 = true, _http3 = true;
  String? _certFile, _keyFile;
  bool _alpnH2 = true;
  int _server = 0;
  int _nextRouteId = 1;
  DartvelShelf http10(bool e) {
    _http10 = e;
    return this;
  }

  DartvelShelf http11(bool e) {
    _http11 = e;
    return this;
  }

  DartvelShelf http2(bool e) {
    _http2 = e;
    return this;
  }

  DartvelShelf http3(bool e) {
    _http3 = e;
    return this;
  }

  DartvelShelf tls(
      {required String certFile, required String keyFile, bool alpnH2 = true}) {
    _certFile = certFile;
    _keyFile = keyFile;
    _alpnH2 = alpnH2;
    return this;
  }

  DartvelShelf use(dynamic mw) {
    final native = _convertToNativeMw(mw);
    if (native != null) _nativeMw.add(native);
    return this;
  }

  DartvelShelf get(String p, Handler h) { _add('GET', p, h); return this; }
  DartvelShelf post(String p, Handler h) { _add('POST', p, h); return this; }
  DartvelShelf put(String p, Handler h) { _add('PUT', p, h); return this; }
  DartvelShelf delete(String p, Handler h) { _add('DELETE', p, h); return this; }
  DartvelShelf head(String p, Handler h) { _add('HEAD', p, h); return this; }
  DartvelShelf options(String p, Handler h) { _add('OPTIONS', p, h); return this; }
  DartvelShelf static(String m, {required String dir}) {
    _routes.add(_Route.native('STATIC', m, {'dir': dir}));
    return this;
  }

  DartvelShelf proxy(String m, {required Uri to}) {
    _routes.add(_Route.native('PROXY', m, {'to': to.toString()}));
    return this;
  }

  DartvelShelf sse(String path, FutureOr<void> Function(SseSink) handler) {
    final id = _nextRouteId++;
    _dartHandlers[id] = (w.Request r) async {
      final rid = r.params['_rid'] == null
          ? r.hashCode
          : int.tryParse(r.params['_rid']!) ?? r.hashCode;
      final sink = SseSink(rid);
      await Future<void>.value(handler(sink));
      return w.Response.sseDone();
    };
    _routes.add(_Route.dart('GET', path, id, flags: {'sse': true}));
    return this;
  }

  DartvelShelf websocket(String path, WsHandler handler) {
    final id = _nextRouteId++;
    _wsHandlers[id] = handler;
    _routes.add(_Route.dart('GET', path, id, flags: {'websocket': true}));
    return this;
  }

  Future<void> listen(
      {String address = '0.0.0.0',
      int port = 8080,
      int? h3Port,
      int isolates = 1}) async {
    final cfgBytes = utf8.encode(jsonEncode({
      'listen': {'address': address, 'port': port, 'h3_port': h3Port},
      'protocols': {
        'http10': _http10,
        'http11': _http11,
        'http2': _http2,
        'http3': _http3
      },
      'tls': {'cert': _certFile, 'key': _keyFile, 'alpn_h2': _alpnH2},
      'routes': _routes.map((r) => r.toJson()).toList(),
      'native_middleware': _nativeMw,
      'dart_hdr_allow': ['authorization', 'content-type'],
    }));
    final p = pkgffi.malloc.allocate<ffi.Uint8>(cfgBytes.length);
    p.asTypedList(cfgBytes.length).setAll(0, cfgBytes);
    _server = gen.dv_server_bootstrap(p, cfgBytes.length);
    pkgffi.malloc.free(p);
    if (_server == 0) {
      final err = gen.dv_last_error();
      throw StateError('Bootstrap failed');
    }
    _runWorker();
  }

  void _runWorker() async {
    final reqPtr = pkgffi.malloc.allocate<gen.RequestEnvelope>(1);
    while (true) {
      final has = gen.dv_server_poll_job(_server, reqPtr);
      if (has == 0) {
        await Future.delayed(Duration(milliseconds: 1));
        continue;
      }
      final e = reqPtr.ref;
      final routeId = e.route_id;
      if (e.method == 7) {
        final ws = WebSocketChannel(e.request_id);
        final h = _wsHandlers[routeId];
        if (h != null) await Future.sync(() => h(ws));
        continue;
      }
      final method = const [
        'GET',
        'POST',
        'PUT',
        'DELETE',
        'PATCH',
        'HEAD',
        'OPTIONS',
        'WS'
      ][e.method];
      // Read URL and headers from RX buffer attached to request_id
      int total = e.path_off + e.path_len;
      total = (e.hdr_off + e.hdr_len) > total ? (e.hdr_off + e.hdr_len) : total;
      total = (e.body_off + e.body_len) > total ? (e.body_off + e.body_len) : total;
      final rxBuf = pkgffi.malloc.allocate<ffi.Uint8>(total);
      final read = gen.dv_request_metadata_read(e.request_id, rxBuf, total);
      final slice = rxBuf.asTypedList(read);
      final urlStr = utf8.decode(slice.sublist(e.path_off, e.path_off + e.path_len));
      final hdrStr = utf8.decode(slice.sublist(e.hdr_off, e.hdr_off + e.hdr_len));
      final bodyBytes = slice.sublist(e.body_off, e.body_off + e.body_len);
      pkgffi.malloc.free(rxBuf);
      final url = Uri.parse(urlStr);
      final headers = Headers();
      try {
        final m = jsonDecode(hdrStr) as Map<String, dynamic>;
        m.forEach((k, v) {
          if (v is List) {
            for (final vv in v) headers.append(k, vv.toString());
          } else if (v != null) {
            headers.append(k, v.toString());
          }
        });
      } catch (_) {}
      final req = w.Request(
          method: method,
          url: url,
          headers: headers,
          bodyStream: Stream<List<int>>.value(bodyBytes),
          params: url.queryParameters);
      final res = await Future<w.Response>.value(_dartHandlers[routeId]!(req));
      final tx = gen.dv_response_open_stream(e.request_id);
      final env = pkgffi.malloc.allocate<gen.ResponseEnvelope>(1);
      env.ref.request_id = e.request_id;
      env.ref.status = res.status;
      env.ref.hdr_off = 0;
      env.ref.hdr_len = 0;
      env.ref.body_tx = tx;
      env.ref.content_len = 0xFFFFFFFFFFFFFFFF;
      env.ref.finalize = res.body == null ? 1 : 0;
      gen.dv_server_submit_response(_server, env);
      pkgffi.malloc.free(env);
      if (res.body != null && !res.isSseNative) {
        await for (final chunk in res.body!.stream) {
          final p = pkgffi.malloc.allocate<ffi.Uint8>(chunk.length);
          p.asTypedList(chunk.length).setAll(0, chunk);
          gen.dv_response_write_chunk(tx, p, chunk.length);
          pkgffi.malloc.free(p);
        }
        gen.dv_response_finalize_stream(tx);
      }
    }
  }

  Map<String, Object?>? _convertToNativeMw(dynamic mw) {
    final s = mw.toString();
    if (s.contains('log')) return {'name': 'log', 'config': {}};
    if (s.contains('gzip'))
      return {
        'name': 'gzip',
        'config': {'level': 5}
      };
    if (s.contains('cors'))
      return {
        'name': 'cors',
        'config': {'origins': '*'}
      };
    return null;
  }

  _Route _add(String method, String path, Handler h) {
    final id = _nextRouteId++;
    _dartHandlers[id] = h;
    final r = _Route.dart(method, path, id);
    _routes.add(r);
    return r;
  }
}

class _Route {
  final bool isDart;
  final String methodOrKind, pathOrMount;
  final int? routeId;
  final Map<String, Object?>? data;
  final Map<String, Object?> flags;
  _Route.dart(this.methodOrKind, this.pathOrMount, this.routeId,
      {this.flags = const {}})
      : isDart = true,
        data = null;
  _Route.native(this.methodOrKind, this.pathOrMount, this.data)
      : isDart = false,
        routeId = null,
        flags = const {};
  Map<String, Object?> toJson() => isDart
      ? {
          'kind': 'dart',
          'method': methodOrKind,
          'path': pathOrMount,
          'route_id': routeId,
          'flags': flags
        }
      : {
          'kind': 'native',
          'what': methodOrKind,
          'mount': pathOrMount,
          'data': data
        };
}
