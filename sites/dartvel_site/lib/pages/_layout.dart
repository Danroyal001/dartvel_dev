import 'package:flutter/material.dart';

import '../components/site.dart';
import '../components/site_search.dart';
import '../dartvel_client/dartvel_client.dart';

/// The chrome every page on this site sits inside.
///
/// A Dartvel layout, discovered by the generator and wrapped around each page
/// in this directory by the generated router. Pages return their own content
/// and nothing else -- they used to wrap themselves in a `SitePage` widget and
/// hand it their own route as a string, which is the page telling the site
/// something the router already knows from the file it lives in.
///
/// A column rather than a stack: the header takes its height and the page gets
/// the rest, so each page's own scroll view is the only scrollable on screen
/// and the header stays where it is above it.
class const Layout({super.key, required super.child}) extends DartvelLayout {
  /// The "To the bottom / Back to top" button on long pages.
  @override
  bool get pageScrollToTop => true;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Palette.of(context).page,
      child: Column(
        children: <Widget>[
          const SiteHeader(),
          // Ctrl+K or Cmd+K opens the search from anywhere on the page.
          Expanded(child: SiteSearchShortcut(child: child)),
        ],
      ),
    );
  }
}
