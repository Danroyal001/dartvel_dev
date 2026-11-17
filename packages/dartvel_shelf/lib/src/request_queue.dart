import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart' as pkgffi;

import 'generated/bindings.dart' as gen;

/// One request as `aw_take_requests` hands it over (`FfiRequest` in
/// rust/src/lib.rs).
final class FfiRequest extends ffi.Struct {
  @ffi.Uint64()
  external int id;
  external gen.FfiStr method;
  external gen.FfiStr target;
  external ffi.Pointer<ffi.Uint8> hdrs;
  @ffi.Size()
  external int hdrsLen;
  external gen.FfiBuf body;
  external gen.FfiStr peer;
}

typedef RequestHandler = void Function(
  int id,
  gen.FfiStr method,
  gen.FfiStr target,
  ffi.Pointer<ffi.Uint8> hdrs,
  int hdrsLen,
  gen.FfiBuf body,
  gen.FfiStr peer,
);

/// Takes a server's requests in batches, on one wakeup, instead of one
/// listener message per request.
///
/// The native side queues each request and wakes the isolate only when the
/// queue was empty; one wakeup then takes every request that arrived in the
/// meantime. Under load that is many, so the isolate stops paying a message
/// per request. A turn takes at most [_batchesPerTurn] batches and then
/// gives the event loop back, so timers, body chunks and WebSocket frames are
/// not starved by a steady stream of requests.
final class RequestQueue {
  RequestQueue._(this._take, this._register);

  /// The queue for a library that has one, or null for one that calls the
  /// request handler with each request.
  static RequestQueue? of(ffi.DynamicLibrary library) {
    if (!library.providesSymbol('aw_take_requests') ||
        !library.providesSymbol('aw_register_request_wakeup_handler')) {
      return null;
    }
    return RequestQueue._(
      library.lookupFunction<
          ffi.Size Function(ffi.Uint64, ffi.Pointer<FfiRequest>, ffi.Size),
          int Function(int, ffi.Pointer<FfiRequest>, int)>(
        'aw_take_requests',
        isLeaf: true,
      ),
      library.lookupFunction<
          ffi.Void Function(
              ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>>),
          void Function(ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>>)>(
        'aw_register_request_wakeup_handler',
      ),
    );
  }

  static const int _batch = 64;
  static const int _batchesPerTurn = 4;

  final int Function(int, ffi.Pointer<FfiRequest>, int) _take;
  final void Function(ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>>)
      _register;
  final ffi.Pointer<FfiRequest> _out = pkgffi.calloc<FfiRequest>(_batch);
  ffi.NativeCallable<ffi.Void Function()>? _wakeup;
  RawReceivePort? _again;
  int _serverId = 0;
  RequestHandler? _handler;

  /// Registers this queue for the server this thread starts next. Call before
  /// `aw_start`, then [attach] with the id it returned.
  void register(RequestHandler handler) {
    _handler = handler;
    final wakeup = ffi.NativeCallable<ffi.Void Function()>.listener(_drain);
    _wakeup = wakeup;
    _again = RawReceivePort((Object? _) => _drain(), 'dartvel requests');
    _register(wakeup.nativeFunction);
  }

  /// The server whose requests this queue takes. Set before the event loop
  /// runs again, so before any wakeup can be handled.
  void attach(int serverId) => _serverId = serverId;

  void _drain() {
    final RequestHandler? handler = _handler;
    if (handler == null) return;
    for (var turn = 0; turn < _batchesPerTurn; turn++) {
      final int taken = _take(_serverId, _out, _batch);
      for (var i = 0; i < taken; i++) {
        final FfiRequest request = (_out + i).ref;
        handler(request.id, request.method, request.target, request.hdrs,
            request.hdrsLen, request.body, request.peer);
      }
      // Fewer than asked for: the queue is empty and the native side wakes
      // this isolate for the next one.
      if (taken < _batch) return;
    }
    // Still full: the native side will not wake again until it is emptied,
    // so this isolate comes back for the rest after the event loop's turn.
    _again?.sendPort.send(null);
  }

  /// Once the server has stopped and nothing will wake this queue again.
  void close() {
    _handler = null;
    _wakeup?.close();
    _again?.close();
    pkgffi.calloc.free(_out);
  }
}
