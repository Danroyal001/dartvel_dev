// Routes declared in code, beside the pages under lib/pages.
//
// `dartvel routes` reads this file: each route below gets a typed target on
// DVRoutes, next to the pages' own, and the generated router mounts the list
// with them. Pages and config routes are one router and one DVRoutes.
import 'package:flutter/widgets.dart';

import 'dartvel_client/dartvel_client.dart';
import 'screens/config_screens.dart';

final List<DVRouteNode> routes = <DVRouteNode>[
  DVRoute(
    path: '/settings',
    title: 'Settings',
    builder: (BuildContext context, DVRouteState state) =>
        SettingsScreen(tab: state.query['tab']),
  ),
  DVRoute(
    path: '/team',
    title: 'Team',
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
  // Signed-out visitors are sent to the About page, a file route, by its
  // typed target.
  DVShellRoute(
    // Async, as a session check is: a deep link here shows the pending view
    // while it decides, never a blank screen.
    redirect: (BuildContext context, DVRouteState state) async {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      return DV.Auth.currentUser == null ? DVRoutes.about : null;
    },
    builder: (BuildContext context, DVRouteState state, Widget child) =>
        AdminFrame(child: child),
    routes: <DVRouteNode>[
      DVRoute(
        path: '/admin/reports',
        name: 'adminReports',
        builder: (BuildContext context, DVRouteState state) =>
            const ReportsScreen(),
      ),
    ],
  ),
];
