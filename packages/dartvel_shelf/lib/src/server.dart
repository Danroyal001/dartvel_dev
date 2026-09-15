import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartvel_core/dartvel.dart'
    show
        DVCacheAdapter,
        DVLogLevel,
        DVObservability,
        DVPageDataResolver,
        DVPreviewMembership,
        DVPreviewServer,
        dvConfigureRuntimeLogging;
import 'package:path/path.dart' as p;

import 'generated/bindings.dart' as gen; // produced by ffigen via build hook
import 'package:dartvel_core/http.dart';

import 'ffi_string.dart';
import 'header_codec.dart';
import 'image_endpoint.dart';
import 'ssr_helper.dart';
import 'package:ffi/ffi.dart' as pkgffi;

typedef _NativeCb = gen.DartReqHandlerFunction;

/// The callback shape this file is written for; see `AW_ABI_VERSION` in
/// rust/src/lib.rs. 2 added the peer address.
const int _nativeAbiVersion = 2;
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
  DVPageDataResolver? pageData, // The route's data on request, for the page pipeline
  DVCacheAdapter? pageStore, // Where the kept pages live, when they are shared
  bool compression = true, // Enable/disable compression
  DVPreviewMembership? previewMembership, // Who may open a members-only preview
}) async {
  // Where a log line actually goes. The runtime's logger keeps records in a
  // bounded buffer and writes nowhere else on its own, because a library that
  // printed would put JSON into the middle of a Flutter test's output; a
  // server is the one place stdout is the right destination, and every
  // container runtime and hosted platform already collects it.
  //
  // This also decides whether the diagnostics endpoints answer, which is why
  // it runs before the first request can arrive rather than lazily.
  dvConfigureRuntimeLogging(Platform.environment, write: stdout.writeln);

  // Preview Environments. A generated backend starts the preview before
  // anything else runs; a hand-written entrypoint that calls serve() directly
  // gets it here. Either way a process deployed as a preview does not serve
  // until it has established it is one -- and outside a preview this is null
  // and nothing below changes.
  final DVPreviewServer? preview = DVPreviewServer.current ??
      DVPreviewServer.start(Platform.environment, membership: previewMembership);

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

  // Before anything is registered. A library built for an older callback
  // shape calls the request handler with fewer arguments than it declares,
  // and the missing one is read from whatever the register holds: not an
  // error, a garbage pointer. Refused here, by name, instead.
  final int abi =
      dylib.providesSymbol('aw_abi_version') ? api.aw_abi_version() : 1;
  if (abi != _nativeAbiVersion) {
    throw StateError(
      'dartvel: the native server library at ${uri.toFilePath()} speaks ABI '
      '$abi and this package speaks $_nativeAbiVersion. Rebuild it: '
      'cargo build --release --target <triple> in dartvel_shelf/rust, then '
      'copy the result over that file.',
    );
  }

  // Wrap handler with SSR middleware if spaRoot is provided
  var effectiveHandler = handler;
  if (spaRoot != null) {
    effectiveHandler = (Request req) async {
      // 0. A resized image, before anything else: its address is not a file
      // under spaRoot, and falling through would answer it with the SPA.
      final Response? variant = await dvImageVariantResponse(
        req,
        webRoot: spaRoot,
        variants: dvImageVariantsFor(spaRoot),
        cacheDir: dvImageVariantCacheDir(spaRoot),
      );
      if (variant != null) return variant;

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
        return handleSsrFallback(req, spaRoot, pageData: pageData, pageStore: pageStore);
      }
      return resp;
    };
  }

  final routed =
      (effectiveHandler is Router) ? effectiveHandler.call : effectiveHandler;
  // The preview's gate goes outermost, around the site's files and assembled
  // pages as well as the router: installed on the router alone, a link-only
  // preview's whole web build would be readable by anybody and every file
  // indexable.
  final effective = preview == null ? routed : preview.wrap(routed);

  final activeSubscriptions = <int, StreamSubscription<List<int>>>{};
  final authority = host.contains(':') && !host.startsWith('[') ? '[$host]' : host;
  // The port a request's URL names. The bound one once the server is up, which
  // is before any request can arrive; `port` may be 0.
  var urlPort = port;

  void handleRequest(
      int reqId,
      gen.FfiStr method,
      gen.FfiStr target,
      ffi.Pointer<ffi.Uint8> hdrsPtr,
      int hdrsLen,
      gen.FfiBuf body,
      gen.FfiStr peer) {
    // Nothing thrown here may leave this function. It runs in the native
    // callback, outside every handler's try: a request whose URL did not
    // parse was never answered, and the exception, unhandled in the root
    // zone, ended the process -- one `GET http://x:1/ HTTP/1.1` stopped the
    // server. So building the request is guarded as a whole, and every way
    // out answers.
    final Request req;
    try {
      req = _readRequest(
        method: method,
        target: target,
        hdrsPtr: hdrsPtr,
        hdrsLen: hdrsLen,
        body: body,
        peer: peer,
        authority: authority,
        port: urlPort,
      );
    } on _MalformedRequest catch (refusal) {
      _logRefused(400, 'refused before any route saw it: ${refusal.reason}');
      _answerError(api, reqId, 400);
      return;
    } catch (error, stack) {
      _logRefused(500,
          'could not be read (${error.runtimeType}), a failure in serve()',
          stack);
      _answerError(api, reqId, 500);
      return;
    }

    Future<void>(() async {
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

          final int accepted = api.aw_complete(reqId, out.ref);
          pkgffi.calloc.free(bodyBuf);
          pkgffi.calloc.free(out);
          pkgffi.malloc.free(hdrsNative);
          // The native side gave up on this request -- it timed out, or the
          // server stopped -- so nothing would read the stream. Not listened
          // to, rather than produced into a channel that is gone.
          if (accepted != 0) return;

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
          pkgffi.malloc.free(bodyNative);
          pkgffi.malloc.free(hdrsNative);
        }
      } catch (error, stack) {
        // By type alone: an error's message is free to quote the request
        // that caused it. A Router catches its routes' errors and logs them
        // itself; this is a handler serve() was given directly, or a failure
        // turning a response into bytes.
        _logRefused(500, 'failed (${error.runtimeType})', stack);
        // Already answered is harmless: the native side answers a request
        // once and refuses the second.
        _answerError(api, reqId, 500);
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
  if (boundPort != 0) urlPort = boundPort;

  return ServerHandle(host, boundPort == 0 ? port : boundPort, serverId, api,
      dartRequestHandler, dartCancelHandler);
}

/// A request that cannot be served as written, and why, in words chosen here:
/// nothing of the request is in [reason].
final class _MalformedRequest implements Exception {
  const _MalformedRequest(this.reason);
  final String reason;
}

/// The request the native side passed, copied out of native memory.
///
/// Throws [_MalformedRequest] for a request target no route could be given.
Request _readRequest({
  required gen.FfiStr method,
  required gen.FfiStr target,
  required ffi.Pointer<ffi.Uint8> hdrsPtr,
  required int hdrsLen,
  required gen.FfiBuf body,
  required gen.FfiStr peer,
  required String authority,
  required int port,
}) {
  // The accepted socket's address, from the native side and never from a
  // header. Empty, or anything that does not parse, is no peer at all
  // rather than a guess.
  final DVPeerAddress? peerAddress = peer.len == 0
      ? null
      : DVPeerAddress.tryParse(String.fromCharCodes(
          peer.ptr.cast<ffi.Uint8>().asTypedList(peer.len)));
  final methodStr = String.fromCharCodes(
      method.ptr.cast<ffi.Uint8>().asTypedList(method.len));
  final targetStr = String.fromCharCodes(
      target.ptr.cast<ffi.Uint8>().asTypedList(target.len));
  final headers = decodeHeaders(hdrsPtr.cast<ffi.Uint8>().asTypedList(hdrsLen));
  final bodyBytes =
      Uint8List.fromList(body.ptr.cast<ffi.Uint8>().asTypedList(body.len));
  return Request(
    method: methodStr,
    url: _requestUrl(targetStr, authority: authority, port: port),
    headers: Headers(headers),
    bodyStream: Stream<List<int>>.value(bodyBytes),
    peerAddress: peerAddress,
  );
}

/// The URL of a request whose request line named [target], on this server.
///
/// Origin form (`/path?query`) is the usual target. Absolute form
/// (`http://host:port/path`) is one a server must accept, and is what a
/// request over HTTP/2 carries; only its path and query are used, since the
/// authority it names is the client's claim and this server answers for
/// [authority]. Pasted after the authority whole, as it was, it made a URL
/// with two ports, which Uri.parse refused inside the native callback.
///
/// Refused: the asterisk form and anything else that is not a path; a percent
/// sign not followed by two hex digits; and a path or query whose escapes do
/// not decode as UTF-8, which Dart's Uri cannot decode and every route that
/// read `pathSegments` or `queryParameters` would have answered with 500.
Uri _requestUrl(String target,
    {required String authority, required int port}) {
  String pathAndQuery;
  if (target.startsWith('/')) {
    pathAndQuery = target;
  } else {
    final String lower = target.toLowerCase();
    final int schemeEnd = lower.startsWith('http://')
        ? 7
        : lower.startsWith('https://')
            ? 8
            : -1;
    if (schemeEnd < 0) {
      throw const _MalformedRequest(
          'the request target is neither a path nor an absolute http URL');
    }
    int rest = target.length;
    for (int i = schemeEnd; i < target.length; i++) {
      final String c = target[i];
      if (c == '/' || c == '?' || c == '#') {
        rest = i;
        break;
      }
    }
    final String tail = target.substring(rest);
    pathAndQuery = tail.startsWith('/') ? tail : '/$tail';
  }
  final int fragment = pathAndQuery.indexOf('#');
  if (fragment >= 0) pathAndQuery = pathAndQuery.substring(0, fragment);
  for (int i = 0; i < pathAndQuery.length; i++) {
    if (pathAndQuery.codeUnitAt(i) != 0x25) continue;
    if (i + 2 >= pathAndQuery.length ||
        !_isHex(pathAndQuery.codeUnitAt(i + 1)) ||
        !_isHex(pathAndQuery.codeUnitAt(i + 2))) {
      throw const _MalformedRequest(
          'the request target has a percent sign that is not an escape');
    }
  }
  final Uri? url = Uri.tryParse('http://$authority:$port$pathAndQuery');
  if (url == null) {
    throw const _MalformedRequest('the request target is not a URL path');
  }
  try {
    // Decoded now, once -- Uri keeps the result -- so a target that cannot
    // be decoded is the client's 400 here rather than a route's 500 later.
    url.pathSegments;
    url.queryParametersAll;
  } on FormatException {
    throw const _MalformedRequest(
        'the request target does not percent-decode as UTF-8');
  } on ArgumentError {
    throw const _MalformedRequest(
        'the request target does not percent-decode as UTF-8');
  }
  return url;
}

bool _isHex(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x46) ||
    (unit >= 0x61 && unit <= 0x66);

/// A request serve() answered with an error itself, logged by [what] alone:
/// never the method, target, headers or body, and never an error's message,
/// which is free to quote them.
void _logRefused(int status, String what, [StackTrace? stack]) {
  try {
    DVObservability.log(
      'dartvel: a request $what; answered $status',
      level: status >= 500 ? DVLogLevel.error : DVLogLevel.warn,
      context: <String, Object?>{'status': status},
      stackTrace: stack,
    );
  } catch (_) {
    // A logger that throws must not cost the request its answer.
  }
}

/// Answers [reqId] with [status] and fixed text. Never throws.
void _answerError(gen.DartvelShelfBindings api, int reqId, int status) {
  try {
    final List<int> text = utf8.encode(
        status == 400 ? 'Bad Request\n' : 'Internal Server Error\n');
    final Uint8List hdrs = encodeHeaders(<String, List<String>>{
      'content-type': <String>['text/plain; charset=utf-8'],
    });
    final hdrsNative = pkgffi.malloc<ffi.Uint8>(hdrs.length)
      ..asTypedList(hdrs.length).setAll(0, hdrs);
    final bodyNative = pkgffi.malloc<ffi.Uint8>(text.length)
      ..asTypedList(text.length).setAll(0, text);
    final out = pkgffi.calloc<gen.FfiResp>();
    out.ref
      ..status = status
      ..is_stream = 0
      ..hdrs = hdrsNative.cast()
      ..hdrs_len = hdrs.length;
    out.ref.body.ptr = bodyNative.cast();
    out.ref.body.len = text.length;
    api.aw_complete(reqId, out.ref);
    pkgffi.calloc.free(out);
    pkgffi.malloc.free(bodyNative);
    pkgffi.malloc.free(hdrsNative);
  } catch (_) {
    // Out of native memory. The native side's timeout answers instead.
  }
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
