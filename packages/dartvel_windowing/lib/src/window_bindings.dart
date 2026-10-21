part of 'windowing_native.dart';

/// What an application asked for when it opened a window.
///
/// `DVWindow` records what a window *is* — its route, kind, presentation and
/// degradation — and not what was requested of the platform, so the size and
/// title arrive with the binding call and are kept here until the surface for
/// that window is built.
@immutable
class DVWindowRequest {
  const DVWindowRequest({
    this.size,
    this.title,
    this.route,
    this.kind,
    this.displayId,
    this.takesFocus = true,
  });

  /// The size asked for, or null to let the platform choose.
  final Size? size;

  /// The title asked for, or null to fall back to the application name.
  final String? title;

  /// The route the window presents.
  final String? route;

  /// The window kind's name -- `regular`, `kiosk`, ... -- as the manager
  /// asked for it. A kiosk is sized to its display.
  final String? kind;

  /// The display the manager resolved, if it asked for one.
  final String? displayId;

  /// False for a window that must never take keyboard focus: a projector or
  /// stage display (`DVWindowOptions.takesFocus`).
  final bool takesFocus;

  /// This request with [takesFocus] changed.
  DVWindowRequest withTakesFocus(bool takesFocus) => DVWindowRequest(
        size: size,
        title: title,
        route: route,
        kind: kind,
        displayId: displayId,
        takesFocus: takesFocus,
      );
}

/// Registers the desktop window bindings.
///
/// `DVWindowingCapability.detect` gates `multiWindow` on `window.open` being
/// registered rather than on the API being importable, so this call is what
/// makes `DV.Platform.window.open` present a real window instead of degrading
/// to a page. Nothing else in Dartvel has to change.
class _DVWindowBindings {
  const _DVWindowBindings._();

  static final Map<String, DVWindowRequest> _requests =
      <String, DVWindowRequest>{};
  static int _sequence = 0;
  static bool _registered = false;

  /// The live surfaces, so a call naming a window can reach its OS window.
  /// Set by [DVWindowHost].
  static DVWindowSurfaces? _surfaces;
  static void useSurfaces(DVWindowSurfaces? surfaces) => _surfaces = surfaces;

  /// Fullscreen asked for before the window's surface existed, by native id:
  /// the display id to fill, or null for wherever the window is.
  ///
  /// An application opens the projector and fullscreens it in one breath, and
  /// the surface is not created until the first frame has rasterized, so the
  /// request has to wait for it rather than be lost.
  static final Map<String, String?> _pendingFullscreen = <String, String?>{};

  /// Takes the fullscreen request held for [nativeId], if any. Called once
  /// the surface exists.
  static ({bool requested, String? displayId}) takePendingFullscreen(
      String? nativeId) {
    if (nativeId == null || !_pendingFullscreen.containsKey(nativeId)) {
      return (requested: false, displayId: null);
    }
    return (requested: true, displayId: _pendingFullscreen.remove(nativeId));
  }

  /// The display [displayId] names in the last enumeration, if any.
  static DVDisplay? displayFor(String? displayId) {
    if (displayId == null) return null;
    for (final DVDisplay display in DV.Platform.window.displays.value) {
      if (display.id == displayId) return display;
    }
    return null;
  }

  /// Registers `window.open`, `window.close`, `window.displays`,
  /// `window.setFullscreen` and `window.setTakesFocus`.
  ///
  /// The handlers do not create the OS window. They allocate its identity and
  /// record what was asked for; the window itself is created by
  /// [DVWindowSurfaces] once a frame has rendered, because a window controller
  /// built before the engine is up ends the process rather than throwing.
  static void register() {
    if (_registered) return;
    _registered = true;

    DVNativeBridge.register('window.open', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      final id = 'dv-window-${++_sequence}';
      final width = map['width'];
      final height = map['height'];
      _requests[id] = DVWindowRequest(
        size: width is num && height is num
            ? Size(width.toDouble(), height.toDouble())
            : null,
        title: map['title'] as String?,
        route: map['route'] as String?,
        kind: map['kind'] as String?,
        displayId: map['displayId'] as String?,
      );
      return id;
    });

