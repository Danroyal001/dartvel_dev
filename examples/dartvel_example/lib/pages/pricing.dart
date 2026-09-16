import 'package:flutter/material.dart';

import '../components/shop_ui.dart';
import '../dartvel_client/dartvel_client.dart';
import '../theme/palette.dart';

// The sitemap argument is here rather than in a test fixture because it is a
// nested call inside the annotation, and every parser of `@DVPage(...)` used
// to stop at its first close parenthesis -- which dropped this page out of
// the router entirely, with the build still succeeding. A page in the
// example is read by the real generator and then compiled, so that cannot
// come back quietly.
@DVPage(
  title: 'Coffee Club',
  showAppBar: true,
  sitemap: DVPageSitemap(
    priority: 0.8,
    changeFrequency: DVSitemapChangeFrequency.weekly,
  ),
)
@pragma('vm:entry-point')
Widget _pricingPage(BuildContext context) => (() {
      final Palette p = Palette.of(context);
      // The price the model declares, read rather than repeated. A static the
      // generator emits and nothing calls is the same gap the annotation had
      // before it was emitted at all -- this page is where a compiler and a
      // screenshot both see it.
      final int club = Product.nativePrice?.amount.toInt() ?? 2499;
      return ShopScroll(children: <Widget>[
        const PageHeading(
          'Coffee Club',
          subtitle: 'Fresh coffee on a schedule. Skip, pause or cancel from '
              'your account whenever you like.',
        ),
        ResponsiveGrid(minTileWidth: 260, maxColumns: 3, children: <Widget>[
          const PlanCard(
            name: 'Occasional',
            price: 'Pay as you go',
            points: <String>['Order any coffee', 'Free shipping over \$30'],
            featured: false,
          ),
          PlanCard(
            name: 'Fortnightly',
            price: '${formatPrice(club)} a month',
            points: const <String>[
              'Two 250 g bags a month',
              'Roaster’s choice or your pick',
              'Always free shipping',
            ],
            featured: true,
          ),
          PlanCard(
            name: 'Office',
            price: '${formatPrice(club * 3)} a month',
            points: const <String>[
              'Two 1 kg bags a month',
              'Espresso or filter roast',
              'A named contact at the roastery',
            ],
            featured: false,
          ),
        ]),
        DVText('Prices in ${Product.nativePrice?.currency ?? 'USD'}.')
            .modifier(p.muted.fontSize(13)),
      ]);
    })();

class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.name,
    required this.price,
    required this.points,
    required this.featured,
  });

  final String name;
  final String price;
  final List<String> points;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return DVBox.list([
      DVBox.row([
        Expanded(child: DVText(name).modifier(p.title.semanticHeading(2))),
        if (featured)
          const DVText('Most popular').modifier(
            p.overline
                .color(p.accent)
                .paddingSymmetric(horizontal: 8, vertical: 4)
                .rounded(8)
                .backgroundColor(p.accentSoft),
          ),
      ], crossAlign: DVCrossAlign.center),
      DVText(price).modifier(p.headline.fontSize(20)),
      for (final String point in points)
        DVBox.row([
          Icon(Icons.check, size: 18, color: p.success),
          Expanded(child: DVText(point).modifier(p.body)),
        ], spacing: 10),
      if (featured)
        FilledButton(
          onPressed: () => DV.Navigation.navigate(DVRoutes.account),
          child: const Text('Join the club'),
        )
      else
        OutlinedButton(
          onPressed: () => DV.Navigation.navigate(DVRoutes.index),
          child: Text(name == 'Office' ? 'Talk to us' : 'Shop coffee'),
        ),
    ], spacing: 14).modifier(
      cardStyle(p, padding: 22).border(
        Border.all(color: featured ? p.accent : p.line, width: featured ? 1.5 : 1),
      ),
    );
  }
}
