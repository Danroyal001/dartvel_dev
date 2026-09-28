/// Dartvel's routes inside a host that does not route with go_router.
///
/// A host that keeps its `GoRouter` mounts Dartvel's routes into it with
/// `dartvelRoutes(at:)`. A host on Flutter's own Navigator -- 1.0's
/// `onGenerateRoute`, or 2.0's pages -- or on auto_route cannot take a
/// `GoRoute`, so it takes a page instead: [DVHostedPage] runs Dartvel's
/// routes in a router of their own, under the host's route. Dartvel's
/// guards and redirects run there as they do in a Dartvel app, the host's
/// back button reaches Dartvel's stack before the host's, and on the web the
/// address bar follows the Dartvel route.
///
/// The generated client wraps these as `dartvelOnGenerateRoute`,
/// `dartvelPageFor` and, for a project that depends on auto_route,
/// `dartvelAutoRoutes`.
library;

import 'dart:async' show unawaited;

import 'package:dartvel_core/dartvel.dart' show dvRoutesOverlap;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:go_router/go_router.dart';

import '../../dartvel_flutter.dart' show DVNavigation;
import 'mount.dart' show dvRoutePaths;

/// The Dartvel path a host [location] names under [at], or null when it is
/// not one of [routes]: the host's own route, which the host handles.
String? dvHostedLocation(String location, List<RouteBase> routes,
    {String at = '/'}) {
  final Uri uri = Uri.parse(location);
  String path = uri.path.isEmpty ? '/' : uri.path;
  if (at != '/') {
    if (path == at) {
      path = '/';
    } else if (path.startsWith('$at/')) {
      path = path.substring(at.length);
    } else {
      return null;
    }
  }
  final bool ours =
      dvRoutePaths(routes).any((String pattern) => dvRoutesOverlap(path, pattern));
  if (!ours) return null;
  return uri.replace(path: path).toString();
}

/// The host path for a Dartvel [path] mounted at [at]: what a host passes to
/// `Navigator.pushNamed` for `DVRoutes.about.path`.
String dvHostedPath(String path, {String at = '/'}) =>
    at == '/' ? path : (path == '/' ? at : '$at$path');

/// For Navigator 1.0: a route for [settings] when it names a Dartvel page
/// under [at], else null for the host's own `onGenerateRoute` to answer.
Route<Object?>? dvOnGenerateRoute(
    RouteSettings settings, List<RouteBase> routes, {String at = '/'}) {
  final String? location =
      dvHostedLocation(settings.name ?? '/', routes, at: at);
  if (location == null) return null;
  return MaterialPageRoute<Object?>(
    settings: settings,
    builder: (BuildContext context) =>
        DVHostedPage(location: location, routes: routes, at: at),
  );
}

/// For Navigator 2.0: the page for [uri] when it names a Dartvel page under
/// [at], else null. The host puts it in its navigator's `pages`.
Page<Object?>? dvPageFor(Uri uri, List<RouteBase> routes, {String at = '/'}) {
  final String? location = dvHostedLocation(uri.toString(), routes, at: at);
  if (location == null) return null;
  return MaterialPage<Object?>(
    key: ValueKey<String>('dartvel:$at'),
    name: uri.toString(),
    child: DVHostedPage(location: location, routes: routes, at: at),
  );
}

/// Dartvel's routes, run by a router of their own inside a host's route.
class DVHostedPage extends StatefulWidget {
  const DVHostedPage({
    super.key,
    required this.location,
    required this.routes,
    this.at = '/',
  });

  /// The Dartvel path to open, without the mount point.
  final String location;
  final List<RouteBase> routes;

  /// Where the host serves Dartvel, for the address bar.
  final String at;

  @override
  State<DVHostedPage> createState() => _DVHostedPageState();
}

class _DVHostedPageState extends State<DVHostedPage> {
  late final GoRouter _router = GoRouter(
    routes: widget.routes,
    initialLocation: widget.location,
  );
  bool _canPop = false;

  @override
  void initState() {
    super.initState();
    _router.routerDelegate.addListener(_changed);
    // DVNavLink and DV.Navigation reach the router the page is in.
    DVNavigation.attach(_router);
  }

  void _changed() {
    final bool canPop = _router.canPop();
    if (canPop != _canPop) setState(() => _canPop = canPop);
    // The address bar follows the Dartvel route, under the host's mount.
    if (kIsWeb) {
      final String location =
          _router.routerDelegate.currentConfiguration.uri.toString();
      unawaited(SystemNavigator.routeInformationUpdated(
          uri: Uri.parse(dvHostedPath(location, at: widget.at))));
    }
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_changed);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
        // Back goes to Dartvel's own stack first, and to the host's once
        // there is nothing left in it.
        canPop: !_canPop,
        onPopInvokedWithResult: (bool didPop, Object? _) {
          if (!didPop && _router.canPop()) _router.pop();
        },
        child: Router<Object>.withConfig(config: _router),
      );
}
