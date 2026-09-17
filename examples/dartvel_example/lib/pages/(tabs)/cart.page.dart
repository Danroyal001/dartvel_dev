import 'package:flutter/material.dart';

import '../../components/shop_ui.dart';
import '../../dartvel_client/dartvel_client.dart';
import '../../shop/cart.dart';
import '../../theme/palette.dart';

/// The bag: what is in it, what it costs, and the way to checkout.
@DVPage(title: 'Bag', showAppBar: true)
@pragma('vm:entry-point')
Widget _cartPage(BuildContext context) => (() {
  final Cart cart = context.global<Cart>();
  final Palette p = Palette.of(context);

  return WatchModels<Product>(
    watch: Product.watch,
    builder: (BuildContext context, List<Product>? catalog) {
      if (catalog == null) {
        return const ShopScroll(children: <Widget>[LoadingTiles(count: 2)]);
      }
      final List<CartLine> lines = cart.linesIn(catalog);
      if (lines.isEmpty) {
        return ShopScroll(
          maxWidth: readingMaxWidth,
          children: <Widget>[
            const PageHeading('Your bag'),
            EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Your bag is empty',
              message:
                  'Pick a coffee from this week’s shelf. We roast on '
                  'Tuesday and ship the next morning.',
              action: FilledButton(
                onPressed: () => DV.Navigation.navigate(DVRoutes.index),
                child: const Text('Browse coffee'),
              ),
            ),
          ],
        );
      }
      final int shipping = cart.shippingCentsFor(catalog);
      final int subtotal = cart.subtotalCents(catalog);
      return ShopScroll(
        maxWidth: readingMaxWidth,
        children: <Widget>[
          PageHeading(
            'Your bag',
            subtitle:
                '${cart.count} ${cart.count == 1 ? 'bag' : 'bags'} of coffee',
          ),
          DVBox.list([
            for (final CartLine line in lines)
              DVBox.row(
                [
                  BagThumb(line.coffee),
                  Expanded(
                    child: DVBox.list([
                      DVText(line.coffee.name).modifier(p.headline),
                      DVText(
                        '${line.coffee.origin} · ${line.coffee.weightGrams} g',
                      ).modifier(p.muted.fontSize(13).maxLines(1)),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: QuantityStepper(
                          key: Key('bag-quantity-${line.coffee.slug}'),
                          value: line.quantity,
                          min: 0,
                          label: '${line.coffee.name} quantity',
                          onChanged: (int next) => updateCart(
                            (Cart c) => c.setQuantity(line.coffee.slug, next),
                          ),
                        ),
                      ),
                    ], spacing: 6),
                  ),
                  DVText(formatPrice(line.totalCents)).modifier(p.headline),
                ],
                spacing: 14,
                crossAlign: DVCrossAlign.start,
              ).modifier(cardStyle(p, padding: 12)),
          ], spacing: 12),
          DVBox.list([
            SummaryLine('Subtotal', formatPrice(subtotal)),
            SummaryLine(
              'Shipping',
              shipping == 0 ? 'Free' : formatPrice(shipping),
              note: shipping == 0
                  ? null
                  : 'Add ${formatPrice(freeShippingFromCents - subtotal)} more for free shipping',
            ),
            Divider(color: p.line),
            SummaryLine(
              'Total',
              formatPrice(subtotal + shipping),
              strong: true,
            ),
            FilledButton(
              key: const Key('go-to-checkout'),
              onPressed: () => DV.Navigation.navigate(DVRoutes.checkout),
              child: const Text('Checkout'),
            ),
          ], spacing: 12).modifier(cardStyle(p, padding: 20)),
        ],
      );
    },
  );
})();
