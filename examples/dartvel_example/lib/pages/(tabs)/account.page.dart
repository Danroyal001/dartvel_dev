import 'package:flutter/material.dart';

import '../../components/shop_ui.dart';
import '../../dartvel_client/dartvel_client.dart';
import '../../shop/account.dart';
import '../../shop/appearance.dart';
import '../../theme/palette.dart';

/// The person, their preferences, and the way behind the counter.
@DVPage(title: 'Account')
@pragma('vm:entry-point')
Widget _accountPage(BuildContext context) => (() {
      final Account account = context.global<Account>();
      final ThemeMode mode = context.global<Appearance>().mode;
      final Palette p = Palette.of(context);

      return ShopScroll(children: <Widget>[
        const PageHeading('Account'),
        if (account.signedIn)
          DVBox.row([
            DVBox(DVText(account.name.characters.first).modifier(
              p.title.color(p.onAccent),
            )).modifier(
              const DVModifier()
                  .width(52)
                  .height(52)
                  .rounded(26)
                  .align(Alignment.center)
                  .backgroundColor(p.accent),
            ),
            Expanded(
              child: DVBox.list([
                DVText(account.name).modifier(p.headline.fontSize(17)),
                DVText(account.email).modifier(p.muted),
              ], spacing: 2),
            ),
            const OutlinedButton(
              key: Key('sign-out'),
              onPressed: signOut,
              child: Text('Sign out'),
            ),
          ], spacing: 14, crossAlign: DVCrossAlign.center)
              .modifier(cardStyle(p, padding: 18))
        else
          DVBox.list([
            const DVText('Sign in to order').modifier(p.title.semanticHeading(2)),
            const DVText('Follow your orders from the roaster to your door, and '
                    'keep your saved coffees on every device.')
                .modifier(p.muted),
            FilledButton(
              key: const Key('account-sign-in'),
              onPressed: () => DV.Navigation.navigate(
                const DVRouteTarget('/sign-in?from=/account'),
              ),
              child: const Text('Sign in'),
            ),
          ], spacing: 10).modifier(cardStyle(p, padding: 20)),
        DVBox.list([
          const SectionHeading('Appearance'),
          SegmentedButton<ThemeMode>(
            key: const Key('appearance'),
            showSelectedIcon: false,
            segments: const <ButtonSegment<ThemeMode>>[
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                label: Text('Automatic'),
              ),
              ButtonSegment<ThemeMode>(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment<ThemeMode>(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: <ThemeMode>{mode},
            onSelectionChanged: (Set<ThemeMode> next) => setAppearance(next.first),
          ),
        ], spacing: 12),
        DVBox.list([
          const SectionHeading('More'),
          DVBox.list([
            ListRow(
              icon: Icons.workspace_premium_outlined,
              title: 'Coffee Club',
              subtitle: 'A fresh bag every two weeks',
              onTap: () => DV.Navigation.navigate(DVRoutes.pricing),
            ),
            ListRow(
              icon: Icons.menu_book_outlined,
              title: 'Brew guides',
              subtitle: 'Pour-over, espresso and cold brew',
              onTap: () => DV.Navigation.navigate(DVRoutes.blog(id: 'pour-over')),
            ),
            ListRow(
              icon: Icons.groups_outlined,
              title: 'The roasters',
              subtitle: 'Who roasts, packs and answers your emails',
              onTap: () => DV.Navigation.navigate(DVRoutes.team),
            ),
            ListRow(
              icon: Icons.tune,
              title: 'Settings',
              subtitle: 'Notifications and delivery',
              onTap: () => DV.Navigation.navigate(DVRoutes.settings),
            ),
            ListRow(
              icon: Icons.inventory_2_outlined,
              title: 'Manage the shop',
              subtitle: 'Edit coffees and see orders — staff only',
              onTap: () => DV.Navigation.navigate(DVRoutes.adminReports),
            ),
            ListRow(
              icon: Icons.code,
              title: 'Under the hood',
              subtitle: 'How this app is built with Dartvel',
              onTap: () => DV.Navigation.navigate(DVRoutes.about),
            ),
          ], spacing: 2).modifier(cardStyle(p, padding: 8)),
        ], spacing: 12),
      ]);
    })();
