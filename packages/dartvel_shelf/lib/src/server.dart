import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

import 'generated/bindings.dart' as gen; // produced by ffigen via build hook
import 'package:dartvel_core/http.dart';

import 'ffi_string.dart';
import 'header_codec.dart';
import 'ssr_helper.dart';
import 'package:ffi/ffi.dart' as pkgffi;

typedef _NativeCb = gen.DartReqHandlerFunction;
typedef _NativeCancelCb = gen.DartStreamCancelHandlerFunction;

class ServerHandle {
  final String host;
  final int port;
  final int _id;
  final gen.DartvelShelfBindings _api;
  final ffi.NativeCallable<_NativeCb> _dartHandler;
  final ffi.NativeCallable<_NativeCancelCb> _dartCancelHandler;
  bool _stopped = false;

  ServerHandle(
    this.host,
    this.port,
    this._id,
    this._api,
    this._dartHandler,
    this._dartCancelHandler,
  );

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _api.aw_stop(_id);
    _dartHandler.close();
    _dartCancelHandler.close();
  }
}

class TlsConfig {
  final String certPem; // PEM contents
  final String keyPem; // PEM contents
  const TlsConfig({required this.certPem, required this.keyPem});
}

class CorsOptions {
  final bool allowAnyOrigin;
  final List<String> origins;
  final bool allowAnyMethod;
  final List<String> methods;
  final bool allowAnyHeader;
  final List<String> headers;
  final List<String> exposeHeaders;
  final bool allowCredentials;
  final Duration? maxAge;

  const CorsOptions({
    this.allowAnyOrigin = false,
    this.origins = const [],
    this.allowAnyMethod = false,
    this.methods = const [],
    this.allowAnyHeader = false,
    this.headers = const [],
    this.exposeHeaders = const [],
    this.allowCredentials = false,
    this.maxAge,
  }) : assert(
          !allowCredentials || !allowAnyOrigin,
          'allowCredentials cannot be used when allowAnyOrigin is true',
        );

  Map<String, Object?> toJson() => {
        'allowAnyOrigin': allowAnyOrigin,
        if (!allowAnyOrigin && origins.isNotEmpty) 'origins': origins,
        'allowAnyMethod': allowAnyMethod,
        if (!allowAnyMethod && methods.isNotEmpty) 'methods': methods,
        'allowAnyHeader': allowAnyHeader,
        if (!allowAnyHeader && headers.isNotEmpty) 'headers': headers,
        if (exposeHeaders.isNotEmpty) 'exposeHeaders': exposeHeaders,
        'allowCredentials': allowCredentials,
        if (maxAge != null) 'maxAgeSeconds': maxAge!.inSeconds,
      };

  String toJsonString() => jsonEncode(toJson());
}

