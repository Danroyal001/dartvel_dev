/// Which router an existing Flutter app uses, and how Dartvel's pages join it.
///
/// Dartvel mounts into go_router (`dartvelGoRouter(existing:)`), auto_route
/// (`dartvelAutoRoutes(existing:)`, generated when the project depends on
/// it) and Flutter's own Navigator -- 1.0 through
/// `dartvelRouteFactory(existing:)`, 2.0 through `dartvelNavigator2_0Routes` spread into the app's
/// own RouterDelegate -- and composes with any `RouterConfig` handed to
/// `MaterialApp.router` or `CupertinoApp.router`
/// (`dartvelRouterConfig(existing:)`). Each keeps the app's own routes.
/// Another router package is named, with these.
library;

/// The routers Dartvel mounts into.
enum DVHostRouter { goRouter, autoRoute, navigator }

/// Routing packages Dartvel does not mount into, by pub name.
const Set<String> dvUnsupportedRouters = <String>{
  'beamer',
  'routemaster',
  'fluro',
  'qlevar_router',
  'vrouter',
  'get',
  'routefly',
  'modular_flutter',
  'flutter_modular',
};

/// What [dvDetectHostRouter] found.
class DVHostRouterDetection {
  const DVHostRouterDetection({this.router, this.unsupported});

  /// The router Dartvel mounts into, or null when the app uses another.
  final DVHostRouter? router;

  /// The package that routes the app when it is not one of the three.
  final String? unsupported;

  /// What adoption says about routing, in one line.
  String get message => switch (router) {
        .goRouter => 'go_router: your routes stay yours. Build the router with '
            '`dartvelGoRouter(at: \'/app\', existing: yourRoutes, redirect: '
            'yourRedirect)`; `dartvel routes` fails with DV-ADOPT-002 when a '
            'GoRoute path is also a generated page route.',
        .autoRoute => 'auto_route: your routes stay yours. Return '
            '`dartvelAutoRoutes(at: \'/app\', existing: yourRoutes)` from '
            'your router\'s routes; Dartvel\'s run in a router of their own '
            'under /app, with their own guards.',
        .navigator => 'Navigator: your routes stay yours. On Navigator 1.0, '
            '`onGenerateRoute: dartvelRouteFactory(at: \'/app\', existing: '
            'yourOnGenerateRoute)`; on Navigator 2.0, add '
            '`...dartvelNavigator2_0Routes(at: \'/app\')` to the route table your '
            'RouterDelegate builds; with MaterialApp.router, '
            '`dartvelRouterConfig(at: \'/app\', existing: yourConfig)`.',
        null => '$unsupported: Dartvel does not mount into $unsupported. It '
            'mounts into go_router (dartvelGoRouter), auto_route '
            '(dartvelAutoRoutes), Flutter\'s own Navigator 1.0 '
            '(dartvelRouteFactory) and 2.0 (dartvelNavigator2_0Routes), and composes with '
            'a RouterConfig (dartvelRouterConfig). Route the screens that show '
            'Dartvel pages through one of those.',
      };
}

/// The router the app whose pubspec is [pubspec] uses.
///
/// go_router and auto_route are named by their dependency. A dependency on a
/// routing package Dartvel does not mount into is named as such, even beside
/// one it does, because that is the router the app's screens are on. With
/// none, the app routes with Flutter's own Navigator.
DVHostRouterDetection dvDetectHostRouter(Map<Object?, Object?> pubspec) {
  final Set<String> deps = <String>{
    for (final String section in <String>['dependencies', 'dev_dependencies'])
      if (pubspec[section] is Map)
        for (final Object? key in (pubspec[section] as Map).keys) '$key',
  };
  for (final String name in dvUnsupportedRouters) {
    if (deps.contains(name)) return DVHostRouterDetection(unsupported: name);
  }
  if (deps.contains('auto_route')) {
    return const DVHostRouterDetection(router: .autoRoute);
  }
  if (deps.contains('go_router')) {
    return const DVHostRouterDetection(router: .goRouter);
  }
  return const DVHostRouterDetection(router: .navigator);
}
