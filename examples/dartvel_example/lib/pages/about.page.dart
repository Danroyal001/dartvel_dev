import 'package:flutter/material.dart';

import '../components/shop_ui.dart';
import '../dartvel_client/dartvel_client.dart';
import '../theme/palette.dart';

/// How the shop is built, for the developer reading it: each piece of
/// Dartvel, where it is used, and the file to open.
@DVPage(title: 'Under the hood')
@pragma('vm:entry-point')
Widget _aboutPage(BuildContext context) => (() {
  final Palette p = Palette.of(context);
  return ShopScroll(
    children: <Widget>[
      const BackToShop(),
      const PageHeading(
        'Under the hood',
        overline: 'Built with Dartvel',
        subtitle:
            'Oakline is a small shop written the way a Flutter '
            'developer would write one with Dartvel. This is what each '
            'screen stands on, and where to look.',
      ),
      ResponsiveGrid(
        minTileWidth: 300,
        maxColumns: 2,
        children: <Widget>[
          for (final HoodPiece piece in hoodPieces) HoodCard(piece),
        ],
      ),
      DVBox.list([
        const SectionHeading('Also in this app'),
        DVBox.wrapLine([
          for (final (String label, DVRouteTarget to)
              in <(String, DVRouteTarget)>[
                (
                  'Notes module, mounted at /notes',
                  DV.Modules.notesRoutes.index,
                ),
                ('Responsive images', DVRoutes.gallery),
                ('Home screen widget', DVRoutes.nextShift),
                ('Config routes', DVRoutes.settings),
                ('Guarded staff screen', DVRoutes.adminReports),
                (
                  'Brew guide, a guarded dynamic route',
                  DVRoutes.blog(id: 'pour-over'),
                ),
              ])
            DVNavLink(
              to: to,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: DVText(label).modifier(p.headline.fontSize(14)),
            ),
        ], spacing: 8),
      ], spacing: 12),
      DVBox.list([
        const SectionHeading('This device'),
        DVBox.wrapLine([
          CoffeeFact('Platform', DV.Platform.currentPlatform),
          CoffeeFact('Device', DV.Platform.deviceType),
          CoffeeFact('Breakpoint', DV.Platform.breakpoint),
          CoffeeFact('Orientation', DV.Platform.orientation.name),
        ], spacing: 10),
      ], spacing: 12),
    ],
  );
})();

class const HoodPiece(
  final String title,
  final String body,
  final String file,
  final IconData icon,
);

const List<HoodPiece> hoodPieces = <HoodPiece>[
  HoodPiece(
    'Models',
    'Product and Order are @DVModel classes. The shop grid, the admin '
        'editor and the orders table are the generated List, Admin and Table.',
    'lib/models/',
    Icons.dataset_outlined,
  ),
  HoodPiece(
    'Tabs from files',
    'The four tabs are a folder with a tabs layout. Each keeps its own stack; '
        'phones get a bottom bar and wider screens a rail.',
    'lib/pages/(tabs)/_layout.dart',
    Icons.tab_outlined,
  ),
  HoodPiece(
    'Signals',
    'The roast filter and quantity are context.signal. The button price is '
        'quantity * price, a signal derived by operating on one.',
    'lib/pages/(tabs)/coffee/[slug].page.dart',
    Icons.bolt_outlined,
  ),
  HoodPiece(
    'Globals',
    'The bag, saved coffees, the account and the theme are DV.global objects. '
        'Replacing one rebuilds every screen that read it.',
    'lib/shop/cart.dart',
    Icons.public,
  ),
  HoodPiece(
    'Live order status',
    'The roastery saves the order at each step. Order.watch on the order '
        'page hears the save; nothing polls.',
    'lib/pages/(tabs)/orders/[id].page.dart',
    Icons.sensors,
  ),
  HoodPiece(
    'Guards and auth',
    'Checkout and Manage sit in a config route shell whose redirect sends '
        'a signed-out visitor to sign in through DV.Auth.',
    'lib/routes.dart',
    Icons.lock_outline,
  ),
  HoodPiece(
    'Jobs and mail',
    'Placing an order dispatches SendOrderConfirmation to a queue. Its '
        'handler sends the receipt with DV.Notifications.mail.',
    'lib/jobs/order_confirmation.dart',
    Icons.outgoing_mail,
  ),
  HoodPiece(
    'Backend functions',
    'Files under lib/backend/functions become the API, with a typed client '
        'generated for the app. The server keeps its data in SQLite.',
    'lib/backend/functions/catalog.get.dart',
    Icons.dns_outlined,
  ),
];

class const HoodCard(final HoodPiece piece, {super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return DVBox.list(
      [
        DVBox.row(
          [
            DVBox(Icon(piece.icon, size: 20, color: p.accent)).modifier(
              const DVModifier()
                  .width(38)
                  .height(38)
                  .rounded(10)
                  .align(Alignment.center)
                  .backgroundColor(p.accentSoft),
            ),
            Expanded(
              child: DVText(
                piece.title,
              ).modifier(p.headline.semanticHeading(2)),
            ),
          ],
          spacing: 12,
          crossAlign: DVCrossAlign.center,
        ),
        DVText(piece.body).modifier(p.muted),
        DVText(piece.file).modifier(
          const DVModifier()
              .fontFamily('monospace')
              .fontSize(12.5)
              .color(p.inkMuted)
              .paddingSymmetric(horizontal: 8, vertical: 4)
              .rounded(6)
              .backgroundColor(p.sunken),
        ),
      ],
      spacing: 10,
      crossAlign: DVCrossAlign.start,
    ).modifier(cardStyle(p, padding: 18));
  }
}
