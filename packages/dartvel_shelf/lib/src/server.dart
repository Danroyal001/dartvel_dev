import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:dartvel_core/dv.dart';
import 'package:dartvel_core/dartvel.dart'
    show
        DVCacheAdapter,
        DVLogLevel,
        DVPageDataResolver,
        DVPreviewMembership,
        DVPreviewServer,
        dvConfigureRuntimeLogging,
        dvDefaultMaxBodyBytes;
import 'package:path/path.dart' as p;

import 'generated/bindings.dart' as gen; // produced by ffigen via build hook
import 'package:dartvel_core/http.dart';

import 'ffi_string.dart';
import 'native_library.dart';
export 'native_library.dart' show embedNativeServerLibrary;
import 'header_codec.dart';
import 'image_endpoint.dart';
import 'request_body.dart';
import 'web_socket.dart';
import 'ssr_helper.dart';
import 'package:ffi/ffi.dart' as pkgffi;

typedef _NativeCb = gen.DartReqHandlerFunction;
typedef _NativeBodyChunkCb = gen.DartBodyChunkHandlerFunction;

/// The callback shape this file is written for; see `AW_ABI_VERSION` in
/// rust/src/lib.rs. 2 added the peer address.
const int _nativeAbiVersion = 2;

/// The native side's own default, so a library that cannot be configured is
/// refused only when a caller asked for something else.
const Duration _defaultRequestTimeout = Duration(seconds: 60);
typedef _NativeCancelCb = gen.DartStreamCancelHandlerFunction;
typedef _NativeAckCb = gen.DartStreamAckHandlerFunction;
typedef _NativeWakeupCb = gen.DartWsWakeupHandlerFunction;

class _StreamResponseState {
  _StreamResponseState(this.subscription);
  final StreamSubscription<List<int>> subscription;
  int inFlight = 0;
  static const int scratchSize = 256 * 1024;
  final ffi.Pointer<ffi.Uint8> scratchPtr =
      pkgffi.malloc<ffi.Uint8>(scratchSize);
  final ffi.Pointer<gen.FfiBuf> scratchBuf = pkgffi.calloc<gen.FfiBuf>();

  void dispose() {
    pkgffi.malloc.free(scratchPtr);
    pkgffi.calloc.free(scratchBuf);
  }
}

class ServerHandle {
  final String host;
  final int port;
  final int _id;
  final gen.DartvelShelfBindings _api;
  final ffi.NativeCallable<_NativeCb> _dartHandler;
  final ffi.NativeCallable<_NativeCancelCb> _dartCancelHandler;
  // Null for a library that reads every body whole, which is a Dart this side
  // has no way to stream a body into.
  final ffi.NativeCallable<_NativeBodyChunkCb>? _dartBodyChunkHandler;
  final ffi.NativeCallable<_NativeAckCb>? _dartStreamAckHandler;
  final ffi.NativeCallable<_NativeWakeupCb>? _dartWsWakeupHandler;
  bool _stopped = false;
  final Set<NativeWebSocketChannel> _webSockets;

