// Screens served by config routes (lib/routes.dart), written the way a
// go_router application already has them: ordinary widgets taking what they
// show as constructor arguments, with no annotation and no page file.
import 'package:flutter/material.dart';

import '../components/shop_ui.dart';
import '../dartvel_client/dartvel_client.dart';
import '../shop/account.dart';
import '../shop/cart.dart';
import '../shop/orders.dart';
import '../theme/palette.dart';

/// A config route's page: a bar with a way back, and the shop's body.
class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Semantics(headingLevel: 1, child: Text(title)),
      leading: DV.Navigation.canGoBack
          ? null
          : IconButton(
              tooltip: 'Shop',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => DV.Navigation.navigate(DVRoutes.index),
            ),
    ),
    body: ShopScroll(maxWidth: readingMaxWidth, children: children),
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.tab});

  final String? tab;

  static const List<String> tabs = <String>[
    'general',
    'delivery',
    'notifications',
  ];

  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    final String current = tabs.contains(tab) ? tab! : 'general';
    return ShopScreen(
      title: 'Settings',
      children: <Widget>[
        DVBox.wrapLine([
          for (final String t in tabs)
            ChoiceChip(
              key: Key('settings-$t'),
              label: Text('${t[0].toUpperCase()}${t.substring(1)}'),
              selected: t == current,
              showCheckmark: false,
              onSelected: (_) => DV.Navigation.navigate(
                DVRoutes.settings.withQuery(<String, String>{'tab': t}),
              ),
            ),
        ], spacing: 8),
        DVText('Showing $current settings').modifier(p.muted),
        Material(
          color: p.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: p.line),
          ),
          child: DVBox.list([
            for (final (String title, String subtitle, bool on)
                in switch (current) {
                  'delivery' => <(String, String, bool)>[
                    ('Leave with a neighbour', 'If nobody is in', true),
                    (
                      'Letterbox-sized bags',
                      'Every 250 g bag fits through a door',
                      true,
                    ),
                  ],
                  'notifications' => <(String, String, bool)>[
                    (
                      'Roast day',
                      'When your order goes into the roaster',
                      true,
                    ),
                    ('Shipping', 'When it leaves us, with tracking', true),
                    ('New coffees', 'At most once a fortnight', false),
                  ],
                  _ => <(String, String, bool)>[
                    (
                      'Grind for me',
                      'Whole bean unless you choose a grind',
                      false,
                    ),
                    ('Use metric weights', 'Grams rather than ounces', true),
                  ],
                })
              SwitchListTile(
                value: on,
                onChanged: (_) {},
                title: Text(title),
                subtitle: Text(subtitle),
              ),
          ]).modifier(const DVModifier().paddingSymmetric(vertical: 6)),
        ),
        const DVBox.wrapLine(<Widget>[
          DVNavLink(
            key: Key('link-team'),
            to: DVRoutes.team,
            child: DVText('The roasters'),
          ),
          DVNavLink(
            key: Key('link-about-from-settings'),
            to: DVRoutes.about,
            child: DVText('Under the hood'),
          ),
        ], spacing: 12),
      ],
    );
  }
}

/// The people behind the shop.
class TeamScreen extends StatelessWidget {
  const TeamScreen({super.key});

  static const Map<String, (String, String)> members =
      <String, (String, String)>{
        'amara': ('Amara Nwosu', 'Head roaster'),
        'jonas': ('Jonas Berg', 'Green coffee buyer'),
        'lucia': ('Lucía Ortega', 'Packing and customer care'),
      };

  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return ShopScreen(
      title: 'The roasters',
      children: <Widget>[
        const DVText(
          'Three people, one Probat roaster, and a small warehouse by '
          'the harbour.',
        ).modifier(p.muted.fontSize(16)),
        DVBox.list([
          for (final MapEntry<String, (String, String)> m in members.entries)
            DVNavLink(
              key: Key('link-member-${m.key}'),
              to: DVRoutes.teamMember(member: m.key),
              semanticLabel: m.value.$1,
              child: ListRow(
                icon: Icons.person_outline,
                title: m.value.$1,
                subtitle: m.value.$2,
                trailing: Icon(Icons.chevron_right, color: p.inkFaint),
              ),
            ),
        ], spacing: 2).modifier(cardStyle(p, padding: 8)),
      ],
    );
  }
}

class TeamMemberScreen extends StatelessWidget {
  const TeamMemberScreen({super.key, required this.member});

