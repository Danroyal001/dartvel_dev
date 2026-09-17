import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';
import '../../components/shop_ui.dart';
import '../../shop/cart.dart';
import '../../theme/palette.dart';

/// The shop's four tabs, from files: every page in this folder belongs to
/// one, each tab keeps its own stack, and back pops inside the tab on screen
/// first.
///
/// `(tabs)` is a route group, so it adds nothing to the paths: the pages here
/// are /, /coffee/:slug, /cart, /orders, /orders/:id, /saved and /account.
///
/// A phone gets them along the bottom, where a thumb is; anything wider gets
/// a rail down the side, where a pointer is.
class ShopTabs extends DartvelTabsLayout {
  const ShopTabs({super.key, required super.shell});

  static const List<DVRouteTarget> tabs = <DVRouteTarget>[
    DVRoutes.index,
    DVRoutes.orders,
    DVRoutes.saved,
    DVRoutes.account,
  ];

  static const List<(String, IconData, IconData)> destinations =
      <(String, IconData, IconData)>[
        ('Shop', Icons.storefront_outlined, Icons.storefront),
        ('Orders', Icons.receipt_long_outlined, Icons.receipt_long),
        ('Saved', Icons.bookmark_border, Icons.bookmark),
        ('Account', Icons.person_outline, Icons.person),
      ];

  @override
  Widget build(BuildContext context) {
    final int bagCount = context.global<Cart>().count;
    final Palette p = Palette.of(context);
    final bool wide = MediaQuery.sizeOf(context).width >= wideLayoutFrom;

    Widget icon(int index, {required bool selected}) {
      final Icon glyph = Icon(
        selected ? destinations[index].$3 : destinations[index].$2,
      );
      if (index != 0 || bagCount == 0) return glyph;
      return Badge(
        key: const Key('bag-count'),
        label: Text('$bagCount'),
        backgroundColor: p.accent,
        textColor: p.onAccent,
        child: glyph,
      );
    }

    if (!wide) {
      return Scaffold(
        body: shell,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.line)),
          ),
          child: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: shell.goBranch,
            destinations: <Widget>[
              for (int i = 0; i < destinations.length; i++)
                NavigationDestination(
                  icon: icon(i, selected: false),
                  selectedIcon: icon(i, selected: true),
                  label: destinations[i].$1,
                ),
            ],
          ),
        ),
      );
    }

    final bool extended = MediaQuery.sizeOf(context).width >= 1100;
    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            extended: extended,
            minExtendedWidth: 220,
            selectedIndex: shell.currentIndex,
            onDestinationSelected: shell.goBranch,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.fromLTRB(8, 20, 8, 28),
              child: Wordmark(compact: !extended),
            ),
            destinations: <NavigationRailDestination>[
              for (int i = 0; i < destinations.length; i++)
                NavigationRailDestination(
                  icon: icon(i, selected: false),
                  selectedIcon: icon(i, selected: true),
                  label: Text(destinations[i].$1),
                  padding: const EdgeInsets.symmetric(vertical: 2),
                ),
            ],
          ),
          VerticalDivider(width: 1, color: p.line),
          Expanded(child: shell),
        ],
      ),
    );
  }
}