  ServerHandle(
    this.host,
    this.port,
    this._id,
    this._api,
    this._dartHandler,
    this._dartCancelHandler, [
    this._dartBodyChunkHandler,
    this._dartStreamAckHandler,
    this._webSockets = const {},
    this._dartWsWakeupHandler,
  ]);

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    for (final channel in _webSockets.toList()) { channel.dispose(); }
    _api.aw_stop(_id);
    _dartHandler.close();
    _dartCancelHandler.close();
    _dartBodyChunkHandler?.close();
    _dartStreamAckHandler?.close();
    _dartWsWakeupHandler?.close();
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
  // The routes Studio has published, which no manifest lists: without them a
  // published page would be answered with a 404.
  Future<Set<String>> Function()? publishedRoutes,
  DVPageDataResolver? pageData, // The route's data on request, for the page pipeline
  DVCacheAdapter? pageStore, // Where the kept pages live, when they are shared
  bool compression = true, // Enable/disable compression
  DVPreviewMembership? previewMembership, // Who may open a members-only preview
  // How long a request may take to arrive and be answered: its headers, its
  // body, and the handler. Past it the native side answers 408 or 504 and
  // closes the connection, or closes one whose headers never finished.
  Duration requestTimeout = _defaultRequestTimeout,
  // The largest request body the native side reads, for a request no route
  // limit covers. A body declared larger is answered 413 without being read;
  // one that grows past it is answered 413 as it does; both close the
  // connection.
  int maxBodyBytes = dvDefaultMaxBodyBytes,
  // Every route, in dispatch order, with the limit it declared: a Router's
  // bodyLimits. A route's own limit replaces maxBodyBytes for the requests it
  // takes, so an upload route reads more without every route doing so.
  Iterable<DVRouteBodyLimit> routeBodyLimits = const <DVRouteBodyLimit>[],
}) async {
  if (requestTimeout <= Duration.zero) {
    throw ArgumentError.value(requestTimeout, 'requestTimeout',
        'must be positive: a request allowed no time is never answered');
  }
  if (maxBodyBytes <= 0) {
    throw ArgumentError.value(maxBodyBytes, 'maxBodyBytes',
        'must be positive: a server that reads no body is not a limit');
  }
  final List<DVRouteBodyLimit> routeLimits =
      List<DVRouteBodyLimit>.of(routeBodyLimits);
  for (final DVRouteBodyLimit route in routeLimits) {
    final int? bytes = route.maxBytes;
    if (bytes != null && bytes <= 0) {
      throw ArgumentError.value(bytes, 'routeBodyLimits',
          'a route limit must be positive (${route.method} ${route.pattern})');
    }
  }

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

  // Embedded in a compiled binary, or the package's own file under dart run.
  final native = await openNativeServerLibrary();
  final dylib = native.library;

  final api = gen.DartvelShelfBindings(dylib);

  // Before anything is registered. A library built for an older callback
  // shape calls the request handler with fewer arguments than it declares,
  // and the missing one is read from whatever the register holds: not an
  // error, a garbage pointer. Refused here, by name, instead.
  final int abi =
      dylib.providesSymbol('aw_abi_version') ? api.aw_abi_version() : 1;
  if (abi != _nativeAbiVersion) {
    throw StateError(
      'dartvel: the native server library at ${native.origin} speaks ABI '
      '$abi and this package speaks $_nativeAbiVersion. Rebuild it: '
      'cargo build --release --target <triple> in dartvel_shelf/rust, then '
      'copy the result over that file.',
    );
  }
  // Added after ABI 2 without changing the callback's shape, so looked up
  // rather than assumed. A library without the timeout still has its fixed
  // one, which is refused only when a caller asked for another; one that
  // does not take acknowledgements frees a request's bytes itself.
  final bool configuresTimeout =
      dylib.providesSymbol('aw_configure_request_timeout');
  final bool acknowledgesRequests = dylib.providesSymbol('aw_request_received');
  // A request body is read a chunk at a time rather than whole when both
  // halves can do it. Detected rather than assumed, and by name rather than by
  // ABI, because the pairing is what makes this safe either way: a library
  // without the symbols reads every body whole, as it always did, and this
  // side reads those bytes as it always did.
  final bool streamsRequestBodies =
      dylib.providesSymbol('aw_register_body_chunk_handler') &&
          dylib.providesSymbol('aw_body_next_chunk');
  if (!configuresTimeout && requestTimeout != _defaultRequestTimeout) {
    throw StateError(
      'dartvel: the native server library at ${native.origin} cannot '
      'configure a request timeout. Rebuild it: cargo build --release '
      '--target <triple> in dartvel_shelf/rust, then copy the result over '
      'that file.',
    );
  }
  // Refused whatever the caller asked for, unlike the timeout above. A
  // library without these reads every body whole with no limit at all, so it
  // cannot give even the default: serving from it would leave one client
  // able to fill this process's memory, with nothing saying so.
  if (!dylib.providesSymbol('aw_configure_max_body_bytes') ||
      !dylib.providesSymbol('aw_configure_route_body_limit')) {
    throw StateError(
      'dartvel: the native server library at ${native.origin} cannot '
      'limit a request body, so it would read any size a client sends. '
      'Rebuild it: cargo build --release --target <triple> in '
      'dartvel_shelf/rust, then copy the result over that file.',
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
        return handleSsrFallback(req, spaRoot, pageData: pageData, pageStore: pageStore, publishedRoutes: publishedRoutes);
      }
      // HEAD is GET without the body. Answering it 404 told an uptime
      // monitor, a link checker and a crawler that asks HEAD first that a
      // page served to every browser was not there.
      if (resp.status == 404 && req.method == 'HEAD') {
        final page = await handleSsrFallback(req, spaRoot,
            pageData: pageData, pageStore: pageStore, publishedRoutes: publishedRoutes);
        return Response(page.status,
            headers: page.headers, body: const Stream<List<int>>.empty());
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
  final activeStreamStates = <int, _StreamResponseState>{};
  // The body of each request being read, keyed by the request its chunks will
  // be delivered for. Dropped when the request is answered, so a chunk that
  // arrives after its handler is done goes nowhere rather than into a map
  // nothing reads again.
  final bodies = <int, RequestBodyStream>{};
  final authority = host.contains(':') && !host.startsWith('[') ? '[$host]' : host;
  // The port a request's URL names. The bound one once the server is up, which
  // is before any request can arrive; `port` may be 0.
  var urlPort = port;

  final webSockets = <NativeWebSocketChannel>{};
  final activeWebSockets = <int, NativeWebSocketChannel>{};

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
    // A body this side can pull, or null for a request whose body the native
    // side read whole -- a library that cannot stream one.
    final RequestBodyStream? bodyStream =
        streamsRequestBodies ? RequestBodyStream(reqId, api) : null;
    try {
      req = _readRequest(
        method: method,
        target: target,
        hdrsPtr: hdrsPtr,
        hdrsLen: hdrsLen,
        body: body,
        bodyStream: bodyStream,
        peer: peer,
        authority: authority,
        port: urlPort,
      );
      // Only once the request exists, so a chunk that arrives before this has
      // nowhere to go and the body is read as soon as the handler pulls.
      if (bodyStream != null) bodies[reqId] = bodyStream;
      // Copied out, so the native side may free what it passed. Until this
      // it keeps them, because a listener runs when the isolate gets to it,
      // which can be after the native side has stopped waiting.
      if (acknowledgesRequests) api.aw_request_received(reqId);
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
        if (resp is WebSocketResponse) {
          if (!dylib.providesSymbol('aw_ws_prepare')) {
            throw StateError('Rebuild the native library for WebSocket support');
          }
          final protocolBytes = utf8.encode(resp.protocol ?? '');
          final ptr = pkgffi.malloc<ffi.Uint8>(protocolBytes.isEmpty ? 1 : protocolBytes.length);
          ptr.asTypedList(protocolBytes.length).setAll(0, protocolBytes);
          final protocol = pkgffi.calloc<gen.FfiStr>();
          protocol.ref..ptr = ptr..len = protocolBytes.length;
          final prepared = api.aw_ws_prepare(reqId, resp.max, protocol.ref);
          pkgffi.malloc.free(ptr); pkgffi.calloc.free(protocol);
          if (prepared != 0) throw StateError('WebSocket preparation refused');
          final out = pkgffi.calloc<gen.FfiResp>();
          out.ref.status = 101;
          final accepted = api.aw_complete(reqId, out.ref);
          pkgffi.calloc.free(out);
          if (accepted != 0) { api.aw_ws_dispose(reqId); return; }
          final channel = NativeWebSocketChannel(reqId, api, resp.protocol, resp.max, resp.pingInterval);
          webSockets.add(channel);
          activeWebSockets[reqId] = channel;
          channel.sink.done.whenComplete(() {
            webSockets.remove(channel);
            activeWebSockets.remove(reqId);
          });
          channel.start(resp.pingInterval);
          try { resp.callback(channel, resp.protocol); }
          catch (_) { channel.dispose(); }
          return;
        }
        // A body the handler marked as a stream is sent as one. So is any body
        // that turns out not to be small: the client gets each piece as the
        // handler produces it rather than waiting for the last one, which is
        // the whole difference for a report that builds itself, a generated
        // file, or a page assembled from a generator. Only a body that is
        // already whole goes as one copy -- reading a small one costs what
        // producing it costs, and the client gets a length rather than framing
        // it has to reassemble.
        final bool marked = resp.isStream ||
            resp.headers.get('content-type')?.contains('text/event-stream') ==
                true;
        Uint8List buffered = Uint8List(0);
        Stream<List<int>>? source;
        if (resp.body != null && !marked) {
          final int? declared =
              int.tryParse(resp.headers.get('content-length') ?? '');
          // A declared length is the handler's own answer for how big this is,
          // so it is the bound to keep to. Failing that, a body no larger than
          // [_bufferedResponseBytes] is read whole and one past that is sent
          // as a stream from the piece that crossed the line.
          final int cap = declared != null &&
                  declared >= 0 &&
                  declared < _bufferedResponseBytes
              ? declared
              : _bufferedResponseBytes;
          final StreamIterator<List<int>> parts =
              StreamIterator<List<int>>(resp.body!.stream);
          final BytesBuilder prefix = BytesBuilder(copy: false);
          bool whole = false;
          // A piece still being produced when this turn of the event loop is
          // over. A body is only "small" if it is already in hand: waiting
          // for a slow one to reach the cap would hold its first bytes back.
          Future<bool>? pending;
          while (true) {
            final Future<bool> next = parts.moveNext();
            final int ready = await Future.any(<Future<int>>[
              next.then<int>((bool more) => more ? 1 : 0,
                  onError: (Object _) => 2),
              Future<int>(() => -1),
            ]);
            if (ready == -1) {
              pending = next;
              break;
            }
            if (ready == 2) await next; // rethrows the body's own error
            if (ready == 0) {
              whole = true;
              break;
            }
            prefix.add(parts.current);
            if (prefix.length > cap) break;
          }
          buffered = whole ? prefix.takeBytes() : buffered;
          // Not whole: the part already read goes first, and the rest is
          // taken from the same iterator as it is produced.
          if (!whole) source = _restOfBody(prefix.takeBytes(), parts, pending);
        }

        final hdrsFlat = encodeHeaders(resp.headers.multiValueMap);
        final hdrsNative = pkgffi.malloc<ffi.Uint8>(hdrsFlat.length)
          ..asTypedList(hdrsFlat.length).setAll(0, hdrsFlat);

        final out = pkgffi.calloc<gen.FfiResp>();
        out.ref.status = resp.status;
        out.ref.hdrs = hdrsNative.cast();
        out.ref.hdrs_len = hdrsFlat.length;

        if ((marked || source != null) && resp.body != null) {
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
          late _StreamResponseState streamState;
          const maxInFlight = 32;
          subscription = (source ?? resp.body!.stream).listen(
            (chunk) {
              final int status;
              if (chunk.length <= _StreamResponseState.scratchSize) {
                if (chunk.isNotEmpty) {
                  streamState.scratchPtr
                      .asTypedList(chunk.length)
                      .setAll(0, chunk);
                }
                streamState.scratchBuf.ref
                  ..ptr = streamState.scratchPtr
                  ..len = chunk.length;
                status =
                    api.aw_stream_send_chunk(reqId, streamState.scratchBuf.ref);
              } else {
                final chunkNative = pkgffi.malloc<ffi.Uint8>(chunk.length)
                  ..asTypedList(chunk.length).setAll(0, chunk);
                final chunkBuf = pkgffi.calloc<gen.FfiBuf>();
                chunkBuf.ref.ptr = chunkNative.cast();
                chunkBuf.ref.len = chunk.length;

                status = api.aw_stream_send_chunk(reqId, chunkBuf.ref);

                pkgffi.calloc.free(chunkBuf);
                pkgffi.malloc.free(chunkNative);
              }

              if (status == 2) {
                activeSubscriptions.remove(reqId);
                activeStreamStates.remove(reqId)?.dispose();
                subscription.cancel();
                return;
              }

              streamState.inFlight++;
              if (streamState.inFlight >= maxInFlight || status == 1) {
                subscription.pause();
              }
            },
            onDone: () {
              activeSubscriptions.remove(reqId);
              activeStreamStates.remove(reqId)?.dispose();
              api.aw_stream_complete(reqId);
            },
            onError: (Object e) {
              activeSubscriptions.remove(reqId);
              activeStreamStates.remove(reqId)?.dispose();
              api.aw_stream_complete(reqId);
            },
            cancelOnError: true,
          );
          streamState = _StreamResponseState(subscription);
          activeSubscriptions[reqId] = subscription;
          activeStreamStates[reqId] = streamState;

        } else {
          out.ref.is_stream = 0;
          final bodyNative = pkgffi.malloc<ffi.Uint8>(buffered.length)
            ..asTypedList(buffered.length).setAll(0, buffered);

          final bodyBuf = pkgffi.calloc<gen.FfiBuf>();
          bodyBuf.ref.ptr = bodyNative.cast();
          bodyBuf.ref.len = buffered.length;
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
      } finally {
        // Nobody is left to pull this request's body: its answer is what
        // told the native side so, and a chunk that arrives after it is
        // dropped rather than waiting for a pull nobody will make.
        bodies.remove(reqId);
      }
    });
  }

  final dartRequestHandler =
      ffi.NativeCallable<_NativeCb>.listener(handleRequest);
  api.aw_register_handler(dartRequestHandler.nativeFunction);

  final dartCancelHandler =
      ffi.NativeCallable<_NativeCancelCb>.listener((int reqId) {
    activeStreamStates.remove(reqId)?.dispose();
    final subscription = activeSubscriptions.remove(reqId);
    subscription?.cancel();
  });
  try {
    api.aw_register_cancel_handler(dartCancelHandler.nativeFunction);
  } on ArgumentError {
    // Older bundled binaries may not expose this FFI symbol. Rust source and
    // generated bindings include it; rebuilding the native asset enables it.
  }

  final dartStreamAckHandler =
      ffi.NativeCallable<_NativeAckCb>.listener((int reqId) {
    final state = activeStreamStates[reqId];
    if (state == null) return;
    state.inFlight = (state.inFlight - 8).clamp(0, 999999);
    if (state.inFlight <= 16 && state.subscription.isPaused) {
      state.subscription.resume();
    }
  });
  try {
    api.aw_register_stream_ack_handler(dartStreamAckHandler.nativeFunction);
  } on ArgumentError {
    // Older bundled binaries may not expose this FFI symbol.
  }

  final dartWsWakeupHandler =
      ffi.NativeCallable<_NativeWakeupCb>.listener((int reqId) {
    activeWebSockets[reqId]?.onWakeup();
  });
  try {
    api.aw_register_ws_wakeup_handler(dartWsWakeupHandler.nativeFunction);
  } on ArgumentError {
    // Older bundled binaries may not expose this FFI symbol.
  }

  // On this thread and before aw_start, which takes it into this server's own
  // slot the way it takes the request and cancel handlers: two isolates
  // starting a server at the same moment interleave as register A, register B,
  // start A, start B, and A would otherwise hand its request bodies to B's
  // isolate.
  ffi.NativeCallable<_NativeBodyChunkCb>? dartBodyChunkHandler;
  if (streamsRequestBodies) {
    dartBodyChunkHandler =
        ffi.NativeCallable<_NativeBodyChunkCb>.listener(
            (int reqId, gen.FfiBuf chunk, int kind) {
      bodies[reqId]?.deliver(kind, chunk.ptr, chunk.len);
    });
    api.aw_register_body_chunk_handler(dartBodyChunkHandler.nativeFunction);
  }

  _configureCors(api, cors);
  _configureStatic(api, staticDir);
  _configureSpaRoot(api, null);
  _configureCompression(api, compression);
  if (configuresTimeout) {
    // On this thread and just before aw_start, which takes it from here.
    final int milliseconds = requestTimeout.inMilliseconds;
    api.aw_configure_request_timeout(milliseconds < 1 ? 1 : milliseconds);
  }
  // Likewise on this thread, with nothing awaited before aw_start.
  _configureBodyLimits(api, maxBodyBytes, routeLimits);

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

  return ServerHandle(
    host,
    boundPort == 0 ? port : boundPort,
    serverId,
    api,
    dartRequestHandler,
    dartCancelHandler,
    dartBodyChunkHandler,
    dartStreamAckHandler,
    webSockets,
    dartWsWakeupHandler,
  );
}

