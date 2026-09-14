/// Memory outside the Dart heap, lent to a worker by address.
///
/// This is the seam the specification's zero-copy path stands on: an address
/// outside the heap is stable and means the same thing on every isolate in
/// the process, so a worker -- or native code a worker calls -- can read and
/// write it without a byte being copied. Platform Memory's arenas are meant
/// to be such memory; until they exist, a buffer is allocated here.
///
/// It is also the unsafe half, which is why it is shaped as a loan. A buffer
/// is passed, not shared: while a worker holds it the caller cannot read it,
/// free it or lend it again. It comes back with the worker's answer, which is
/// the worker's last act, or -- for a run that was cancelled or timed out --
/// only when the worker's thread has actually ended. A cancelled run is
/// answered at once, but its isolate may still be writing; memory freed
/// under it is a use-after-free that crashes somewhere else, later, in
/// release.
library dartvel.compute.worker_buffer_ffi;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'worker_types.dart';

/// What a worker is handed: an address and a length. Two integers, so it
/// crosses any isolate boundary.
///
/// Valid only inside a run that lends its buffer.
final class DVWorkerLease {
  const DVWorkerLease._(this.address, this.length);

  final int address;
  final int length;

  /// The memory, in place.
  Uint8List get bytes => Pointer<Uint8>.fromAddress(address).asTypedList(length);

  @override
  String toString() =>
      'DVWorkerLease(0x${address.toRadixString(16)}, $length bytes)';
}

/// Zero-filled native memory a caller owns and may lend to a worker.
final class DVWorkerBuffer implements DVWorkerLendable {
  DVWorkerBuffer._(this._pointer, this.length);

  /// Allocates [length] zeroed bytes. Nothing frees them but [free].
  factory DVWorkerBuffer.allocate(int length) {
    if (length < 1) {
      throw ArgumentError.value(length, 'length', 'a buffer holds a byte');
    }
    return DVWorkerBuffer._(calloc<Uint8>(length), length);
  }

  Pointer<Uint8>? _pointer;
  final int length;
  bool _lent = false;

  /// Whether a worker holds it.
  bool get isLent => _lent;

  bool get isFreed => _pointer == null;

  /// The memory, in place. A view taken before lending is not revoked by
  /// lending, which Dart cannot do; do not keep one across a run.
  Uint8List get bytes {
    _usable('read');
    return _pointer!.asTypedList(length);
  }

  /// The address and length to put in a task's input.
  DVWorkerLease get lease {
    if (_pointer == null) throw StateError('This DVWorkerBuffer was freed.');
    return DVWorkerLease._(_pointer!.address, length);
  }

  /// Frees the memory. Freeing twice does nothing; freeing while lent throws.
  void free() {
    if (_pointer == null) return;
    _usable('free');
    calloc.free(_pointer!);
    _pointer = null;
  }

  @override
  void lend() {
    if (_pointer == null) throw StateError('This DVWorkerBuffer was freed.');
    if (_lent) {
      throw StateError('This DVWorkerBuffer is already lent to a worker. A '
          'buffer is passed, not shared: two workers writing one buffer is a '
          'data race.');
    }
    _lent = true;
  }

  @override
  void giveBack() => _lent = false;

  void _usable(String verb) {
    if (_pointer == null) throw StateError('This DVWorkerBuffer was freed.');
    if (_lent) {
      throw StateError('Cannot $verb a DVWorkerBuffer while a worker holds '
          'it; it comes back when the worker has ended.');
    }
  }
}
