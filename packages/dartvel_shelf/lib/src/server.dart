import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'generated/bindings.dart' as gen; // produced by ffigen via build hook
import 'wintercg.dart';
import 'router.dart';
import 'header_codec.dart';
import 'package:ffi/ffi.dart' as pkgffi;

typedef _NativeCb = gen.DartReqHandlerFunction;

class ServerHandle {
  final String host;
  final int port;
  final int _id;
  final gen.DartvelShelfBindings _api;
  final ffi.NativeCallable<_NativeCb> _dartHandler;
  bool _stopped = false;

  ServerHandle(
    this.host,
    this.port,
    this._id,
    this._api,
    this._dartHandler,
  );

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _api.aw_stop(_id);
    _dartHandler.close();
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
  final effective = (handler is Router) ? handler.call : handler;

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
        final bodyData = await resp.body?.bytesU8() ?? Uint8List(0);
        final hdrsFlat = encodeHeaders(resp.headers.multiValueMap);

        final hdrsNative = pkgffi.malloc<ffi.Uint8>(hdrsFlat.length)
          ..asTypedList(hdrsFlat.length).setAll(0, hdrsFlat);
        final bodyNative = pkgffi.malloc<ffi.Uint8>(bodyData.length)
          ..asTypedList(bodyData.length).setAll(0, bodyData);

        final out = pkgffi.calloc<gen.FfiResp>();
        out.ref.status = resp.status;

        final bodyBuf = pkgffi.calloc<gen.FfiBuf>();
        bodyBuf.ref.ptr = bodyNative.cast();
        bodyBuf.ref.len = bodyData.length;
        out.ref.body = bodyBuf.ref;

        out.ref.hdrs = hdrsNative.cast();
        out.ref.hdrs_len = hdrsFlat.length;

        api.aw_complete(reqId, out.ref);
        pkgffi.calloc.free(bodyBuf);
        pkgffi.calloc.free(out);
      } catch (_) {
        final out = pkgffi.calloc<gen.FfiResp>();
        out.ref.status = 500;
        out.ref.body = (pkgffi.calloc<gen.FfiBuf>()..ref.len = 0).ref;
        out.ref.hdrs = pkgffi.malloc<ffi.Uint8>(0).cast();
        out.ref.hdrs_len = 0;
        api.aw_complete(reqId, out.ref);
      }
    });
  }

  final dartRequestHandler =
      ffi.NativeCallable<_NativeCb>.listener(handleRequest);

  api.aw_register_handler(dartRequestHandler.nativeFunction);

  _configureCors(api, cors);

  if (tls != null) {
    final certBytes = Uint8List.fromList(tls.certPem.codeUnits);
    final keyBytes = Uint8List.fromList(tls.keyPem.codeUnits);

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

  final hostBytes = Uint8List.fromList(host.codeUnits);
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
    throw StateError('aw_start failed ($serverId)');
  }

  return ServerHandle(host, port, serverId, api, dartRequestHandler);
}

void _configureCors(gen.DartvelShelfBindings api, CorsOptions? cors) {
  final json = cors?.toJsonString() ?? '';
  final bytes = Uint8List.fromList(json.codeUnits);
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
