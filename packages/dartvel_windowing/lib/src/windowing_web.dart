/// [DVWindowHost] where there are no OS windows: a browser.
library dartvel_windowing.web;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';

/// The application root. In a browser it is the home and nothing more:
/// `DV.Platform.window.open` navigates to a window's route instead, and says
/// so through `DVWindow.isVirtual`.
class DVWindowHost extends StatelessWidget {
  const DVWindowHost({super.key, required this.home, required this.routeBuilder});

  final Widget home;

  /// Unused in a browser, where no route gets a window of its own.
  final Widget Function(BuildContext context, DVRouteTarget route) routeBuilder;

  /// The page's one view, as `runApp` would give it: under `runWidget` the
  /// root provides its own `View`, and a bare home has nowhere to render.
  @override
  Widget build(BuildContext context) => View(
        view: WidgetsBinding.instance.platformDispatcher.implicitView!,
        child: home,
      );
}
