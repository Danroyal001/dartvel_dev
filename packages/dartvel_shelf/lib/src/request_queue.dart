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
  RequestQueue._(this._take, this._register, this._drive, this._park);

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
      library.providesSymbol('aw_drive')
          ? library.lookupFunction<ffi.Int32 Function(ffi.Uint64),
              int Function(int)>('aw_drive')
          : null,
      library.providesSymbol('aw_park')
          ? library.lookupFunction<ffi.Int32 Function(ffi.Uint64),
              int Function(int)>('aw_park')
          : null,
    );
  }

  /// Whether this isolate can drive the server's runtime itself: pass
  /// AW_FLAG_DRIVEN to aw_start when it can.
  bool get drives => _drive != null && _park != null;

  static const int _batch = 64;
  static const int _batchesPerTurn = 4;

  final int Function(int, ffi.Pointer<FfiRequest>, int) _take;
  final void Function(ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>>)
      _register;
  final int Function(int)? _drive;
  final int Function(int)? _park;

  /// How long an idle turn waits for the next request before the isolate
  /// parks, in microseconds: what a timer can be late by while it waits.
  /// Turns with nothing to take before the runtime goes to the helper.
  static const int _idleTurnsBeforePark = 8;
  int _idleTurns = 0;
  final ffi.Pointer<FfiRequest> _out = pkgffi.calloc<FfiRequest>(_batch);
  bool _againScheduled = false;
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
    _againScheduled = false;
    final RequestHandler? handler = _handler;
    if (handler == null) return;
    final int Function(int)? drive = _drive;
    final int Function(int)? park = _park;
    if (drive != null && park != null) {
      _drainDriven(handler, drive, park);
      return;
    }
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

  /// The isolate drives the server's runtime (AW_FLAG_DRIVEN): each turn
  /// reads what the sockets have, writes the answers handlers have given,
  /// and takes the requests that produced. While requests keep coming the
  /// isolate comes back for the next turn by a message to itself, so the
  /// answers its handlers give in this turn's microtasks are written by the
  /// next one, on this thread. A turn with nothing to take hands the runtime
  /// to the server's helper thread, which waits for the next request and
  /// wakes this isolate for it.
  void _drainDriven(RequestHandler handler, int Function(int) drive,
      int Function(int) park) {
    var handedOver = false;
    for (var turn = 0; turn < _batchesPerTurn; turn++) {
      drive(_serverId);
      final int taken = _take(_serverId, _out, _batch);
      for (var i = 0; i < taken; i++) {
        final FfiRequest request = (_out + i).ref;
        handler(request.id, request.method, request.target, request.hdrs,
            request.hdrsLen, request.body, request.peer);
      }
      if (taken > 0) handedOver = true;
      if (taken < _batch) break;
    }
    if (handedOver) {
      _idleTurns = 0;
      _scheduleAgain();
      return;
    }
    // Nothing this turn. The next request of a busy server is usually a
    // moment away, so a few more turns come back for it -- each a message to
    // this isolate, so timers, other I/O and a client in this same isolate
    // run in between -- before the runtime goes to the helper, whose
    // hand-back costs a wakeup and a message. Waiting for it in the kernel
    // instead (aw_linger) held the event loop: a client in the same isolate
    // could not send the request being waited for.
    if (_idleTurns < _idleTurnsBeforePark) {
      _idleTurns++;
      _scheduleAgain();
      return;
    }
    _idleTurns = 0;
    park(_serverId);
  }

  void _scheduleAgain() {
    if (_againScheduled) return;
    _againScheduled = true;
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
