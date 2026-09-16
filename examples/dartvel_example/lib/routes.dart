// Routes declared in code, beside the pages under lib/pages.
//
// `dartvel routes` reads this file: each route below gets a typed target on
// DVRoutes, next to the pages' own, and the generated router mounts the list
// with them. Pages and config routes are one router and one DVRoutes.
import 'package:flutter/widgets.dart';

import 'dartvel_client/dartvel_client.dart';
import 'screens/config_screens.dart';
import 'shop/account.dart';

final List<DVRouteNode> routes = <DVRouteNode>[
  DVRoute(
    path: '/settings',
    title: 'Settings',
    builder: (BuildContext context, DVRouteState state) =>
        SettingsScreen(tab: state.query['tab']),
  ),
  DVRoute(
    path: '/team',
    title: 'The roasters',
    builder: (BuildContext context, DVRouteState state) => const TeamScreen(),
    routes: <DVRouteNode>[
      DVRoute(
        path: ':member',
        // /team/:member would derive DVRoutes.team, which /team already is.
        name: 'teamMember',
        builder: (BuildContext context, DVRouteState state) =>
            TeamMemberScreen(member: state.params['member']!),
      ),
    ],
  ),
  // Checkout and the staff screens need somebody signed in. A signed-out
  // visitor is sent to sign in, with the way back in the query.
  DVShellRoute(
    // Async, as a session check is: a deep link here shows the pending view
    // while it decides, never a blank screen.
    redirect: (BuildContext context, DVRouteState state) async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return currentAccount.signedIn
          ? null
          : DVRouteTarget('/sign-in?from=${Uri.encodeQueryComponent(state.path)}');
    },
    builder: (BuildContext context, DVRouteState state, Widget child) =>
        SignedInFrame(child: child),
    routes: <DVRouteNode>[
      DVRoute(
        path: '/checkout',
        title: 'Checkout',
        builder: (BuildContext context, DVRouteState state) =>
            const CheckoutScreen(),
      ),
      DVRoute(
        path: '/admin/reports',
        name: 'adminReports',
        title: 'Manage the shop',
        builder: (BuildContext context, DVRouteState state) =>
            const ReportsScreen(),
      ),
    ],
  ),
];
