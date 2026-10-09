// The only place that touches Flutter's windowing API, which is @internal,
// behind a feature flag, and master-channel only.
// ignore_for_file: invalid_use_of_internal_member
part of '../dartvel_windowing.dart';

/// Turns a Dartvel window into a real OS window.
class DVFlutterWindowSurfaceFactory implements DVWindowSurfaceFactory {
  const DVFlutterWindowSurfaceFactory();

  /// Enables Flutter's windowing feature for this application.
  ///
  /// The flag is a plain mutable `bool` the tool sets from
  /// `--dart-define=FLUTTER_ENABLED_FEATURE_FLAGS`, and it only injects that
  /// define on the master channel — `flutter config --enable-windowing`
  /// reports success on stable and changes nothing. Assigning it here means an
  /// application gets the same behaviour however it was built, and does not
  /// have to know the flag exists.
  static void enable() {
    if (_enabled) return;
    _enabled = true;
    isWindowingEnabled = true;
    // The binding chose its windowing owner when it was initialized, which is
    // before any application code runs, and with the flag still false it
    // chose the "unsupported" owner. Setting the flag afterwards does not
    // replace it, so every window controller threw "Windowing APIs are not
    // enabled" on stable. Installing the platform's owner now is what makes
    // the flag take effect.
    final binding = WidgetsBinding.instance;
    binding.windowingOwner = createDefaultWindowingOwner();
  }

  static bool _enabled = false;

  /// Used when a window is opened without a size.
  ///
  /// `DVWindowOptions.size` is optional, so the gap has to be filled
  /// somewhere. It is filled here, visibly, rather than by making the Dartvel
  /// option required: a projector window's real size comes from the display it
  /// is going to, which is a separate question from what a window defaults to.
  static const Size defaultSize = Size(1280, 720);

  /// The size a window is asked for: a kiosk covers the display it owns,
  /// anything else gets what it asked for or the default.
  static Size preferredSizeFor(DVWindowRequest? request, List<DVDisplay> displays) {
    if (request?.kind == 'kiosk' && request?.displayId != null) {
      for (final DVDisplay d in displays) {
        if (d.id == request!.displayId) return d.bounds.size;
      }
    }
    return request?.size ?? defaultSize;
  }

  @override
  DVWindowSurface create(DVWindow window, Widget content) {
    final request = _DVWindowBindings.requestFor(window.nativeId);
    final size = preferredSizeFor(request, DV.Platform.window.displays.value);
    // RegularWindowController, and the size is a request: the platform
    // may not honour either. Named for the window kind rather than generic,
    // because Flutter has a controller per kind -- dialog, popup, tooltip,
    // satellite -- and the owned kinds are not wired up yet.
    // No constraints: DVWindowOptions.constraints is not carried
    // in the window.open payload yet, and passing null here would look like
    // it had been considered.
    final surface = _FlutterWindowSurface(
      window,
      content,
      RegularWindowController(size: size, title: request?.title),
    );
    // Creating the controller realizes a new Flutter view, and on Linux the
    // embedder leaves its EGL context current on this (the GTK main) thread.
    // GTK's next paint then makes a GLX context current here, libglvnd
    // refuses, and the process ends with a GLX BadAccess. See _DVLinuxEgl.
    if (Platform.isLinux) _DVLinuxEgl.releaseCurrentContext();

    // Which display, as DVWindowOptions.display asked: Flutter's controller
    // takes no display, so without this the window manager puts the
    // projector on the operator's screen.
    final display = _DVWindowBindings.displayFor(request?.displayId);
    if (display != null) surface.placeOn(display, size: size);

    final pending = _DVWindowBindings.takePendingFullscreen(window.nativeId);
    if (pending.requested) {
      surface.setFullscreen(true,
          on: _DVWindowBindings.displayFor(pending.displayId));
    }
    return surface;
  }
}

class _FlutterWindowSurface implements DVWindowSurface {
  _FlutterWindowSurface(this.window, this._child, this._controller);

  @override
  final DVWindow window;
  final Widget _child;
  final RegularWindowController _controller;

  @override
  Widget get content => RegularWindow(controller: _controller, child: _child);

  /// The GtkWindow behind the controller, on Linux.
  ffi.Pointer<ffi.Void>? get _gtkWindow {
    final controller = _controller;
    return controller is WindowControllerLinux
        ? (controller as WindowControllerLinux).windowHandle
        : null;
  }

  /// Moves the window onto [display]. Linux only: elsewhere the OS places it.
  bool placeOn(DVDisplay display, {Size? size}) {
    final handle = _gtkWindow;
    return handle != null && _DVLinuxWindows.placeOn(handle, display, size: size);
  }

  @override
  bool setFullscreen(bool fullscreen, {DVDisplay? on}) {
    final handle = _gtkWindow;
    if (handle != null) {
      return fullscreen
          ? _DVLinuxWindows.fullscreen(handle, on)
          : _DVLinuxWindows.unfullscreen(handle);
    }
    // Elsewhere Flutter's controller is the only way in, and it does not
    // promise to honour a display. Refused rather than fullscreened on
    // whichever display the window is on.
    if (fullscreen && on != null) return false;
    _controller.setFullscreen(fullscreen);
    return true;
  }

  @override
  void destroy() => _controller.destroy();
}
