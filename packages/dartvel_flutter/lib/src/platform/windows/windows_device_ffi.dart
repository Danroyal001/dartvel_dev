/// Device APIs on Windows: how the shared runtime reads its numbers here.
///
/// GlobalMemoryStatusEx for memory, GetTickCount64 for uptime,
/// GetDiskFreeSpaceExW for disk, GetSystemMetrics for the digitizer and the
/// screen. Windows keeps no load average and exposes no temperature without
/// WMI, so neither is claimed; a supervisor is told nothing, because a
/// Windows service has no sd_notify to tell.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../device_runtime.dart';

final class _MemoryStatusEx extends Struct {
  @Uint32()
  external int dwLength;
  @Uint32()
  external int dwMemoryLoad;
  @Uint64()
  external int ullTotalPhys;
  @Uint64()
  external int ullAvailPhys;
  @Uint64()
  external int ullTotalPageFile;
  @Uint64()
  external int ullAvailPageFile;
  @Uint64()
  external int ullTotalVirtual;
  @Uint64()
  external int ullAvailVirtual;
  @Uint64()
  external int ullAvailExtendedVirtual;
}

const int _smCxScreen = 0;
const int _smDigitizer = 94;
const int _nidIntegratedTouch = 0x01;
const int _nidExternalTouch = 0x02;

class DVWindowsDeviceProbes extends DVDeviceProbes {
  const DVWindowsDeviceProbes();

  static DynamicLibrary get _kernel32 => DynamicLibrary.open('kernel32.dll');
  static DynamicLibrary get _user32 => DynamicLibrary.open('user32.dll');

  @override
  Map<String, int> memory() {
    final status = _kernel32.lookupFunction<
        Int32 Function(Pointer<_MemoryStatusEx>),
        int Function(Pointer<_MemoryStatusEx>)>('GlobalMemoryStatusEx');
    final Pointer<_MemoryStatusEx> info = calloc<_MemoryStatusEx>();
    try {
      info.ref.dwLength = sizeOf<_MemoryStatusEx>();
      if (status(info) == 0) return const <String, int>{};
      return <String, int>{'totalBytes': info.ref.ullTotalPhys, 'availableBytes': info.ref.ullAvailPhys};
    } finally {
      calloc.free(info);
    }
  }

  @override
  double uptimeSeconds() =>
      _kernel32.lookupFunction<Uint64 Function(), int Function()>('GetTickCount64')() / 1000;

  @override
  int diskFreeBytes(String path) {
    final free = _kernel32.lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>),
        int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>)>('GetDiskFreeSpaceExW');
    final Pointer<Utf16> name = path.toNativeUtf16();
    final Pointer<Uint64> available = calloc<Uint64>();
    final Pointer<Uint64> total = calloc<Uint64>();
    final Pointer<Uint64> totalFree = calloc<Uint64>();
    try {
      if (free(name, available, total, totalFree) == 0) return 0;
      return available.value;
    } finally {
      calloc.free(name);
      calloc.free(available);
      calloc.free(total);
      calloc.free(totalFree);
    }
  }

  int _metric(int index) =>
      _user32.lookupFunction<Int32 Function(Int32), int Function(int)>('GetSystemMetrics')(index);

  @override
  bool hasTouch() => _metric(_smDigitizer) & (_nidIntegratedTouch | _nidExternalTouch) != 0;

  @override
  bool hasDisplay() => _metric(_smCxScreen) > 0;

  @override
  String displayServer() => 'win32';
}
