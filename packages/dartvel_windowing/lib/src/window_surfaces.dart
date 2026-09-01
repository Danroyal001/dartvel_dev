part of '../dartvel_windowing.dart';

/// One OS surface rendering one window's route.
abstract class DVWindowSurface {
  /// The window this surface presents.
  DVWindow get window;

  /// What the window renders.
  Widget get content;

  /// Releases the OS window. Called when the window leaves the manager's list.
  void destroy();
}

/// Creates the surface for a window.
///
/// The seam exists so the reconciler can be tested without an engine: building
/// a real window controller in a headless test would reach Flutter's windowing
/// FFI and take the process with it.
abstract class DVWindowSurfaceFactory {
  /// Builds the surface for [window], rendering [content].
  DVWindowSurface create(DVWindow window, Widget content);
}

/// Keeps the live OS surfaces in step with [DVWindowManager]'s window list.
///
/// Two rules carry the weight here, and both were measured rather than
/// assumed — see `docs/proposals/2026-09-multiwindow-stable-probe.md`.
///
/// **Nothing is created before the first frame.** Building a window controller
/// while the engine is still coming up does not throw; it ends the process
/// with an X `BadAccess`, on Flutter master even for a single window. Windows
/// asked for early are held until [markFirstFrame] and created then, so no
/// application can get the timing wrong by calling `open()` from `main`.
///
/// **A degraded window never gets a surface.** `DVWindowManager.open` always
/// presents the route, navigating to it when a window cannot be created. A
/// surface for that window would present the same route twice.
class DVWindowSurfaces {
  DVWindowSurfaces({
    required DVWindowSurfaceFactory factory,
    required Widget Function(DVWindow window) contentFor,
  })  : _factory = factory,
        _contentFor = contentFor;

  final DVWindowSurfaceFactory _factory;
  final Widget Function(DVWindow window) _contentFor;

  final List<DVWindowSurface> _live = <DVWindowSurface>[];
  List<DVWindow> _pending = <DVWindow>[];
  bool _firstFrame = false;

  /// The surfaces currently presenting, in the order their windows opened.
  List<DVWindowSurface> get live => List<DVWindowSurface>.unmodifiable(_live);

  /// Whether the first frame has rendered and windows may now be created.
  bool get isReady => _firstFrame;

  /// Records that the first frame has rendered, and creates whatever was
  /// asked for before it.
  void markFirstFrame() {
    if (_firstFrame) return;
    _firstFrame = true;
    final pending = _pending;
    _pending = <DVWindow>[];
    sync(pending);
  }

  /// Reconciles against [windows], creating and destroying surfaces so the
  /// live set matches.
  ///
  /// Safe to call on every rebuild: a window that already has a surface keeps
  /// the one it has rather than being recreated, because recreating it would
  /// flash the projector black mid-service.
  void sync(List<DVWindow> windows) {
    final wanted = windows.where((w) => !w.isVirtual).toList(growable: false);

    if (!_firstFrame) {
      _pending = wanted;
      return;
    }

    for (final surface in _live.toList()) {
      if (!wanted.contains(surface.window)) {
        surface.destroy();
        _live.remove(surface);
      }
    }

    for (final window in wanted) {
      if (_live.any((s) => identical(s.window, window))) continue;
      _live.add(_factory.create(window, _contentFor(window)));
    }
  }

  /// Destroys every surface. For teardown and for tests.
  void dispose() {
    for (final surface in _live) {
      surface.destroy();
    }
    _live.clear();
    _pending = <DVWindow>[];
  }
}
