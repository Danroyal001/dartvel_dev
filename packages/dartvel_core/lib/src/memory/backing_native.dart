import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'backing.dart';

/// Native targets: segments from the native heap, outside the Dart GC, at
/// addresses that do not move.
DVMemoryBacking dvPlatformMemoryBacking() => const _NativeBacking();

final class _NativeBacking implements DVMemoryBacking {
  const _NativeBacking();

  static const int _page = 4096;

  @override
  DVMemorySegmentStore? reserve(int bytes, {required bool touchPages}) {
    final Pointer<Uint8> pointer;
    try {
      pointer = malloc<Uint8>(bytes);
    } on Object {
      return null;
    }
    // Freed by the finalizer when the last view of the segment is collected,
    // not by dispose(). A slice's chunks are typed views and can be held past
    // dispose; freeing under them would turn a stale read into reading
    // whatever the allocator put there next, or a crash.
    final Uint8List view = pointer.asTypedList(
      bytes,
      finalizer: malloc.nativeFree,
    );
    if (touchPages) {
      for (var i = 0; i < bytes; i += _page) {
        view[i] = 0;
      }
    }
    return _NativeSegment(view, pointer.address);
  }
}

final class _NativeSegment implements DVMemorySegmentStore {
  _NativeSegment(this.bytes, this.address);

  @override
  final Uint8List bytes;

  @override
  final int address;
}