  final String member;

  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    final (String name, String role) =
        TeamScreen.members[member] ?? (member, 'Oakline Coffee');
    return ShopScreen(
      title: name,
      children: <Widget>[
        DVBox.row(
          [
            DVBox(
              DVText(
                name.characters.first,
              ).modifier(p.display.color(p.onAccent)),
            ).modifier(
              const DVModifier()
                  .width(72)
                  .height(72)
                  .rounded(36)
                  .align(Alignment.center)
                  .backgroundColor(p.accent),
            ),
            Expanded(
              child: DVBox.list([
                DVText(name).modifier(p.title.semanticHeading(2)),
                DVText(role).modifier(p.muted),
              ], spacing: 4),
            ),
          ],
          spacing: 18,
          crossAlign: DVCrossAlign.center,
        ),
        DVText(
          'Ask $name anything about the coffee: hello@oakline.coffee',
        ).modifier(p.body),
      ],
    );
  }
}

/// Where a signed-in person pays.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool _placing = false;

  Future<void> _place(List<Product> catalog) async {
    setState(() => _placing = true);
    final Order order = await placeOrder(
      cart: currentCart,
      catalog: catalog,
      email: currentAccount.email,
    );
    DV.Navigation.navigate(DVRoutes.ordersId(id: order.id));
  }

  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    final Cart cart = context.global<Cart>();
    final Account account = context.global<Account>();
    return ShopScreen(
      title: 'Checkout',
      children: <Widget>[
        WatchModels<Product>(
          watch: Product.watch,
          builder: (BuildContext context, List<Product>? catalog) {
            if (catalog == null) return const LoadingTiles(count: 1);
            if (cart.linesIn(catalog).isEmpty) {
              return EmptyState(
                icon: Icons.shopping_bag_outlined,
                title: 'Nothing to check out',
                message: 'Your bag is empty.',
                action: FilledButton(
                  onPressed: () => DV.Navigation.navigate(DVRoutes.index),
                  child: const Text('Browse coffee'),
                ),
              );
            }
            final int shipping = cart.shippingCentsFor(catalog);
            return DVBox.list([
              DVBox.list([
                const SectionHeading('Deliver to'),
                DVText(account.name).modifier(p.headline),
                const DVText(
                  '14 Quay Street, Bristol BS1 4DB',
                ).modifier(p.muted),
                DVText(account.email).modifier(p.muted),
              ], spacing: 6).modifier(cardStyle(p, padding: 20)),
              DVBox.list([
                const SectionHeading('Order'),
                for (final CartLine line in cart.linesIn(catalog))
                  SummaryLine(
                    '${line.quantity} × ${line.coffee.name}',
                    formatPrice(line.totalCents),
                  ),
                SummaryLine(
                  'Shipping',
                  shipping == 0 ? 'Free' : formatPrice(shipping),
                ),
                Divider(color: p.line),
                SummaryLine(
                  'Total',
                  formatPrice(cart.totalCents(catalog)),
                  strong: true,
                ),
                FilledButton(
                  key: const Key('place-order'),
                  onPressed: _placing ? null : () => _place(catalog),
                  child: Text(_placing ? 'Placing order…' : 'Place order'),
                ),
                const DVText(
                  'This demo takes no payment.',
                ).modifier(p.muted.fontSize(13)),
              ], spacing: 12).modifier(cardStyle(p, padding: 20)),
            ], spacing: 16);
          },
        ),
      ],
    );
  }
}

/// Staff only: the catalogue and the orders, from the generated admin and
/// table.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return ShopScreen(
      title: 'Manage the shop',
      children: <Widget>[
        const DVText('Reports').modifier(p.title.semanticHeading(2)),
        WatchModels<Order>(
          watch: Order.watch,
          builder: (BuildContext context, List<Order>? orders) {
            if (orders == null) return const LoadingTiles(count: 1);
            final int revenue = orders.fold(
              0,
              (int sum, Order o) => sum + o.totalCents,
            );
            return DVBox.list([
              DVBox.wrapLine([
                CoffeeFact('Orders', '${orders.length}'),
                CoffeeFact('Revenue', formatPrice(revenue)),
                CoffeeFact(
                  'In progress',
                  '${orders.where((Order o) => o.status != 'delivered').length}',
                ),
              ], spacing: 10),
              if (orders.isNotEmpty)
                // Wider than a phone: the generated table keeps its columns and
                // scrolls sideways rather than wrapping every cell.
                DVBox(
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: 980, child: Order.Table(orders)),
                  ),
                ).modifier(cardStyle(p, padding: 8)),
            ], spacing: 16);
          },
        ),
        const DVText('Coffees').modifier(p.title.semanticHeading(2)),
        // The whole catalogue editor: list, form, save and delete, generated
        // from the model and asked of ProductPolicy for each action.
        DVBox(
          SizedBox(height: 560, child: Product.Admin(as: currentAccount.user)),
        ).modifier(cardStyle(p, padding: 12)),
      ],
    );
  }
}

/// The frame around the routes that need a sign-in: nothing but the page.
class SignedInFrame extends StatelessWidget {
  const SignedInFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
