import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

/// Tabs from files: every page in this folder belongs to a tab, each tab
/// keeps its own stack, and back pops inside the tab on screen first.
///
/// `(tabs)` is a route group, so it adds nothing to the paths: the pages
/// here are /library, /library/:book and /saved.
class LibraryTabs extends DartvelTabsLayout {
  const LibraryTabs({super.key, required super.shell});

  static const List<DVRouteTarget> tabs = <DVRouteTarget>[
    DVRoutes.library,
    DVRoutes.saved,
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: shell.goBranch,
          destinations: const <Widget>[
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              label: 'Library',
            ),
            NavigationDestination(
              icon: Icon(Icons.bookmark_outline),
              label: 'Saved',
            ),
          ],
        ),
      );
}
