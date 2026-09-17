import 'package:flutter/material.dart';

import '../../../components/shop_ui.dart';
import '../../../dartvel_client/dartvel_client.dart';
import '../../../shop/cart.dart';
import '../../../shop/saved.dart';
import '../../../theme/palette.dart';

/// One coffee: its story, what it tastes like, and how many bags.
///
/// Pushed over the shop inside the Shop tab, so back returns to the grid.
@DVPage(title: 'Coffee', showAppBar: true)
@pragma('vm:entry-point')
Widget _coffeePage(BuildContext context) => (() {
  final String slug = context.dvParams['slug'] ?? '';
  final quantity = context.signal(1);
  final Palette p = Palette.of(context);
  final bool saved = context.global<SavedCoffees>().contains(slug);

  return WatchModels<Product>(
    watch: Product.watch,
    builder: (BuildContext context, List<Product>? coffees) {
      if (coffees == null) {
        return const ShopScroll(children: <Widget>[LoadingTiles(count: 1)]);
      }
      final Product? coffee = coffees
          .where((Product c) => c.slug == slug)
          .firstOrNull;
      if (coffee == null) {
        return ShopScroll(
          children: <Widget>[
            EmptyState(
              icon: Icons.search_off,
              title: 'That coffee has sold out',
              message:
                  'It is not on the shelf any more. Have a look at '
                  'what is roasting this week.',
              action: FilledButton(
                onPressed: () => DV.Navigation.navigate(DVRoutes.index),
                child: const Text('Back to the shop'),
              ),
            ),
          ],
        );
      }

      // Price times quantity, as a signal of its own: the button's
      // label follows the stepper without being told to.
      final total = quantity * coffee.priceCents;
      final bool wide = MediaQuery.sizeOf(context).width >= 760;

      final Widget details = DVBox.list([
        PageHeading(
          coffee.name,
          overline: coffee.origin,
          subtitle: coffee.notes,
        ),
        DVText(coffee.description).modifier(p.body.fontSize(16)),
        DVBox.wrapLine([
          CoffeeFact(
            'Roast',
            '${coffee.roast[0].toUpperCase()}${coffee.roast.substring(1)}',
          ),
          CoffeeFact('Bag', '${coffee.weightGrams} g'),
          CoffeeFact('Price', formatPrice(coffee.priceCents)),
        ], spacing: 10),
        Divider(color: p.line),
        DVBox.row(
          [
            QuantityStepper(
              value: quantity.value,
              onChanged: (int next) => quantity.value = next,
            ),
            Expanded(
              child: FilledButton(
                key: const Key('add-to-bag'),
                onPressed: () {
                  updateCart(
                    (Cart cart) => cart.add(coffee.slug, quantity.read()),
                  );
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                          '${quantity.read()} × ${coffee.name} added to your bag',
                        ),
                        action: SnackBarAction(
                          label: 'View bag',
                          onPressed: () =>
                              DV.Navigation.navigate(DVRoutes.cart),
                        ),
                      ),
                    );
                },
                child: Text('Add to bag · ${formatPrice(total.value.toInt())}'),
              ),
            ),
          ],
          spacing: 12,
          crossAlign: DVCrossAlign.center,
        ),
        OutlinedButton.icon(
          key: const Key('save-coffee'),
          onPressed: () => toggleSaved(coffee.slug),
          icon: Icon(
            saved ? Icons.bookmark : Icons.bookmark_border,
            color: saved ? p.accent : p.inkMuted,
          ),
          label: Text(saved ? 'Saved' : 'Save for later'),
        ),
      ], spacing: 20);

      return ShopScroll(
        children: <Widget>[
          if (wide)
            DVBox.row(
              [
                Expanded(child: BagArt(coffee, height: 460, large: true)),
                Expanded(child: details),
              ],
              spacing: 40,
              crossAlign: DVCrossAlign.start,
            )
          else ...<Widget>[BagArt(coffee, height: 220, large: true), details],
        ],
      );
    },
  );
})();
