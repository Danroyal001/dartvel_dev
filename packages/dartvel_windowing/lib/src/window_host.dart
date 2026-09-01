part of '../dartvel_windowing.dart';

/// The application root when the app can open windows.
///
/// Pass this to `runWidget` in place of `runApp`. The application's own
/// content renders in the window the runner created, and every window opened
/// through `DV.Platform.Window.open` renders alongside it in the same widget
/// tree — so state shared between the operator surface and a projector surface
/// is ordinary Dartvel state, read in two places, rather than a protocol.
///
/// [routeBuilder] renders a window's route. It is called once per open window.
class DVWindowHost extends StatefulWidget {
  const DVWindowHost({
    super.key,
    required this.home,
    required this.routeBuilder,
    this.factory = const DVFlutterWindowSurfaceFactory(),
  });

  /// What the application's own window shows.
  final Widget home;

  /// Renders the route an opened window presents.
  final Widget Function(BuildContext context, DVRouteTarget route) routeBuilder;

  /// How a window becomes an OS surface. Replaceable for tests.
  final DVWindowSurfaceFactory factory;

  @override
  State<DVWindowHost> createState() => _DVWindowHostState();

  /// Registers the window bindings without mounting a host.
  ///
  /// The registrar is private because the windowing contract says anything
  /// beyond `DV.Window` and `DVWindow` is private, and Dart privacy is per
  /// library. Tests still have to reach it, and mounting a real host in a
  /// headless test would build a window controller and take the process with
  /// it, so the seam is here rather than in the public API.
  @visibleForTesting
  static void debugRegisterBindings() => _DVWindowBindings.register();

  /// Unregisters the bindings and forgets every recorded request.
  @visibleForTesting
  static void debugResetBindings() => _DVWindowBindings.reset();

  /// What was asked for when the window with [nativeId] was opened.
  @visibleForTesting
  static DVWindowRequest? debugRequestFor(String? nativeId) =>
      _DVWindowBindings.requestFor(nativeId);
}

class _DVWindowHostState extends State<DVWindowHost> {
  late final DVWindowSurfaces _surfaces;
  late final ValueListenable<List<DVWindow>> _windows;

  @override
  void initState() {
    super.initState();
    DVFlutterWindowSurfaceFactory.enable();
    _DVWindowBindings.register();

    _surfaces = DVWindowSurfaces(
      factory: widget.factory,
      contentFor: (DVWindow window) => Builder(
        builder: (BuildContext context) =>
            widget.routeBuilder(context, window.route),
      ),
    );

    _DVWindowBindings.useSurfaces(_surfaces);

    _windows = DV.Platform.Window.all;
    _windows.addListener(_onWindowsChanged);

    // Windows are held until the first frame has been **rasterized**, not
    // merely built. Creating a window controller before the engine is up does
    // not throw -- it ends the process with an X BadAccess.
    //
    // addPostFrameCallback is not enough, and that was measured rather than
    // reasoned: it fires after build, layout and paint but before the raster
    // thread has presented anything, and a window created in it still killed
    // the process. waitUntilFirstFrameRasterized is the signal that the engine
    // has actually put a frame on screen.
    unawaited(WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) {
      if (!mounted) return;
      setState(_surfaces.markFirstFrame);
    }));
  }

  void _onWindowsChanged() {
    if (!mounted) return;
    setState(() => _surfaces.sync(_windows.value));
  }

  @override
  void dispose() {
    _windows.removeListener(_onWindowsChanged);
    _surfaces.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ViewCollection(
      views: <Widget>[
        View(
          view: PlatformDispatcher.instance.implicitView!,
          child: widget.home,
        ),
        for (final surface in _surfaces.live) surface.content,
      ],
    );
  }
}
