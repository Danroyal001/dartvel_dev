import 'package:flutter/widgets.dart';

import 'dartvel_client/dartvel_client.dart';

// docs:start routing-config
// lib/routes.dart, read by dartvel routes. Each route here gets a typed
// target on DVRoutes beside the pages' own, and the generated router mounts
// the list with them: one router, one DVRoutes, whichever way a route was
// declared.
final List<DVRouteNode> routes = <DVRouteNode>[
  DVRoute(
    path: '/settings',
    title: 'Settings',
    builder: (BuildContext context, DVRouteState state) =>
        SettingsScreen(tab: state.query['tab']),
  ),
  DVRoute(
    path: '/roasters',
    title: 'The roasters',
    builder: (BuildContext context, DVRouteState state) => const RoastersScreen(),
    routes: <DVRouteNode>[
      DVRoute(
        // Nested, so this is /roasters/:person. The name is given because
        // /roasters/:person would derive DVRoutes.roasters, which the parent
        // already is.
        path: ':person',
        name: 'roaster',
        builder: (BuildContext context, DVRouteState state) =>
            RoasterScreen(person: state.params['person']!),
      ),
    ],
  ),
];
// docs:end

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.tab});

  final String? tab;

  @override
  Widget build(BuildContext context) => DVText(tab ?? 'Settings');
}

class RoastersScreen extends StatelessWidget {
  const RoastersScreen({super.key});

  @override
  Widget build(BuildContext context) => const DVText('The roasters');
}

class RoasterScreen extends StatelessWidget {
  const RoasterScreen({super.key, required this.person});

  final String person;

  @override
  Widget build(BuildContext context) => DVText(person);
}
