// ignore_for_file: invalid_use_of_internal_member

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'flutter_window_surface.dart';
import 'window_surfaces.dart';
import 'windowing.dart';

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
}

class _DVWindowHostState extends State<DVWindowHost> {
  late final DVWindowSurfaces _surfaces;
  late final ValueListenable<List<DVWindow>> _windows;

  @override
  void initState() {
    super.initState();
    DVFlutterWindowSurfaceFactory.enable();
    DVWindowing.register();

    _surfaces = DVWindowSurfaces(
      factory: widget.factory,
      contentFor: (DVWindow window) => Builder(
        builder: (BuildContext context) =>
            widget.routeBuilder(context, window.route),
      ),
    );

    _windows = DV.Platform.Window.all;
    _windows.addListener(_onWindowsChanged);

    // Windows are held until a frame has rendered. Creating a window
    // controller while the engine is still coming up does not throw -- it ends
    // the process with an X BadAccess, on master even for a single window.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(_surfaces.markFirstFrame);
    });
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
