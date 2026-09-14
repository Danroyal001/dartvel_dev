/// Where an arena's segments come from.
library;

import 'dart:typed_data';

import 'backing_web.dart' if (dart.library.io) 'backing_native.dart';

/// Reserves segments for an arena.
///
/// Best-effort by contract: [reserve] returns null when the platform will not
/// grant the bytes, and the arena carries on with what it has.
abstract interface class DVMemoryBacking {
  DVMemorySegmentStore? reserve(int bytes, {required bool touchPages});
}

/// One reserved segment.
abstract interface class DVMemorySegmentStore {
  /// The segment's bytes. Typed views over it are what an arena hands out.
  Uint8List get bytes;

  /// The native address of the first byte, or 0 when the segment lives on
  /// the Dart heap (web, or [DVMemoryHeapBacking]) and has none.
  int get address;
}

/// A segment on the Dart heap: an `ArrayBuffer` on web.
final class DVMemoryHeapSegment implements DVMemorySegmentStore {
  DVMemoryHeapSegment(this.bytes);

  @override
  final Uint8List bytes;

  @override
  int get address => 0;
}

/// Segments allocated as typed data on the Dart heap.
///
/// The web backing, and a portable one for tests. `touchPages` is a no-op:
/// typed data is zeroed as it is allocated.
final class DVMemoryHeapBacking implements DVMemoryBacking {
  const DVMemoryHeapBacking();

  @override
  DVMemorySegmentStore? reserve(int bytes, {required bool touchPages}) {
    try {
      return DVMemoryHeapSegment(Uint8List(bytes));
    } on Object {
      // A browser that will not grant an ArrayBuffer this large throws a
      // RangeError; a VM out of heap throws OutOfMemoryError. Both are the
      // platform granting less than was asked.
      return null;
    }
  }
}

/// The backing this platform uses when an arena is not given one: the
/// native heap through FFI where there is one, typed data on the heap
/// otherwise.
DVMemoryBacking dvDefaultMemoryBacking() => dvPlatformMemoryBacking();
