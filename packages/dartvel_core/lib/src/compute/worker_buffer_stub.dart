/// The web's answer to a native buffer: there is none.
///
/// A web worker is handed a copy by structured clone, or a transferable
/// buffer it then owns outright; neither is memory two threads address in
/// place. The names exist so code that mentions them compiles everywhere,
/// and `DVWorkers.capability.zeroCopyNative` is false so nothing has to find
/// out by calling one.
library dartvel.compute.worker_buffer_stub;

import 'dart:typed_data';

import 'worker_types.dart';

final class DVWorkerLease {
  const DVWorkerLease._(this.address, this.length);

  final int address;
  final int length;

  Uint8List get bytes => throw UnsupportedError(_why);
}

final class DVWorkerBuffer implements DVWorkerLendable {
  factory DVWorkerBuffer.allocate(int length) => throw UnsupportedError(_why);

  int get length => throw UnsupportedError(_why);
  bool get isLent => false;
  bool get isFreed => true;
  Uint8List get bytes => throw UnsupportedError(_why);
  DVWorkerLease get lease => throw UnsupportedError(_why);
  void free() {}

  @override
  void lend() => throw UnsupportedError(_why);

  @override
  void giveBack() {}
}

const String _why = 'There is no native memory to lend on this target; a web '
    'worker is handed a copy or a transferred buffer instead.';
