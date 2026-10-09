part of '../dartvel_windowing.dart';

// GdkRectangle: four ints, logical (unscaled) pixels.
final class _GdkRectangle extends ffi.Struct {
  @ffi.Int32()
  external int x;
  @ffi.Int32()
  external int y;
  @ffi.Int32()
  external int width;
  @ffi.Int32()
  external int height;
}

/// Puts a GTK toplevel on a chosen display, and fullscreens it there.
///
/// Flutter's `RegularWindowController.setFullscreen(display:)` ignores the
/// display on Linux (its own TODO says so) and calls plain
/// `gtk_window_fullscreen`, which fullscreens the window on whichever monitor
/// the window manager happened to place it on. For a projector output that is
/// the operator's own screen, in front of the room. So the window is moved onto
/// the display first and then fullscreened with
/// `gtk_window_fullscreen_on_monitor`, which sets `_NET_WM_FULLSCREEN_MONITORS`
/// for a window manager that honours it and is a plain fullscreen on the
/// monitor the window is now on for one that does not.
///
/// The display is matched to a GDK monitor by its origin: `window.displays`
/// reports XRandR monitors in X pixels, GDK reports the same monitors in
/// logical pixels with a scale factor, and the origin times the scale is the
/// one thing both agree on without trusting that the two lists are in the
/// same order.
class _DVLinuxWindows {
  const _DVLinuxWindows._();

  static ffi.DynamicLibrary? _gtk;

  static ffi.DynamicLibrary? _load() {
    if (_gtk != null) return _gtk;
    try {
      // The process already has GTK loaded (the runner is a GTK app), so this
      // resolves to the same copy rather than loading a second one.
      _gtk = ffi.DynamicLibrary.open('libgtk-3.so.0');
    } on ArgumentError {
      _gtk = null;
    }
    return _gtk;
  }

  /// The GDK monitor index showing [target], or null when none does.
  static int? monitorIndexFor(ffi.Pointer<ffi.Void> window, DVDisplay target) {
    final gtk = _load();
    if (gtk == null || window == ffi.nullptr) return null;
    final getDisplay = gtk.lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)>(
      'gtk_widget_get_display',
    );
    final monitorCount = gtk.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('gdk_display_get_n_monitors');
    final monitorAt = gtk.lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.Int32),
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int)>(
      'gdk_display_get_monitor',
    );
    final geometryOf = gtk.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<_GdkRectangle>),
        void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<_GdkRectangle>)>(
      'gdk_monitor_get_geometry',
    );
    final scaleOf = gtk.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('gdk_monitor_get_scale_factor');

    final display = getDisplay(window);
    if (display == ffi.nullptr) return null;
    final rect = ffi.calloc<_GdkRectangle>();
    try {
      final count = monitorCount(display);
      for (var index = 0; index < count; index++) {
        final monitor = monitorAt(display, index);
        if (monitor == ffi.nullptr) continue;
        geometryOf(monitor, rect);
        final scale = scaleOf(monitor);
        if (rect.ref.x * scale == target.bounds.left.round() &&
            rect.ref.y * scale == target.bounds.top.round()) {
          return index;
        }
      }
      return null;
    } finally {
      ffi.calloc.free(rect);
    }
  }

  /// Moves [window] onto [target], centred if it fits. False when [target] is
  /// not a monitor GDK knows, so the caller can refuse rather than guess.
  static bool placeOn(ffi.Pointer<ffi.Void> window, DVDisplay target,
      {Size? size}) {
    final gtk = _load();
    final index = monitorIndexFor(window, target);
    if (gtk == null || index == null) return false;
    final move = gtk.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32),
        void Function(ffi.Pointer<ffi.Void>, int, int)>('gtk_window_move');
    final bounds = target.bounds;
    final width = size?.width ?? 0;
    final height = size?.height ?? 0;
    final left = width > 0 && width < bounds.width
        ? bounds.left + (bounds.width - width) / 2
        : bounds.left;
    final top = height > 0 && height < bounds.height
        ? bounds.top + (bounds.height - height) / 2
        : bounds.top;
    move(window, left.round(), top.round());
    return true;
  }

  /// Fullscreens [window] on [target], or wherever it is when [target] is
  /// null. False when [target] is not a monitor GDK knows.
  static bool fullscreen(ffi.Pointer<ffi.Void> window, DVDisplay? target) {
    final gtk = _load();
    if (gtk == null || window == ffi.nullptr) return false;
    if (target == null) {
      gtk.lookupFunction<ffi.Void Function(ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<ffi.Void>)>('gtk_window_fullscreen')(window);
      return true;
    }
    final index = monitorIndexFor(window, target);
    if (index == null) return false;
    placeOn(window, target);
    final screenOf = gtk.lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)>(
      'gtk_window_get_screen',
    );
    final fullscreenOnMonitor = gtk.lookupFunction<
        ffi.Void Function(
            ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Int32),
        void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, int)>(
      'gtk_window_fullscreen_on_monitor',
    );
    fullscreenOnMonitor(window, screenOf(window), index);
    return true;
  }

  /// Leaves fullscreen.
  static bool unfullscreen(ffi.Pointer<ffi.Void> window) {
    final gtk = _load();
    if (gtk == null || window == ffi.nullptr) return false;
    gtk.lookupFunction<ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)>('gtk_window_unfullscreen')(window);
    return true;
  }
}

/// Releases an EGL context Flutter's Linux embedder left current on the GTK
/// main thread.
///
/// Measured, not assumed (see the multi-window probe): when a second view is
/// realized while the engine is running, the embedder's realize handler makes
/// its EGL context current on the main thread and does not release it. The
/// next time GTK paints a window it makes GDK's own **GLX** paint context
/// current on that thread, and libglvnd refuses to make a GLX context current
/// on a thread where an EGL context is current: it raises `BadAccess` on
/// `X_GLXMakeContextCurrent` locally, and GDK's X error handler ends the
/// process. Whether that paint comes before or after the engine next tidies
/// up is timing -- a window manager's reparent and configure make it come
/// first, which is why the two windows survived a bare X server and died
/// under openbox.
///
/// libglvnd is how every current Linux distribution ships both Mesa and the
/// NVIDIA driver, so this is not a software-GL quirk. Dart runs on the GTK main
/// thread on Linux, so releasing the context right after the window is
/// created, from Dart, restores what GDK needs. The engine makes its context
/// current again whenever it uses it.
class _DVLinuxEgl {
  const _DVLinuxEgl._();

  static ffi.DynamicLibrary? _egl;
  static bool _loadFailed = false;

  /// Releases the calling thread's current EGL context, if there is one.
  /// True when one was released.
  static bool releaseCurrentContext() {
    if (_loadFailed) return false;
    try {
      _egl ??= ffi.DynamicLibrary.open('libEGL.so.1');
    } on ArgumentError {
      _loadFailed = true;
      return false;
    }
    final egl = _egl!;
    final currentContext = egl.lookupFunction<ffi.Pointer<ffi.Void> Function(),
        ffi.Pointer<ffi.Void> Function()>('eglGetCurrentContext');
    if (currentContext() == ffi.nullptr) return false;
    final currentDisplay = egl.lookupFunction<ffi.Pointer<ffi.Void> Function(),
        ffi.Pointer<ffi.Void> Function()>('eglGetCurrentDisplay');
    final makeCurrent = egl.lookupFunction<
        ffi.Uint32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)>('eglMakeCurrent');
    // EGL_NO_SURFACE and EGL_NO_CONTEXT are both null.
    return makeCurrent(currentDisplay(), ffi.nullptr, ffi.nullptr, ffi.nullptr) != 0;
  }
}