Future<ServerHandle> serve(
  Future<Response> Function(Request) handler, {
  String host = '127.0.0.1',
  int port = 8080,
  TlsConfig? tls, // enables HTTPS + ALPN → HTTP/2
  bool h2c = false, // plaintext HTTP/2 (advanced)
  CorsOptions? cors,
  String? staticDir, // Path to static files directory
  String? spaRoot, // Path to SPA root (e.g. build/web) for SSR injection
  bool compression = true, // Enable/disable compression
}) async {
  final subdir = Platform.isMacOS
      ? (Platform.version.contains('arm64') ? 'macos-arm64' : 'macos-x64')
      : Platform.isLinux
          ? (Platform.version.contains('aarch64') ? 'linux-arm64' : 'linux-x64')
          : (Platform.version.contains('ARM64')
              ? 'windows-arm64'
              : 'windows-x64');
  final libName = Platform.isWindows
      ? 'dartvel_shelf.dll'
      : Platform.isMacOS
          ? 'libdartvel_shelf.dylib'
          : 'libdartvel_shelf.so';
  final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_shelf/native/$subdir/$libName'));
  final dylib = ffi.DynamicLibrary.open(uri!.toFilePath());

  final api = gen.DartvelShelfBindings(dylib);

  // Wrap handler with SSR middleware if spaRoot is provided
  var effectiveHandler = handler;
  if (spaRoot != null) {
    effectiveHandler = (Request req) async {
      // 1. Try serving static file from spaRoot
      final pathPart = req.url.path.startsWith('/')
          ? req.url.path.substring(1)
          : req.url.path;
      if (pathPart.isNotEmpty && !pathPart.contains('..')) {
        final file = File(p.join(spaRoot, pathPart));
        if (await file.exists() && (await FileSystemEntity.isFile(file.path))) {
          final bytes = await file.readAsBytes();
          final mime = getMimeType(file.path);
          return Response(200,
              headers: Headers()..set('content-type', mime),
              body: Stream.value(bytes));
        }
      }

      // 2. Fall back to normal handler or SPA index
      final resp = await handler(req);
      if (resp.status == 404 && req.method == 'GET') {
        return handleSsrFallback(req, spaRoot);
      }
      return resp;
    };
  }

  final effective =
      (effectiveHandler is Router) ? effectiveHandler.call : effectiveHandler;

  final activeSubscriptions = <int, StreamSubscription<List<int>>>{};

  void handleRequest(int reqId, gen.FfiStr method, gen.FfiStr target,
      ffi.Pointer<ffi.Uint8> hdrsPtr, int hdrsLen, gen.FfiBuf body) {
    final methodStr = String.fromCharCodes(
        method.ptr.cast<ffi.Uint8>().asTypedList(method.len));
    final targetStr = String.fromCharCodes(
        target.ptr.cast<ffi.Uint8>().asTypedList(target.len));
    final headers =
        decodeHeaders(hdrsPtr.cast<ffi.Uint8>().asTypedList(hdrsLen));
    final url = Uri.parse('http://$host:$port$targetStr');
    final bodyBytes =
        Uint8List.fromList(body.ptr.cast<ffi.Uint8>().asTypedList(body.len));

    Future<void>(() async {
      final req = Request(
        method: methodStr,
        url: url,
        headers: Headers(headers),
        bodyStream: Stream<List<int>>.value(bodyBytes),
      );

      try {
        final resp = await effective(req);
        final hdrsFlat = encodeHeaders(resp.headers.multiValueMap);
        final hdrsNative = pkgffi.malloc<ffi.Uint8>(hdrsFlat.length)
          ..asTypedList(hdrsFlat.length).setAll(0, hdrsFlat);

        final out = pkgffi.calloc<gen.FfiResp>();
        out.ref.status = resp.status;
        out.ref.hdrs = hdrsNative.cast();
        out.ref.hdrs_len = hdrsFlat.length;

        final isSse =
            resp.headers.get('content-type')?.contains('text/event-stream') ==
                true;
        final isStream = resp.isStream || isSse;

        if (isStream && resp.body != null) {
          out.ref.is_stream = 1;
          final bodyBuf = pkgffi.calloc<gen.FfiBuf>();
          bodyBuf.ref.ptr = ffi.Pointer.fromAddress(0);
          bodyBuf.ref.len = 0;
          out.ref.body = bodyBuf.ref;

          api.aw_complete(reqId, out.ref);
          pkgffi.calloc.free(bodyBuf);
          pkgffi.calloc.free(out);

          late StreamSubscription<List<int>> subscription;
          subscription = resp.body!.stream.listen(
            (chunk) {
              final chunkNative = pkgffi.malloc<ffi.Uint8>(chunk.length)
                ..asTypedList(chunk.length).setAll(0, chunk);
              final chunkBuf = pkgffi.calloc<gen.FfiBuf>();
              chunkBuf.ref.ptr = chunkNative.cast();
              chunkBuf.ref.len = chunk.length;

              api.aw_stream_send_chunk(reqId, chunkBuf.ref);

              pkgffi.calloc.free(chunkBuf);
              pkgffi.malloc.free(chunkNative);
            },
            onDone: () {
              activeSubscriptions.remove(reqId);
              api.aw_stream_complete(reqId);
            },
            onError: (Object e) {
              activeSubscriptions.remove(reqId);
              api.aw_stream_complete(reqId);
            },
            cancelOnError: true,
          );
          activeSubscriptions[reqId] = subscription;
        } else {
          out.ref.is_stream = 0;
          final bodyData = await resp.body?.bytesU8() ?? Uint8List(0);
          final bodyNative = pkgffi.malloc<ffi.Uint8>(bodyData.length)
            ..asTypedList(bodyData.length).setAll(0, bodyData);

          final bodyBuf = pkgffi.calloc<gen.FfiBuf>();
          bodyBuf.ref.ptr = bodyNative.cast();
          bodyBuf.ref.len = bodyData.length;
          out.ref.body = bodyBuf.ref;

          api.aw_complete(reqId, out.ref);
          pkgffi.calloc.free(bodyBuf);
          pkgffi.calloc.free(out);
        }
      } catch (_) {
        final out = pkgffi.calloc<gen.FfiResp>();
        out.ref.status = 500;
        out.ref.is_stream = 0;
        out.ref.body = (pkgffi.calloc<gen.FfiBuf>()..ref.len = 0).ref;
        out.ref.hdrs = pkgffi.malloc<ffi.Uint8>(0).cast();
        out.ref.hdrs_len = 0;
        api.aw_complete(reqId, out.ref);
        pkgffi.calloc.free(out);
      }
    });
  }

  final dartRequestHandler =
      ffi.NativeCallable<_NativeCb>.listener(handleRequest);
  api.aw_register_handler(dartRequestHandler.nativeFunction);

  final dartCancelHandler =
      ffi.NativeCallable<_NativeCancelCb>.listener((int reqId) {
    final subscription = activeSubscriptions.remove(reqId);
    subscription?.cancel();
  });
  try {
    api.aw_register_cancel_handler(dartCancelHandler.nativeFunction);
  } on ArgumentError {
    // Older bundled binaries may not expose this FFI symbol. Rust source and
    // generated bindings include it; rebuilding the native asset enables it.
  }

  _configureCors(api, cors);
  _configureStatic(api, staticDir);
  _configureSpaRoot(api, null);
  _configureCompression(api, compression);

  if (tls != null) {
    final certBytes = dvFfiBytes(tls.certPem);
    final keyBytes = dvFfiBytes(tls.keyPem);

    final certPtr = pkgffi.malloc<ffi.Uint8>(certBytes.length)
      ..asTypedList(certBytes.length).setAll(0, certBytes);
    final keyPtr = pkgffi.malloc<ffi.Uint8>(keyBytes.length)
      ..asTypedList(keyBytes.length).setAll(0, keyBytes);

    final certBufPtr = pkgffi.calloc<gen.FfiBuf>();
    certBufPtr.ref
      ..ptr = certPtr.cast()
      ..len = certBytes.length;

    final keyBufPtr = pkgffi.calloc<gen.FfiBuf>();
    keyBufPtr.ref
      ..ptr = keyPtr.cast()
      ..len = keyBytes.length;

    final rcTls = api.aw_tls_rustls_from_pem(certBufPtr.ref, keyBufPtr.ref);

    pkgffi.malloc.free(certPtr);
    pkgffi.malloc.free(keyPtr);
    pkgffi.calloc.free(certBufPtr);
    pkgffi.calloc.free(keyBufPtr);

    if (rcTls != 0) throw StateError('TLS config failed (code=$rcTls)');
  }

  final hostBytes = dvFfiBytes(host);
  final hostPtr = pkgffi.malloc<ffi.Uint8>(hostBytes.length)
    ..asTypedList(hostBytes.length).setAll(0, hostBytes);
  final hostFfiPtr = pkgffi.calloc<gen.FfiStr>();
  hostFfiPtr.ref
    ..ptr = hostPtr.cast()
    ..len = hostBytes.length;

  final flags = h2c ? 0x01 : 0x00; // AW_FLAG_H2C
  final serverId = api.aw_start(hostFfiPtr.ref, port, flags);

  pkgffi.malloc.free(hostPtr);
  pkgffi.calloc.free(hostFfiPtr);

  if (serverId <= 0) {
    // Named rather than numeric, because "aw_start failed (-3)" sends the
    // reader into the FFI layer to find out that a port was in use.
    final reason = switch (serverId) {
      -2 => 'could not parse "$host:$port" as an address',
      -3 => 'could not bind $host:$port — in use, or not permitted',
      _ => 'aw_start failed ($serverId)',
    };
    throw StateError('dartvel: $reason');
  }

  // Not `port`: a caller may pass 0 and let the OS assign one, and 0 is not
  // something anything can connect to. The bound port is the only callable
  // answer, and it is also the one to report back for a fixed port, since
  // agreeing with the request is then the same number.
  final boundPort = api.aw_server_port(serverId);

  return ServerHandle(host, boundPort == 0 ? port : boundPort, serverId, api,
      dartRequestHandler, dartCancelHandler);
}

