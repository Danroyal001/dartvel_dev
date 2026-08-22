/// Native HTTP/2 transport, backed by the Rust client in
/// `dartvel_shelf/rust/src/http_client.rs`.
///
/// Registered through `dvUseHttpTransport`, so nothing that makes an outbound
/// request has to know it exists. It claims HTTP/2 only: HTTP/1.1 stays with
/// `package:http`, composed through `DVCompositeHttpTransport`, because a
/// native HTTP/2 client is useful the day it works and should not have to
/// reimplement HTTP/1.1 first.
library dartvel_core.http.native_client;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'transport.dart';

// Event codes, mirroring the DV_HTTP_EVENT_* constants in the Rust module.
const int _eventDone = 0;
const int _eventEarlyHints = 1;
const int _eventHead = 2;
const int _eventBody = 3;
const int _eventError = -1;
const int _eventInvalid = -2;

final class _FfiStr extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> ptr;
  @ffi.Size()
  external int len;
}

final class _FfiBuf extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> ptr;
  @ffi.Size()
  external int len;
}

typedef _SendNative = ffi.Uint64 Function(_FfiStr, _FfiBuf);
typedef _SendDart = int Function(_FfiStr, _FfiBuf);
typedef _NextNative = ffi.Int32 Function(ffi.Uint64, ffi.Pointer<_FfiBuf>);
typedef _NextDart = int Function(int, ffi.Pointer<_FfiBuf>);
typedef _FreeNative = ffi.Void Function(_FfiBuf);
typedef _FreeDart = void Function(_FfiBuf);
typedef _CancelNative = ffi.Int32 Function(ffi.Uint64);
typedef _CancelDart = int Function(int);

/// Resolves the packaged native library for this host.
///
/// Same layout the server uses, so a build that produces one produces both.
Future<String> resolveNativeLibraryPath() async {
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
  if (uri == null) {
    throw StateError('Could not resolve the dartvel_shelf native library.');
  }
  return uri.toFilePath();
}

/// The request description handed to the Rust side.
///
/// Separated from the transport so it can be tested without a native library:
/// the wire format is the part most likely to drift, and the part a test can
/// actually pin.
String encodeNativeRequest(DVHttpRequest request, DVHttpProtocol protocol) {
  return jsonEncode(<String, Object?>{
    'url': request.url.toString(),
    'method': request.method,
    'headers': request.headers,
    'alpn': protocol.alpn,
    'timeout_ms': 0,
  });
}

/// What the pump isolate sends back for each native event.
class _PumpEvent {
  final int code;
  final Uint8List? payload;
  const _PumpEvent(this.code, this.payload);
}

/// Arguments for the pump isolate. Everything here must be sendable, which is
/// why the request crosses as JSON and bytes rather than as objects.
class _PumpArgs {
  final SendPort port;
  final String libraryPath;
  final String requestJson;
  final Uint8List body;
  const _PumpArgs(this.port, this.libraryPath, this.requestJson, this.body);
}

