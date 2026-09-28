/// Which router an existing Flutter app uses, and how Dartvel's pages join it.
///
/// Dartvel mounts into exactly three: go_router (`dartvelRoutes(at:)`),
/// auto_route (`dartvelAutoRoutes(at:)`, generated when the project depends
/// on it) and Flutter's own Navigator -- 1.0 through `dartvelOnGenerateRoute`,
/// 2.0 through `dartvelPageFor`. Any other router is named, with the three
/// it could be.
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
        .goRouter => 'go_router: your routes stay yours. Mount Dartvel\'s with '
            '`GoRouter(routes: [...yours, ...dartvelRoutes(at: \'/app\')])`; '
            '`dartvel routes` fails with DV-ADOPT-002 when a GoRoute path is '
            'also a generated page route.',
        .autoRoute => 'auto_route: your routes stay yours. Mount Dartvel\'s '
            'with `routes: [...yours, ...dartvelAutoRoutes(at: \'/app\')]`; '
            'they run in a router of their own under /app, with their own '
            'guards.',
        .navigator => 'Navigator: your routes stay yours. On Navigator 1.0, '
            '`onGenerateRoute: (s) => dartvelOnGenerateRoute(s, at: \'/app\') '
            '?? yours(s)`; on Navigator 2.0, put `dartvelPageFor(uri, at: '
            '\'/app\')` in your pages.',
        null => '$unsupported: Dartvel does not mount into $unsupported. It '
            'mounts into go_router (dartvelRoutes), auto_route '
            '(dartvelAutoRoutes) and Flutter\'s own Navigator, 1.0 '
            '(dartvelOnGenerateRoute) or 2.0 (dartvelPageFor). Route the '
            'screens that show Dartvel pages through one of those three.',
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