void _configureCors(gen.DartvelShelfBindings api, CorsOptions? cors) {
  final json = cors?.toJsonString() ?? '';
  final bytes = dvFfiBytes(json);
  final strPtr = pkgffi.calloc<gen.FfiStr>();
  ffi.Pointer<ffi.Uint8>? dataPtr;
  if (bytes.isEmpty) {
    strPtr.ref
      ..ptr = ffi.Pointer.fromAddress(0)
      ..len = 0;
  } else {
    dataPtr = pkgffi.malloc<ffi.Uint8>(bytes.length)
      ..asTypedList(bytes.length).setAll(0, bytes);
    strPtr.ref
      ..ptr = dataPtr.cast()
      ..len = bytes.length;
  }

  final rc = api.aw_configure_cors(strPtr.ref);

  if (dataPtr != null) {
    pkgffi.malloc.free(dataPtr);
  }
  pkgffi.calloc.free(strPtr);

  if (rc != 0) {
    throw StateError('CORS config failed (code=$rc)');
  }
}

void _configureStatic(gen.DartvelShelfBindings api, String? staticDir) {
  final path = staticDir ?? '';
  final bytes = dvFfiBytes(path);
  final strPtr = pkgffi.calloc<gen.FfiStr>();
  ffi.Pointer<ffi.Uint8>? dataPtr;

  if (bytes.isEmpty) {
    strPtr.ref
      ..ptr = ffi.Pointer.fromAddress(0)
      ..len = 0;
  } else {
    dataPtr = pkgffi.malloc<ffi.Uint8>(bytes.length)
      ..asTypedList(bytes.length).setAll(0, bytes);
    strPtr.ref
      ..ptr = dataPtr.cast()
      ..len = bytes.length;
  }

  final rc = api.aw_configure_static(strPtr.ref);

  if (dataPtr != null) {
    pkgffi.malloc.free(dataPtr);
  }
  pkgffi.calloc.free(strPtr);

  if (rc != 0) {
    throw StateError('Static config failed (code=$rc)');
  }
}