/// Runs the whole request on a helper isolate.
///
/// `dv_http_next_event` blocks by design, so pumping it on the main isolate
/// would stall the event loop for the duration of every request. The send is
/// done here too, so the native library is opened exactly once per request in
/// the isolate that uses it.
void _pump(_PumpArgs args) {
  final library = ffi.DynamicLibrary.open(args.libraryPath);
  final send = library.lookupFunction<_SendNative, _SendDart>('dv_http_send');
  final next =
      library.lookupFunction<_NextNative, _NextDart>('dv_http_next_event');
  final free =
      library.lookupFunction<_FreeNative, _FreeDart>('dv_http_free_buf');

  final jsonBytes = utf8.encode(args.requestJson);
  final jsonPtr = calloc<ffi.Uint8>(jsonBytes.length);
  final bodyPtr =
      args.body.isEmpty ? ffi.nullptr : calloc<ffi.Uint8>(args.body.length);
  final eventOut = calloc<_FfiBuf>();

  try {
    jsonPtr.asTypedList(jsonBytes.length).setAll(0, jsonBytes);
    if (args.body.isNotEmpty) {
      bodyPtr.cast<ffi.Uint8>().asTypedList(args.body.length).setAll(
            0,
            args.body,
          );
    }

    final requestStr = calloc<_FfiStr>();
    final bodyBuf = calloc<_FfiBuf>();
    requestStr.ref
      ..ptr = jsonPtr
      ..len = jsonBytes.length;
    bodyBuf.ref
      ..ptr = bodyPtr.cast<ffi.Uint8>()
      ..len = args.body.length;

    final handle = send(requestStr.ref, bodyBuf.ref);
    calloc.free(requestStr);
    calloc.free(bodyBuf);

    // Reported before the blocking loop starts, because once this isolate is
    // inside dv_http_next_event it cannot receive anything. Cancellation
    // therefore has to come from elsewhere, and needs the handle to do it.
    args.port.send(handle);

    if (handle == 0) {
      args.port.send(const _PumpEvent(
        _eventError,
        null,
      ));
      return;
    }

    while (true) {
      final code = next(handle, eventOut);
      if (code == _eventDone || code == _eventInvalid) {
        args.port.send(_PumpEvent(code, null));
        break;
      }
      final buf = eventOut.ref;
      Uint8List? payload;
      if (buf.ptr != ffi.nullptr && buf.len > 0) {
        // Copied before the native buffer is released: the list handed to
        // asTypedList is a view over memory this loop is about to free.
        payload = Uint8List.fromList(buf.ptr.asTypedList(buf.len));
        free(buf);
      }
      args.port.send(_PumpEvent(code, payload));
      if (code == _eventError) break;
    }
  } finally {
    calloc.free(jsonPtr);
    if (bodyPtr != ffi.nullptr) calloc.free(bodyPtr.cast<ffi.Uint8>());
    calloc.free(eventOut);
    args.port.send(null);
  }
}

/// HTTP/2 over the native Rust client, with 103 Early Hints.
class DVRustHttpTransport implements DVHttpTransport {
  final String libraryPath;

  const DVRustHttpTransport(this.libraryPath);

  /// Opens the packaged library, or returns null when it is not present.
  ///
  /// Returning null rather than throwing lets an application register this
  /// opportunistically: a target without the native library keeps working over
  /// `package:http` instead of failing at startup.
  static Future<DVRustHttpTransport?> tryLoad() async {
    try {
      final path = await resolveNativeLibraryPath();
      if (!File(path).existsSync()) return null;
      // Proves the symbols exist before anything depends on them, so a stale
      // library fails here rather than mid-request.
      final library = ffi.DynamicLibrary.open(path);
      library.lookup<ffi.NativeFunction<_SendNative>>('dv_http_send');
      library.lookup<ffi.NativeFunction<_NextNative>>('dv_http_next_event');
      return DVRustHttpTransport(path);
    } catch (_) {
      return null;
    }
  }

  @override
  String get name => 'rust';

  @override
  Set<DVHttpProtocol> get supportedProtocols =>
      const <DVHttpProtocol>{DVHttpProtocol.http2};

