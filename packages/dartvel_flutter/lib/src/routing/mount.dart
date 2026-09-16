/// Dartvel's routes inside an application that already has a `GoRouter`.
///
/// Adopting Dartvel must not mean handing over the router. A host keeps its
/// own `GoRouter`, its routes, its redirects and every `context.go` it has,
/// and mounts the generated routes into it -- beside its own at the root, or
/// under a prefix such as `/app`. The generated `dartvelRoutes(at: ...)` calls
/// [dvMountRoutes]; the host passes the result into its `routes:` and calls
/// `DVNavigation.attach(router)`.
///
/// Under a prefix every Dartvel path moves: each top-level route, each shell
/// branch's initial location, and every location a Dartvel redirect returns,
/// so a guard written as `return '/login'` still lands on Dartvel's sign-in
/// page. `DV.Navigation` places a target under the prefix when Dartvel serves
/// it and hands it to the host router as it is when not.
library dartvel_flutter.routing.mount;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart' show dvRoutesOverlap;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

String _mountedAt = '/';
List<String> _owned = const <String>[];

/// Where the routes were last mounted, `/` when at the root.
String get dvMountPoint => _mountedAt;

/// [routes] mounted at [at], for a host `GoRouter`'s `routes:`.
///
/// [at] is `/` or a path with no trailing slash (`/app`). Records the mount
/// for `DVNavigation.locationOf`.
List<RouteBase> dvMountRoutes(List<RouteBase> routes, {String at = '/'}) {
  if (!at.startsWith('/') || (at.length > 1 && at.endsWith('/'))) {
    throw ArgumentError.value(
      at,
      'at',
      "is not a mount point: write '/' or a path such as '/app'",
    );
  }
  _owned = <String>[for (final RouteBase route in routes) ..._paths(route, '')];
  _mountedAt = at;
  if (at == '/') return routes;
  return <RouteBase>[for (final RouteBase route in routes) _top(route, at)];
}

/// Forgets the mount. For tests, and a host that unmounts.
void dvResetMount() {
  _mountedAt = '/';
  _owned = const <String>[];
}

/// The location to hand the router for Dartvel [path]: under the mount point
/// when Dartvel serves the path, unchanged when it does not.
String dvMountedLocation(String path) {
  if (_mountedAt == '/') return path;
  final Uri uri = Uri.parse(path);
  if (!uri.path.startsWith('/')) return path;
  final bool owned = _owned.any(
    (String pattern) => dvRoutesOverlap(uri.path, pattern),
  );
  if (!owned) return path;
  final String joined = uri.path == '/' ? _mountedAt : '$_mountedAt${uri.path}';
  return uri.replace(path: joined).toString();
}

Iterable<String> _paths(RouteBase route, String parent) sync* {
  if (route is GoRoute) {
    final String full = route.path.startsWith('/')
        ? route.path
        : parent == '/'
        ? '/${route.path}'
        : '$parent/${route.path}';
    yield full;
    for (final RouteBase child in route.routes) {
      yield* _paths(child, full);
    }
  } else {
    for (final RouteBase child in route.routes) {
      yield* _paths(child, parent);
    }
  }
}

GoRouterRedirect? _redirect(GoRouterRedirect? redirect) {
  if (redirect == null) return null;
  return (BuildContext context, GoRouterState state) {
    final FutureOr<String?> to = redirect(context, state);
    if (to is Future<String?>) {
      return to.then(
        (String? location) =>
            location == null ? null : dvMountedLocation(location),
      );
    }
    return to == null ? null : dvMountedLocation(to);
  };
}

/// A route whose path is absolute: top level, or directly inside a shell.
RouteBase _top(RouteBase route, String at) {
  if (route is GoRoute) {
    return _goRoute(
      route,
      path: route.path == '/' ? at : '$at${route.path}',
      at: at,
    );
  }
  return _shell(route, at);
}

GoRoute _goRoute(GoRoute route, {required String path, required String at}) =>
    GoRoute(
      path: path,
      name: route.name,
      builder: route.builder,
      pageBuilder: route.pageBuilder,
      parentNavigatorKey: route.parentNavigatorKey,
      redirect: _redirect(route.redirect),
      onExit: route.onExit,
      routes: <RouteBase>[
        for (final RouteBase child in route.routes)
          child is GoRoute
              ? _goRoute(child, path: child.path, at: at)
              : _shell(child, at),
      ],
    );

RouteBase _shell(RouteBase route, String at) {
  if (route is StatefulShellRoute) {
    return StatefulShellRoute(
      redirect: _redirect(route.redirect),
      builder: route.builder,
      pageBuilder: route.pageBuilder,
      navigatorContainerBuilder: route.navigatorContainerBuilder,
      parentNavigatorKey: route.parentNavigatorKey,
      restorationScopeId: route.restorationScopeId,
      branches: <StatefulShellBranch>[
        for (final StatefulShellBranch branch in route.branches)
          StatefulShellBranch(
            navigatorKey: branch.navigatorKey,
            initialLocation: branch.initialLocation == null
                ? null
                : dvMountedLocation(branch.initialLocation!),
            restorationScopeId: branch.restorationScopeId,
            observers: branch.observers,
            preload: branch.preload,
            routes: <RouteBase>[
              for (final RouteBase child in branch.routes) _top(child, at),
            ],
          ),
      ],
    );
  }
  if (route is ShellRoute) {
    return ShellRoute(
      redirect: _redirect(route.redirect),
      builder: route.builder,
      pageBuilder: route.pageBuilder,
      observers: route.observers,
      parentNavigatorKey: route.parentNavigatorKey,
      navigatorKey: route.navigatorKey,
      restorationScopeId: route.restorationScopeId,
      routes: <RouteBase>[
        for (final RouteBase child in route.routes) _top(child, at),
      ],
    );
  }
  throw ArgumentError.value(
    route,
    'route',
    'is a kind of route dvMountRoutes cannot move under a prefix',
  );
}