/// A response body no larger than this, and already whole when the handler
/// returns it, is sent in one piece.
///
/// Small enough that a body under it is nearly always already in hand -- a
/// page, an API answer, an error -- and reading it costs no more than
/// producing it. Past it, holding a body to find out whether it is small is
/// the thing being avoided.
const int _bufferedResponseBytes = 64 * 1024;

/// The bytes already read from a body that turned out not to be small or not
/// yet whole, then the piece being waited for, then the rest of it as the
/// handler produces it.
///
/// A generator rather than a concatenation, so the part that was read is not
/// held twice and the rest is not run ahead of the client: the native side
/// takes each piece as it is produced.
Stream<List<int>> _restOfBody(List<int> prefix,
    StreamIterator<List<int>> rest, Future<bool>? pending) async* {
  if (prefix.isNotEmpty) yield prefix;
  if (pending != null) {
    if (!await pending) return;
    yield rest.current;
  }
  while (await rest.moveNext()) {
    yield rest.current;
  }
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
  required RequestBodyStream? bodyStream,
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
  // A body the native side streamed is pulled one chunk at a time as the
  // handler reads it; one it read whole arrives here and is already in memory.
  final Stream<List<int>> bodySource = bodyStream == null
      ? Stream<List<int>>.value(
          Uint8List.fromList(body.ptr.cast<ffi.Uint8>().asTypedList(body.len)))
      : _pulled(bodyStream);
  return Request(
    method: methodStr,
    url: _requestUrl(targetStr, authority: authority, port: port),
    headers: Headers(headers),
    bodyStream: bodySource,
    peerAddress: peerAddress,
  );
}