    // Enumeration is a read, so it needs no request bookkeeping. It is
    // registered here rather than in dartvel_flutter's Linux bindings because
    // the specification lists window.displays among the *desktop windowing*
    // bindings, and because a target with no windowing has nothing to enumerate.
    DVNativeBridge.register('window.displays', (Object? _) => enumerateDisplays());

    // Fullscreen, on a named display. DVWindow.setFullscreen has already
    // resolved the hint to a display id; a display id this process has not
    // enumerated is refused, because filling some other display instead puts
    // the output on the operator's screen.
    DVNativeBridge.register('window.setFullscreen', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      final id = map['id'];
      if (id is! String || !_requests.containsKey(id)) return false;
      final fullscreen = map['fullscreen'] != false;
      final displayId = fullscreen ? map['displayId'] as String? : null;
      if (displayId != null && displayFor(displayId) == null) return false;

      final surface = _surfaces?.forNativeId(id);
      if (surface == null) {
        if (fullscreen) {
          _pendingFullscreen[id] = displayId;
        } else {
          _pendingFullscreen.remove(id);
        }
        return true;
      }
      return surface.setFullscreen(fullscreen, on: displayFor(displayId));
    });

    // A window that never takes keyboard focus. The manager asks right after
    // window.open, before the window is listed and so before its surface
    // exists; the surface applies it when the OS window is created, which is
    // before it is first shown. Linux only: elsewhere the answer is no, and
    // the manager puts DV-WINDOW-016 on the window rather than pretending.
    DVNativeBridge.register('window.setTakesFocus', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      final id = map['id'];
      if (id is! String || !_requests.containsKey(id)) return false;
      final takesFocus = map['takesFocus'] != false;
      // Recorded everywhere: the window's own widgets are kept from taking
      // focus on every platform (see contentFor). Only the OS half is Linux.
      _requests[id] = _requests[id]!.withTakesFocus(takesFocus);
      if (!Platform.isLinux) return false;
      final surface = _surfaces?.forNativeId(id);
      if (surface is _FlutterWindowSurface) {
        return surface.setTakesFocus(takesFocus);
      }
      return true;
    });

    DVNativeBridge.register('window.close', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      final id = map['id'];
      if (id is String) {
        _requests.remove(id);
        _pendingFullscreen.remove(id);
      }
      return true;
    });
  }

  /// The displays the running desktop reports, in the shared decoder's
  /// spelling: XRandR or Xinerama on Linux, EnumDisplayMonitors on Windows,
  /// CGGetActiveDisplayList on macOS. Empty where there is no desktop.
  static List<Map<String, Object?>> enumerateDisplays() {
    if (Platform.isWindows) return _DVWindowsDisplays.enumerate();
    if (Platform.isMacOS) return _DVMacosDisplays.enumerate();
    if (Platform.isLinux) return _DVLinuxDisplays.enumerate();
    return const <Map<String, Object?>>[];
  }

  /// What [window] renders [content] as.
  ///
  /// A window that takes no focus gets none inside Flutter either. Every
  /// window is a view of one widget tree with one FocusManager, and a key goes
  /// to its primary focus whichever OS window delivered it. Measured on a
  /// two-monitor X server: with the projector's GTK window refusing focus the
  /// operator's window kept the X input focus, and an `autofocus` in the
  /// projector's route still took every keystroke. [ExcludeFocus] keeps any
  /// widget in it from becoming focused at all.
  static Widget contentFor(DVWindow window, Widget content) {
    final DVWindowRequest? request = requestFor(window.nativeId);
    if (request == null || request.takesFocus) return content;
    return ExcludeFocus(child: content);
  }

  /// What was asked for when the window with [nativeId] was opened.
  static DVWindowRequest? requestFor(String? nativeId) =>
      nativeId == null ? null : _requests[nativeId];

  /// Unregisters the bindings and forgets every request. For tests, and for a
  /// target that tears the windowing layer down.
  static void reset() {
    DVNativeBridge.unregister('window.open');
    DVNativeBridge.unregister('window.close');
    DVNativeBridge.unregister('window.displays');
    DVNativeBridge.unregister('window.setFullscreen');
    DVNativeBridge.unregister('window.setTakesFocus');
    _requests.clear();
    _pendingFullscreen.clear();
    _surfaces = null;
    _sequence = 0;
    _registered = false;
  }
}