  @override
  Future<DVHttpResponse> send(DVHttpRequest request) async {
    final streamed = await stream(request);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.body) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    return DVHttpResponse(
      statusCode: streamed.statusCode,
      body: utf8.decode(bytes, allowMalformed: true),
      bytes: bytes,
      protocol: streamed.protocol,
      earlyHints: streamed.earlyHints,
    );
  }

  @override
  Future<DVHttpStreamedResponse> stream(DVHttpRequest request) async {
    final protocol = request.protocols.protocols.single;
    final receive = ReceivePort();
    final hints = <DVEarlyHints>[];
    final head = Completer<Map<String, Object?>>();
    final body = StreamController<List<int>>();
    Object? failure;
    var cancelled = false;
    int? handle;

    await Isolate.spawn(
      _pump,
      _PumpArgs(
        receive.sendPort,
        libraryPath,
        encodeNativeRequest(request, protocol),
        Uint8List.fromList(request.body),
      ),
    );

    receive.listen((Object? message) {
      if (message is int) {
        handle = message;
        // A stream abandoned before the handle arrived still has to stop.
        if (cancelled) _cancelNative(libraryPath, message);
        return;
      }
      if (message == null) {
        receive.close();
        if (!head.isCompleted) {
          head.completeError(failure ??
              DVHttpNegotiationFailure(
                protocol,
                'the native client produced no response',
              ));
        }
        unawaited(body.close());
        return;
      }
      final event = message as _PumpEvent;
      switch (event.code) {
        case _eventEarlyHints:
          final decoded = _decodeJson(event.payload);
          if (decoded != null) {
            final headers = <String, String>{
              for (final entry in decoded.entries)
                entry.key: '${entry.value}',
            };
            final hint = DVEarlyHints(headers);
            hints.add(hint);
            // Delivered as they arrive, which is the entire point: a hint
            // handed over with the response is not early.
            request.onEarlyHints?.call(hint);
          }
        case _eventHead:
          final decoded = _decodeJson(event.payload);
          if (decoded != null && !head.isCompleted) head.complete(decoded);
        case _eventBody:
          if (event.payload != null) body.add(event.payload!);
        case _eventError:
          failure = _decodeFailure(event.payload, protocol);
          if (!head.isCompleted) head.completeError(failure!);
        case _eventDone:
        case _eventInvalid:
          break;
      }
    });

    // Abandoning the body must stop the request. Without this an unfinished
    // server-sent-events stream would keep a native request, its connection
    // and its tokio task alive for as long as the process runs.
    body.onCancel = () {
      cancelled = true;
      final id = handle;
      if (id != null && id != 0) _cancelNative(libraryPath, id);
    };

    final resolved = await head.future;
    final negotiated = resolved['protocol'];
    final headers = resolved['headers'];
    return DVHttpStreamedResponse(
      statusCode: (resolved['status'] as num?)?.toInt() ?? 0,
      headers: <String, String>{
        if (headers is Map)
          for (final entry in headers.entries) '${entry.key}': '${entry.value}',
      },
      body: body.stream,
      protocol: negotiated is String
          ? (DVHttpProtocol.fromAlpn(negotiated) ?? protocol)
          : protocol,
      earlyHints: List<DVEarlyHints>.unmodifiable(hints),
    );
  }
}

/// Asks the native side to abandon a request.
///
/// Called from the isolate that owns the stream rather than the pump isolate,
/// which is blocked inside `dv_http_next_event` and cannot act on anything.
/// The call itself does not block. Failures are swallowed deliberately:
/// cancelling is best-effort cleanup, and throwing from a stream's onCancel
/// would replace a tidy shutdown with an unhandled error.
void _cancelNative(String libraryPath, int handle) {
  try {
    final library = ffi.DynamicLibrary.open(libraryPath);
    library.lookupFunction<_CancelNative, _CancelDart>('dv_http_cancel')(
      handle,
    );
  } catch (_) {
    // Nothing useful to do: the request is being abandoned either way.
  }
}

Map<String, Object?>? _decodeJson(Uint8List? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(utf8.decode(payload));
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// Turns the Rust failure envelope into the Dart one.
///
/// Preserving `retryable` is what lets the fallback chain distinguish "this
/// peer will not speak HTTP/2" — worth another protocol — from a failure that
/// another protocol would reproduce.
DVHttpNegotiationFailure _decodeFailure(
  Uint8List? payload,
  DVHttpProtocol protocol,
) {
  final decoded = _decodeJson(payload);
  return DVHttpNegotiationFailure(
    protocol,
    decoded?['message'] ?? 'the native client failed without a reason',
    retryable: decoded?['retryable'] as bool? ?? true,
  );
}

/// Installs the native client for HTTP/2, keeping `package:http` for
/// HTTP/1.1, when the native library is available.
///
/// Returns true when it was installed. Safe to call on a target with no native
/// library: it does nothing and reports false.
Future<bool> installNativeHttpTransport() async {
  final native = await DVRustHttpTransport.tryLoad();
  if (native == null) return false;
  dvUseHttpTransport(DVCompositeHttpTransport(<DVHttpTransport>[
    native,
    const DVPackageHttpTransport(),
  ]));
  return true;
}
