/// Device APIs on macOS: how the shared runtime reads its numbers here.
///
/// sysctl for the memory size and the boot time, Mach's host_statistics64
/// for the pages that are free, getloadavg for the load, `df` for the disk
/// the way the Linux probes do, CoreGraphics for whether there is a display.
/// No temperature without a private framework, and no touchscreen on a Mac.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../device_runtime.dart';

const int _hostVmInfo64 = 4;

/// sizeof(vm_statistics64) / sizeof(integer_t).
const int _hostVmInfo64Count = 38;

class DVMacosDeviceProbes extends DVDeviceProbes {
  const DVMacosDeviceProbes();

  static DynamicLibrary get _libc => DynamicLibrary.process();

  static int? _sysctlInt(String name) {
    final sysctl = _libc.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Void>, Pointer<IntPtr>, Pointer<Void>, IntPtr),
        int Function(Pointer<Utf8>, Pointer<Void>, Pointer<IntPtr>, Pointer<Void>, int)>('sysctlbyname');
    final Pointer<Utf8> key = name.toNativeUtf8();
    final Pointer<Int64> value = calloc<Int64>();
    final Pointer<IntPtr> size = calloc<IntPtr>()..value = 8;
    try {
      if (sysctl(key, value.cast(), size, nullptr, 0) != 0) return null;
      return size.value == 4 ? value.cast<Int32>().value : value.value;
    } finally {
      calloc.free(key);
      calloc.free(value);
      calloc.free(size);
    }
  }

  @override
  Map<String, int> memory() {
    final int total = _sysctlInt('hw.memsize') ?? 0;
    final int page = _sysctlInt('hw.pagesize') ?? 4096;
    final hostSelf = _libc.lookupFunction<Uint32 Function(), int Function()>('mach_host_self');
    final statistics = _libc.lookupFunction<
        Int32 Function(Uint32, Int32, Pointer<Int32>, Pointer<Uint32>),
        int Function(int, int, Pointer<Int32>, Pointer<Uint32>)>('host_statistics64');
    final Pointer<Int32> info = calloc<Int32>(_hostVmInfo64Count);
    final Pointer<Uint32> count = calloc<Uint32>()..value = _hostVmInfo64Count;
    try {
      var available = 0;
      if (statistics(hostSelf(), _hostVmInfo64, info, count) == 0) {
        // free_count, active_count, inactive_count, wire_count, ... as
        // vm_statistics64 lays them out: what is free and what is inactive
        // is what a new allocation can have.
        available = (info[0] + info[2]) * page;
      }
      return <String, int>{'totalBytes': total, 'availableBytes': available};
    } finally {
      calloc.free(info);
      calloc.free(count);
    }
  }

  @override
  double uptimeSeconds() {
    // kern.boottime is a timeval: seconds then microseconds.
    final sysctl = _libc.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Void>, Pointer<IntPtr>, Pointer<Void>, IntPtr),
        int Function(Pointer<Utf8>, Pointer<Void>, Pointer<IntPtr>, Pointer<Void>, int)>('sysctlbyname');
    final Pointer<Utf8> key = 'kern.boottime'.toNativeUtf8();
    final Pointer<Int64> value = calloc<Int64>(2);
    final Pointer<IntPtr> size = calloc<IntPtr>()..value = 16;
    try {
      if (sysctl(key, value.cast(), size, nullptr, 0) != 0) return 0;
      final int booted = value[0];
      return DateTime.now().millisecondsSinceEpoch / 1000 - booted;
    } finally {
      calloc.free(key);
      calloc.free(value);
      calloc.free(size);
    }
  }

  @override
  List<String> load() {
    final getloadavg = _libc.lookupFunction<
        Int32 Function(Pointer<Double>, Int32),
        int Function(Pointer<Double>, int)>('getloadavg');
    final Pointer<Double> out = calloc<Double>(3);
    try {
      if (getloadavg(out, 3) != 3) return const <String>['0', '0', '0'];
      return <String>[for (var i = 0; i < 3; i++) out[i].toStringAsFixed(2)];
    } finally {
      calloc.free(out);
    }
  }

  @override
  int diskFreeBytes(String path) {
    try {
      final ProcessResult r = Process.runSync('df', <String>['-k', path]);
      final List<String> lines = '${r.stdout}'.trim().split('\n');
      final List<String> columns = lines.last.trim().split(RegExp(r'\s+'));
      // Filesystem, 1024-blocks, Used, Available, ...
      return columns.length > 3 ? (int.tryParse(columns[3]) ?? 0) * 1024 : 0;
    } on ProcessException {
      return 0;
    }
  }

  @override
  bool hasTouch() => false;

  @override
  bool hasDisplay() {
    try {
      final DynamicLibrary cg =
          DynamicLibrary.open('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics');
      final int main = cg.lookupFunction<Uint32 Function(), int Function()>('CGMainDisplayID')();
      return cg.lookupFunction<IntPtr Function(Uint32), int Function(int)>('CGDisplayPixelsWide')(main) > 0;
    } on ArgumentError {
      return false;
    }
  }

  @override
  String displayServer() => 'quartz';
}
