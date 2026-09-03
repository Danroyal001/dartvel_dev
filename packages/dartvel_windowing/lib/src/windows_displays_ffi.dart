part of '../dartvel_windowing.dart';

// RECT.
final class _Rect extends ffi.Struct {
  @ffi.Int32()
  external int left;
  @ffi.Int32()
  external int top;
  @ffi.Int32()
  external int right;
  @ffi.Int32()
  external int bottom;
}

// MONITORINFOEXW: MONITORINFO followed by the device name.
final class _MonitorInfoEx extends ffi.Struct {
  @ffi.Uint32()
  external int cbSize;
  external _Rect rcMonitor;
  external _Rect rcWork;
  @ffi.Uint32()
  external int dwFlags;
  @ffi.Array(32)
  external ffi.Array<ffi.Uint16> szDevice;
}

typedef _MonitorEnumProcNative = ffi.Int32 Function(
    ffi.IntPtr hMonitor, ffi.IntPtr hdc, ffi.Pointer<_Rect> rect, ffi.IntPtr lParam);

/// Display enumeration on Windows: EnumDisplayMonitors, GetMonitorInfoW for
/// the bounds, the primary flag and the device name, GetDpiForMonitor for
/// the scale where Windows 8.1's shcore is present.
class _DVWindowsDisplays {
  const _DVWindowsDisplays._();

  static const int _monitorInfoPrimary = 0x1;

  static List<Map<String, Object?>> enumerate() {
    final ffi.DynamicLibrary user32;
    try {
      user32 = ffi.DynamicLibrary.open('user32.dll');
    } on ArgumentError {
      return const <Map<String, Object?>>[];
    }
    ffi.DynamicLibrary? shcore;
    try {
      shcore = ffi.DynamicLibrary.open('shcore.dll');
    } on ArgumentError {
      shcore = null;
    }

    final enumMonitors = user32.lookupFunction<
        ffi.Int32 Function(ffi.IntPtr, ffi.Pointer<_Rect>,
            ffi.Pointer<ffi.NativeFunction<_MonitorEnumProcNative>>, ffi.IntPtr),
        int Function(int, ffi.Pointer<_Rect>,
            ffi.Pointer<ffi.NativeFunction<_MonitorEnumProcNative>>, int)>('EnumDisplayMonitors');
    final getInfo = user32.lookupFunction<
        ffi.Int32 Function(ffi.IntPtr, ffi.Pointer<_MonitorInfoEx>),
        int Function(int, ffi.Pointer<_MonitorInfoEx>)>('GetMonitorInfoW');
    final getDpi = shcore?.lookupFunction<
        ffi.Int32 Function(ffi.IntPtr, ffi.Int32, ffi.Pointer<ffi.Uint32>, ffi.Pointer<ffi.Uint32>),
        int Function(int, int, ffi.Pointer<ffi.Uint32>, ffi.Pointer<ffi.Uint32>)>('GetDpiForMonitor');

    final List<int> handles = <int>[];
    int collect(int hMonitor, int hdc, ffi.Pointer<_Rect> rect, int lParam) {
      handles.add(hMonitor);
      return 1;
    }

    final callback = ffi.NativeCallable<_MonitorEnumProcNative>.isolateLocal(collect, exceptionalReturn: 0);
    try {
      enumMonitors(0, ffi.nullptr, callback.nativeFunction, 0);
    } finally {
      callback.close();
    }

    final rows = <Map<String, Object?>>[];
    final info = ffi.calloc<_MonitorInfoEx>();
    final dpiX = ffi.calloc<ffi.Uint32>();
    final dpiY = ffi.calloc<ffi.Uint32>();
    try {
      for (var i = 0; i < handles.length; i++) {
        final int handle = handles[i];
        info.ref.cbSize = ffi.sizeOf<_MonitorInfoEx>();
        if (getInfo(handle, info) == 0) continue;
        final _Rect r = info.ref.rcMonitor;
        final String device = _deviceName(info.ref.szDevice);
        var scale = 1.0;
        if (getDpi != null && getDpi(handle, 0, dpiX, dpiY) == 0 && dpiX.value > 0) {
          scale = dpiX.value / 96.0;
        }
        rows.add(<String, Object?>{
          'id': device.isEmpty ? 'win32-$i' : device,
          'name': device.isEmpty ? 'display-$i' : device,
          'x': r.left.toDouble(),
          'y': r.top.toDouble(),
          'width': (r.right - r.left).toDouble(),
          'height': (r.bottom - r.top).toDouble(),
          'devicePixelRatio': scale,
          'isPrimary': info.ref.dwFlags & _monitorInfoPrimary != 0,
        });
      }
    } finally {
      ffi.calloc.free(info);
      ffi.calloc.free(dpiX);
      ffi.calloc.free(dpiY);
    }
    return rows;
  }

  static String _deviceName(ffi.Array<ffi.Uint16> units) {
    final List<int> codes = <int>[];
    for (var i = 0; i < 32; i++) {
      final int u = units[i];
      if (u == 0) break;
      codes.add(u);
    }
    return String.fromCharCodes(codes);
  }
}