void _configureSpaRoot(gen.DartvelShelfBindings api, String? spaRoot) {
  final path = spaRoot ?? '';
  final bytes = dvFfiBytes(path);
  final strPtr = pkgffi.calloc<gen.FfiStr>();
  ffi.Pointer<ffi.Uint8>? dataPtr;

  if (bytes.isEmpty) {
    strPtr.ref
      ..ptr = ffi.Pointer.fromAddress(0)
      ..len = 0;
  } else {
    dataPtr = pkgffi.malloc<ffi.Uint8>(bytes.length)
      ..asTypedList(bytes.length).setAll(0, bytes);
    strPtr.ref
      ..ptr = dataPtr.cast()
      ..len = bytes.length;
  }

  final rc = api.aw_configure_spa_root(strPtr.ref);

  if (dataPtr != null) {
    pkgffi.malloc.free(dataPtr);
  }
  pkgffi.calloc.free(strPtr);

  if (rc != 0) {
    throw StateError('SPA root config failed (code=$rc)');
  }
}

void _configureCompression(gen.DartvelShelfBindings api, bool enabled) {
  api.aw_configure_compression(enabled ? 1 : 0);
}

String getMimeType(String path) {
  final ext = p.extension(path).toLowerCase();
  switch (ext) {
    case '.html':
      return 'text/html';
    case '.css':
      return 'text/css';
    case '.js':
      return 'application/javascript';
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.gif':
      return 'image/gif';
    case '.svg':
      return 'image/svg+xml';
    case '.json':
      return 'application/json';
    case '.wasm':
      return 'application/wasm';
    default:
      return 'application/octet-stream';
  }
}
