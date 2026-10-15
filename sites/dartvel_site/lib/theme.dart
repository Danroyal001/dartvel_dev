import 'package:flutter/material.dart';
import 'dartvel_client/dartvel_client.dart';

/// A scrollbar on every scrollable, for every input.
///
/// Flutter's Material behaviour draws one for a mouse or a trackpad and none
/// for touch, which on the web means a tablet gets no indication of how long a
/// page is. The docs page is nine sections; without a thumb it looks the same
/// near the top as near the bottom.
///
/// Overridden rather than configured because the platform switch is inside
/// `buildScrollbar` and there is no flag for "also touch". The theme handles
/// the other half — see [dartvelSiteTheme] — since a scrollbar that exists and
/// fades after a second is barely better than none.
class const DartvelSiteScrollBehavior() extends MaterialScrollBehavior {
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      Scrollbar(controller: details.controller, child: child);
}

/// The theme every page is given.
///
/// Public so a test can read what the pages actually get rather than asserting
/// against a copy of it.
ThemeData dartvelSiteTheme(Brightness brightness) =>
    dartvelDefaultTheme(brightness, fontPackage: null);
