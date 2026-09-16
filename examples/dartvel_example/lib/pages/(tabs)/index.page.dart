import 'package:flutter/material.dart';

import '../../components/shop_ui.dart';
import '../../dartvel_client/dartvel_client.dart';
import '../../shop/account.dart';
import '../../shop/cart.dart';
import '../../theme/palette.dart';

/// The shop: this week's coffees, straight from the store.
@DVPage(title: 'Shop')
@pragma('vm:entry-point')
Widget _shopPage(BuildContext context) => (() {
      // Which roast the grid shows. A signal: tapping a chip rebuilds this
      // page and nothing else.
      final roast = context.signal('all');
      final Palette p = Palette.of(context);
      final Account account = context.global<Account>();
      final int bagCount = context.global<Cart>().count;

      return ShopScroll(children: <Widget>[
        ShopTopBar(
          bagCount: bagCount,
          heading: PageHeading(
            account.signedIn
                ? 'Good to see you, ${account.firstName}'
                : 'This week’s coffee',
            subtitle: 'Roasted on Tuesday, at your door by Friday. '
                'Shipping is free over \$30.',
          ),
        ),
        const CoffeeClubBanner(),
        DVBox.list([
          const SectionHeading('The shelf'),
          DVBox.wrapLine([
            for (final String option in <String>['all', 'light', 'medium', 'dark'])
              ChoiceChip(
                key: Key('roast-$option'),
                label: Text(option == 'all'
                    ? 'All roasts'
                    : '${option[0].toUpperCase()}${option.substring(1)}'),
                selected: roast.value == option,
                showCheckmark: false,
                side: BorderSide(color: p.line),
                backgroundColor: p.surface,
                selectedColor: p.accentSoft,
                labelStyle: TextStyle(
                  color: roast.value == option ? p.ink : p.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (_) => roast.value = option,
              ),
          ], spacing: 8),
          WatchModels<Product>(
            watch: Product.watch,
            builder: (BuildContext context, List<Product>? coffees) {
              if (coffees == null) return const LoadingTiles();
              final List<Product> shown = <Product>[
                for (final Product c in coffees)
                  if (c.published && (roast.value == 'all' || c.roast == roast.value)) c,
              ];
              if (shown.isEmpty) {
                return EmptyState(
                  icon: Icons.coffee_outlined,
                  title: 'Nothing on the shelf',
                  message: 'No ${roast.value} roasts this week. The next '
                      'roast is on Tuesday.',
                  action: TextButton(
                    onPressed: () => roast.value = 'all',
                    child: const Text('Show every roast'),
                  ),
                );
              }
              return ResponsiveGrid(children: <Widget>[
                for (final Product coffee in shown)
                  CoffeeCard(
                    coffee,
                    onOpen: () => DV.Navigation.navigate(
                      DVRoutes.coffee(slug: coffee.slug),
                    ),
                    onAdd: () {
                      updateCart((Cart cart) => cart.add(coffee.slug));
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(
                          content: Text('${coffee.name} is in your bag'),
                          duration: const Duration(seconds: 2),
                        ));
                    },
                  ),
              ]);
            },
          ),
        ], spacing: 16),
      ]);
    })();
