import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

/// The docs frame around every page under /docs, inside the site layout.
///
/// A layout, so the sidebar is written once and each page returns only its
/// own article. The current path comes from the router, the one place that
/// already knows which page is open.
class DocsLayout extends DartvelLayout {
  const DocsLayout({super.key, required super.child});

  @override
  Widget build(BuildContext context) => DocsFrame(
        current: GoRouterState.of(context).uri.path,
        child: child,
      );
}
