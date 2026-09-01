part of '../dartvel_windowing.dart';

// XRRMonitorInfo, as XRandR 1.5 lays it out.
final class _XRRMonitorInfo extends ffi.Struct {
  @ffi.Uint64()
  external int name; // Atom
  @ffi.Int32()
  external int primary;
  @ffi.Int32()
  external int automatic;
  @ffi.Int32()
  external int noutput;
  @ffi.Int32()
  external int x;
  @ffi.Int32()
  external int y;
  @ffi.Int32()
  external int width;
  @ffi.Int32()
  external int height;
  @ffi.Int32()
  external int mwidth;
  @ffi.Int32()
  external int mheight;
  external ffi.Pointer<ffi.Uint64> outputs; // RROutput*
}

// XineramaScreenInfo, the fallback when XRandR reports no monitors.
final class _XineramaScreenInfo extends ffi.Struct {
  @ffi.Int32()
  external int screenNumber;
  @ffi.Int16()
  external int xOrg;
  @ffi.Int16()
  external int yOrg;
  @ffi.Int16()
  external int width;
  @ffi.Int16()
  external int height;
}

/// Enumerates the displays an X11 desktop reports.
///
/// XRandR first, because it is the only one of the two that reports a
/// display's **name** and which is **primary** — and a projector is chosen by
/// name (`DVDisplayHint.byName`) far more often than by index. Xinerama is the
/// fallback: it knows the geometry of each display and nothing else, so its
/// rows are named by index and none is primary. Reporting no primary is
/// correct there; inventing one would make `DVDisplayHint.primary` resolve to
/// a display nothing said was primary.
class _DVLinuxDisplays {
  const _DVLinuxDisplays._();

  static ffi.DynamicLibrary? _x11;
  static ffi.DynamicLibrary? _randr;
  static ffi.DynamicLibrary? _xinerama;

  /// Loads the X libraries. False when there is no X11 at all, which is a
  /// headless container rather than a fault.
  static bool load() {
    if (_x11 != null) return true;
    try {
      _x11 = ffi.DynamicLibrary.open('libX11.so.6');
    } on ArgumentError {
      return false;
    }
    try {
      _randr = ffi.DynamicLibrary.open('libXrandr.so.2');
    } on ArgumentError {
      _randr = null;
    }
    try {
      _xinerama = ffi.DynamicLibrary.open('libXinerama.so.1');
    } on ArgumentError {
      _xinerama = null;
    }
    return true;
  }

  /// The rows `window.displays` reports, in the shape [DVDisplays.fromBinding]
  /// reads.
  static List<Map<String, Object?>> enumerate() {
    if (!load()) return const <Map<String, Object?>>[];

    final openDisplay = _x11!.lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Utf8>),
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Utf8>)>('XOpenDisplay');
    final closeDisplay = _x11!.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('XCloseDisplay');

    final display = openDisplay(ffi.nullptr);
    if (display == ffi.nullptr) return const <Map<String, Object?>>[];

    try {
      final fromRandr = _viaRandr(display);
      if (fromRandr.isNotEmpty) return fromRandr;
      return _viaXinerama(display);
    } finally {
      closeDisplay(display);
    }
  }

  static List<Map<String, Object?>> _viaRandr(ffi.Pointer<ffi.Void> display) {
    final randr = _randr;
    if (randr == null) return const <Map<String, Object?>>[];

    final defaultRootWindow = _x11!.lookupFunction<
        ffi.Uint64 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('XDefaultRootWindow');
    final getMonitors = randr.lookupFunction<
        ffi.Pointer<_XRRMonitorInfo> Function(
            ffi.Pointer<ffi.Void>, ffi.Uint64, ffi.Int32, ffi.Pointer<ffi.Int32>),
        ffi.Pointer<_XRRMonitorInfo> Function(
            ffi.Pointer<ffi.Void>, int, int, ffi.Pointer<ffi.Int32>)>(
      'XRRGetMonitors',
    );
    final freeMonitors = randr.lookupFunction<
        ffi.Void Function(ffi.Pointer<_XRRMonitorInfo>),
        void Function(ffi.Pointer<_XRRMonitorInfo>)>('XRRFreeMonitors');
    final getAtomName = _x11!.lookupFunction<
        ffi.Pointer<ffi.Utf8> Function(ffi.Pointer<ffi.Void>, ffi.Uint64),
        ffi.Pointer<ffi.Utf8> Function(ffi.Pointer<ffi.Void>, int)>(
      'XGetAtomName',
    );
    final xFree = _x11!.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('XFree');

    final count = ffi.calloc<ffi.Int32>();
    try {
      final monitors =
          getMonitors(display, defaultRootWindow(display), 1, count);
      if (monitors == ffi.nullptr || count.value <= 0) {
        return const <Map<String, Object?>>[];
      }
      final rows = <Map<String, Object?>>[];
      for (var i = 0; i < count.value; i++) {
        final m = monitors[i];
        final namePtr = getAtomName(display, m.name);
        final name = namePtr == ffi.nullptr
            ? 'monitor-$i'
            : namePtr.toDartString();
        if (namePtr != ffi.nullptr) xFree(namePtr.cast());
        rows.add(<String, Object?>{
          'id': 'x11-randr-$i',
          'name': name,
          'x': m.x.toDouble(),
          'y': m.y.toDouble(),
          'width': m.width.toDouble(),
          'height': m.height.toDouble(),
          'devicePixelRatio': 1.0,
          'isPrimary': m.primary != 0,
        });
      }
      freeMonitors(monitors);
      return rows;
    } finally {
      ffi.calloc.free(count);
    }
  }

  static List<Map<String, Object?>> _viaXinerama(
      ffi.Pointer<ffi.Void> display) {
    final xinerama = _xinerama;
    if (xinerama == null) return const <Map<String, Object?>>[];

    final isActive = xinerama.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('XineramaIsActive');
    if (isActive(display) == 0) return const <Map<String, Object?>>[];

    final queryScreens = xinerama.lookupFunction<
        ffi.Pointer<_XineramaScreenInfo> Function(
            ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>),
        ffi.Pointer<_XineramaScreenInfo> Function(
            ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>)>(
      'XineramaQueryScreens',
    );
    final xFree = _x11!.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('XFree');

    final count = ffi.calloc<ffi.Int32>();
    try {
      final screens = queryScreens(display, count);
      if (screens == ffi.nullptr || count.value <= 0) {
        return const <Map<String, Object?>>[];
      }
      final rows = <Map<String, Object?>>[];
      for (var i = 0; i < count.value; i++) {
        final s = screens[i];
        rows.add(<String, Object?>{
          'id': 'x11-xinerama-$i',
          'name': 'display-$i',
          'x': s.xOrg.toDouble(),
          'y': s.yOrg.toDouble(),
          'width': s.width.toDouble(),
          'height': s.height.toDouble(),
          'devicePixelRatio': 1.0,
          // Xinerama does not report a primary. Saying "none" is true;
          // guessing index 0 would make DVDisplayHint.primary resolve to a
          // display nothing designated.
          'isPrimary': false,
        });
      }
      xFree(screens.cast());
      return rows;
    } finally {
      ffi.calloc.free(count);
    }
  }
}
