import 'package:flutter/material.dart';

import '../../components/shop_ui.dart';
import '../../dartvel_client/dartvel_client.dart';
import '../../shop/cart.dart';
import '../../shop/saved.dart';

/// The coffees someone bookmarked, kept while they browse the other tabs.
@DVPage(title: 'Saved')
@pragma('vm:entry-point')
Widget _savedPage(BuildContext context) => (() {
  final SavedCoffees saved = context.global<SavedCoffees>();

  return ShopScroll(
    children: <Widget>[
      const PageHeading('Saved', subtitle: 'Coffees you want to come back to.'),
      WatchModels<Product>(
        watch: Product.watch,
        builder: (BuildContext context, List<Product>? coffees) {
          if (coffees == null) return const LoadingTiles(count: 2);
          final List<Product> mine = <Product>[
            for (final Product c in coffees)
              if (saved.contains(c.slug)) c,
          ];
          if (mine.isEmpty) {
            return EmptyState(
              icon: Icons.bookmark_border,
              title: 'Nothing saved yet',
              message:
                  'Tap Save for later on a coffee and it will wait '
                  'for you here.',
              action: FilledButton(
                onPressed: () => DV.Navigation.navigate(DVRoutes.index),
                child: const Text('Browse coffee'),
              ),
            );
          }
          return ResponsiveGrid(
            children: <Widget>[
              for (final Product coffee in mine)
                CoffeeCard(
                  coffee,
                  onOpen: () => DV.Navigation.navigate(
                    DVRoutes.coffee(slug: coffee.slug),
                  ),
                  onAdd: () => updateCart((Cart cart) => cart.add(coffee.slug)),
                ),
            ],
          );
        },
      ),
    ],
  );
})();