/// The body [source] has, as it arrives.
///
/// A generator, so a chunk is asked for only when the consumer has come back
/// for the next one. That is what makes the handler the thing that decides how
/// fast a client may send.
Stream<List<int>> _pulled(RequestBodyStream source) async* {
  while (true) {
    final Uint8List? chunk = await source.pull();
    if (chunk == null) return;
    yield chunk;
  }
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
    DV.log(
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

/// The server's body limit and every route's, in dispatch order.
///
/// The server's first: it also clears any routes this thread added for a
/// serve() that failed before starting.
void _configureBodyLimits(gen.DartvelShelfBindings api, int maxBodyBytes,
    List<DVRouteBodyLimit> routes) {
  final int rc = api.aw_configure_max_body_bytes(maxBodyBytes);
  if (rc != 0) throw StateError('Body limit config failed (code=$rc)');
  for (final DVRouteBodyLimit route in routes) {
    final List<int> method = dvFfiBytes(route.method);
    final List<int> pattern = dvFfiBytes(route.pattern);
    final methodPtr = pkgffi.malloc<ffi.Uint8>(method.isEmpty ? 1 : method.length)
      ..asTypedList(method.length).setAll(0, method);
    final patternPtr =
        pkgffi.malloc<ffi.Uint8>(pattern.isEmpty ? 1 : pattern.length)
          ..asTypedList(pattern.length).setAll(0, pattern);
    final methodStr = pkgffi.calloc<gen.FfiStr>();
    final patternStr = pkgffi.calloc<gen.FfiStr>();
    methodStr.ref
      ..ptr = methodPtr.cast()
      ..len = method.length;
    patternStr.ref
      ..ptr = patternPtr.cast()
      ..len = pattern.length;
    // Zero is a route with no limit of its own. It is still sent: it may come
    // before a route with one, and then it decides.
    final int routeRc = api.aw_configure_route_body_limit(
        methodStr.ref, patternStr.ref, route.maxBytes ?? 0);
    pkgffi.calloc.free(methodStr);
    pkgffi.calloc.free(patternStr);
    pkgffi.malloc.free(methodPtr);
    pkgffi.malloc.free(patternPtr);
    if (routeRc != 0) {
      throw StateError('Route body limit config failed (code=$routeRc)');
    }
  }
}

String getMimeType(String path) {
  // iOS refuses the Universal Links document as anything but JSON, and its
  // name has no extension to say so.
  if (p.basename(path) == 'apple-app-site-association') {
    return 'application/json';
  }
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
