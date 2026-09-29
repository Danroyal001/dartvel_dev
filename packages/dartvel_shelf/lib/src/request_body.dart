import 'dart:async';
import 'dart:collection';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'generated/bindings.dart' as gen;

/// `aw_body_next_chunk` recorded the ask, or answered it.
const int bodyPullTaken = gen.AW_BODY_PULL_TAKEN;

/// The body of one request, as it arrives.
///
/// Pull-driven: [pull] asks the native side for the next chunk and waits for
/// the answer, so nothing is read off the socket that the consumer is not
/// asking for, and at most one chunk is held at a time. A `StreamController`
/// would not do: `await for` gives the producer no signal that the consumer
/// has come back for more, so it would run ahead and hold a whole upload in
/// this isolate's memory -- which is what this replaces.
final class RequestBodyStream {
  RequestBodyStream(this.reqId, this._api);

  final int reqId;
  final gen.DartvelShelfBindings _api;

  /// Events already handed over and not yet asked for. At most one, because
  /// the native side sends one per pull; a queue so a second one cannot be
  /// dropped silently.
  final Queue<_BodyEvent> _mailbox = Queue<_BodyEvent>();

  /// Completes when the next event is in [_mailbox], or null when nobody is.
  Completer<void>? _waiting;

  /// Takes an event from the native chunk callback.
  ///
  /// Runs on this isolate's event loop, never while [pull] is on the stack:
  /// the callback is a listener, so the native call that triggers it returns
  /// first and the event is delivered afterwards.
  void deliver(int kind, ffi.Pointer<ffi.Uint8> ptr, int len) {
    _mailbox.add(_BodyEvent(kind, copyOf(ptr, len)));
    final Completer<void>? waiting = _waiting;
    if (waiting != null) {
      _waiting = null;
      waiting.complete();
    }
  }

  /// The next chunk of the body, or null once there is nothing more.
  ///
  /// Fails on a refusal, because the bytes a handler has are not the bytes the
  /// client sent and answering a length for them would be a lie. Ends quietly
  /// on an unreadable body, which is how a request whose body could not be
  /// read has always been answered.
  Future<Uint8List?> pull() async {
    if (_api.aw_body_next_chunk(reqId) != bodyPullTaken) return null;
    if (_mailbox.isEmpty) {
      final Completer<void> waiting = Completer<void>();
      _waiting = waiting;
      await waiting.future;
    }
    final _BodyEvent event = _mailbox.removeFirst();
    switch (event.kind) {
      case gen.AW_BODY_CHUNK:
        return event.bytes;
      case gen.AW_BODY_REFUSED:
        throw StateError(
          'dartvel: the request body was not read whole -- it passed the limit '
          'the server was given, or the request ran out of time with it '
          'unfinished. The request is answered 413 or 408 and the connection '
          'is closed.',
        );
      case gen.AW_BODY_END:
      case gen.AW_BODY_UNREADABLE:
      default:
        return null;
    }
  }
}

/// One event the native side handed over.
final class _BodyEvent {
  _BodyEvent(this.kind, this.bytes);
  final int kind;
  final Uint8List bytes;
}

/// The [len] bytes at [ptr], copied out of native memory.
///
/// A copy rather than a view: the chunk belongs to the native side until the
/// next pull replaces it, and this runs on the isolate's event loop rather than
/// during the call that delivered it.
Uint8List copyOf(ffi.Pointer<ffi.Uint8> ptr, int len) {
  if (len == 0 || ptr.address == 0) return Uint8List(0);
  return Uint8List.fromList(ptr.asTypedList(len));
}
