/// Routes declared in code, mounted beside the pages.
///
/// A page is a route because of where its file is. A team arriving from
/// `go_router` or `auto_route` already has its screens as widgets taking
/// constructor arguments and its structure as a tree, and asking it to move
/// every screen into a folder before anything works is asking it not to
/// adopt. These types are that tree, in the shape `go_router` taught it --
/// `DVRoute` for `GoRoute`, `DVShellRoute` for `ShellRoute`,
/// `DVStatefulShellRoute` for `StatefulShellRoute` -- with typed targets
/// where `go_router` has strings.
///
/// Declared in `lib/routes.dart` as a top-level `routes`. `dartvel routes`
/// reads the file for the paths, generates a `DVRoutes` member for each and
/// checks them against the pages; the generated router passes the list to
/// [dvConfigRoutes] and orders the result with the rest through
/// [dvOrderGoRoutes]. Nothing here is generated, so nothing here can drift
/// from what the CLI wrote.
library dartvel_flutter.routing.config_routes;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart' show dvOrderRoutes;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../dartvel_flutter.dart'
    show
        DVRouteTarget,
        DartvelRouteState,
        DartvelSeo,
        PageTransitionSpec,
        SeoProps,
        dvTransitionPage;
import 'nav_link.dart' show DVRoutePreviews;
import 'page_lifecycle.dart' show DVPageLifecycleHost;

/// What a config route's builder and redirect are told about the match.
class DVRouteState {
  const DVRouteState({
    required this.uri,
    required this.pattern,
    this.params = const <String, String>{},
  });

  /// The state of a route previewed from a link, where nothing has matched.
  DVRouteState.preview(String path)
    : uri = Uri.parse(path),
      pattern = path,
      params = const <String, String>{};

  factory DVRouteState._of(GoRouterState state) => DVRouteState(
    uri: state.uri,
    pattern: state.fullPath ?? state.matchedLocation,
    params: Map<String, String>.unmodifiable(state.pathParameters),
  );

  /// The whole location, query included.
  final Uri uri;

  /// The route as declared, parameters unfilled: `/orders/:id`.
  final String pattern;

  /// The path parameters: `{'id': '42'}` for `/orders/42`.
  final Map<String, String> params;

  /// The location's path: `/orders/42`.
  String get path => uri.path;

  /// The query parameters.
  Map<String, String> get query => uri.queryParameters;
}

/// Builds a config route's screen.
typedef DVRouteBuilder =
    Widget Function(BuildContext context, DVRouteState state);

/// Where to send a visitor instead, or null to let the route activate.
///
/// A [DVRouteTarget] rather than a string, so a redirect to a route that
/// was renamed is a compile error rather than a not-found page.
typedef DVRouteRedirect =
    FutureOr<DVRouteTarget?> Function(BuildContext context, DVRouteState state);

/// Builds the frame a [DVShellRoute]'s child routes render inside.
typedef DVShellBuilder =
    Widget Function(BuildContext context, DVRouteState state, Widget child);

/// Builds the frame of a [DVStatefulShellRoute], given the tabs.
typedef DVStatefulShellBuilder =
    Widget Function(
      BuildContext context,
      DVRouteState state,
      DVShellNavigation shell,
    );

/// One entry in `lib/routes.dart`.
sealed class DVRouteNode {
  const DVRouteNode();
}

/// A path and the screen it shows. `GoRoute`, typed.
class DVRoute extends DVRouteNode {
  const DVRoute({
    required this.path,
    required this.builder,
    this.name,
    this.title,
    this.redirect,
    this.transition,
    this.preview = true,
    this.routes = const <DVRouteNode>[],
  });

  /// Absolute at the top level and inside a shell (`/orders`), relative
  /// under another [DVRoute] (`:id`). Written once, as a plain string: the
  /// build reads it for the typed target.
  final String path;

  final DVRouteBuilder builder;

  /// The `DVRoutes` member, when the one derived from [path] collides or
  /// reads badly. An identifier, not a path.
  final String? name;

  /// The document title, over the project's SEO defaults.
  final String? title;

  /// Runs before this route and every route under it activates.
  final DVRouteRedirect? redirect;

  /// The page transition, when not the project's default.
  final PageTransitionSpec? transition;

  /// Whether a `DVNavLink` resting on a link here shows the screen. Only a
  /// route with no parameters and no redirect over it ever does.
  final bool preview;

  /// Child routes, pushed over this one.
  final List<DVRouteNode> routes;
}

/// A frame around child routes, which render in a nested navigator.
/// `ShellRoute`, typed.
class DVShellRoute extends DVRouteNode {
  const DVShellRoute({
    required this.builder,
    required this.routes,
    this.redirect,
  });

  final DVShellBuilder builder;

  /// Absolute paths.
  final List<DVRouteNode> routes;

  /// Runs before any route inside the shell activates.
  final DVRouteRedirect? redirect;
}

/// Tabs: each branch keeps its own navigation stack.
/// `StatefulShellRoute.indexedStack`, typed.
class DVStatefulShellRoute extends DVRouteNode {
  const DVStatefulShellRoute({
    required this.builder,
    required this.branches,
    this.redirect,
  });

  final DVStatefulShellBuilder builder;

  final List<DVShellBranch> branches;

  final DVRouteRedirect? redirect;
}

/// One tab of a [DVStatefulShellRoute].
class DVShellBranch {
  const DVShellBranch({required this.routes, this.initialLocation});

  /// Absolute paths.
  final List<DVRouteNode> routes;

  /// Where the tab opens, when not its first route.
  final DVRouteTarget? initialLocation;
}

/// An existing application's `go_router` routes, mounted as they are.
///
/// Not wrapped, not reordered internally and given no typed targets: the
/// build cannot read a list declared somewhere else, and the application
/// already reaches these routes the way it always has.
class DVGoRoutes extends DVRouteNode {
  const DVGoRoutes(this.routes);

  final List<RouteBase> routes;
}

/// The tabs a [DVStatefulShellRoute]'s builder places, and switches between.
class DVShellNavigation extends StatelessWidget {
  const DVShellNavigation._(this._shell);

  final StatefulNavigationShell _shell;

  /// The branch on screen.
  int get currentIndex => _shell.currentIndex;

  /// Shows branch [index], where it was left unless [initialLocation].
  void goBranch(int index, {bool initialLocation = false}) =>
      _shell.goBranch(index, initialLocation: initialLocation);

  @override
  Widget build(BuildContext context) => _shell;
}

/// [nodes] as `go_router` routes, for the generated router.
///
/// Each screen is given what a page is given that does not come from a
/// folder: the route state, the page lifecycle, the SEO defaults with the
/// route's title, and a page transition. [inheritedRedirect] is the
/// application's root `_guard.dart`, applied over every top-level node except
/// a [DVGoRoutes], which brings its own.
///
/// Registers a link preview for each parameterless route no redirect covers.
List<RouteBase> dvConfigRoutes(
  List<DVRouteNode> nodes, {
  SeoProps seo = SeoProps.empty,
  PageTransitionSpec transition = const PageTransitionSpec(),
  GoRouterRedirect? inheritedRedirect,
}) {
  final _Convert convert = _Convert(seo: seo, transition: transition);
  return <RouteBase>[
    for (final DVRouteNode node in nodes)
      if (node is DVGoRoutes)
        ...node.routes
      else
        convert.node(
          node,
          parentPath: '',
          guarded: inheritedRedirect != null,
          inherited: inheritedRedirect,
        ),
  ];
}

/// [routes] ordered so that no route hides another: a static segment is
/// matched before a parameter, a parameter before a catch-all, whatever
/// order they were declared in. A shell and a route with children move as
/// one. Throws `DVRouteOrderException` (`DV-ROUTE-004`) when no order works.
List<RouteBase> dvOrderGoRoutes(List<RouteBase> routes) =>
    dvOrderRoutes<RouteBase>(routes, (RouteBase r) => _leaves(r, ''));

Iterable<String> _leaves(RouteBase route, String parent) sync* {
  if (route is GoRoute) {
    final String full = _join(parent, route.path);
    yield full;
    for (final RouteBase child in route.routes) {
      yield* _leaves(child, full);
    }
  } else if (route is StatefulShellRoute) {
    for (final StatefulShellBranch branch in route.branches) {
      for (final RouteBase child in branch.routes) {
        yield* _leaves(child, parent);
      }
    }
  } else {
    for (final RouteBase child in route.routes) {
      yield* _leaves(child, parent);
    }
  }
}

String _join(String parent, String path) {
  if (path.startsWith('/') || parent.isEmpty) return path;
  return parent == '/' ? '/$path' : '$parent/$path';
}

class _Convert {
  _Convert({required this.seo, required this.transition});

  final SeoProps seo;
  final PageTransitionSpec transition;

  RouteBase node(
    DVRouteNode node, {
    required String parentPath,
    required bool guarded,
    GoRouterRedirect? inherited,
  }) {
    switch (node) {
      case DVRoute():
        return _route(node, parentPath, guarded, inherited);
      case DVShellRoute():
        final bool inside = guarded || node.redirect != null;
        return ShellRoute(
          redirect: _redirect(inherited, node.redirect),
          builder: (BuildContext context, GoRouterState state, Widget child) =>
              node.builder(context, DVRouteState._of(state), child),
          routes: _children(node.routes, parentPath, inside),
        );
      case DVStatefulShellRoute():
        final bool inside = guarded || node.redirect != null;
        return StatefulShellRoute.indexedStack(
          redirect: _redirect(inherited, node.redirect),
          builder:
              (
                BuildContext context,
                GoRouterState state,
                StatefulNavigationShell shell,
              ) => node.builder(
                context,
                DVRouteState._of(state),
                DVShellNavigation._(shell),
              ),
          branches: <StatefulShellBranch>[
            for (final DVShellBranch branch in node.branches)
              StatefulShellBranch(
                initialLocation: branch.initialLocation?.path,
                routes: _children(branch.routes, parentPath, inside),
              ),
          ],
        );
      case DVGoRoutes():
        // Only reachable nested: at the top level dvConfigRoutes spreads it.
        throw ArgumentError(
          'DVGoRoutes mounts a list at the top level of lib/routes.dart; '
          'nest the GoRoutes inside it instead.',
        );
    }
  }

  List<RouteBase> _children(
    List<DVRouteNode> nodes,
    String parentPath,
    bool guarded,
  ) => dvOrderGoRoutes(<RouteBase>[
    for (final DVRouteNode child in nodes)
      if (child is DVGoRoutes)
        ...child.routes
      else
        node(child, parentPath: parentPath, guarded: guarded),
  ]);

  GoRoute _route(
    DVRoute route,
    String parentPath,
    bool guarded,
    GoRouterRedirect? inherited,
  ) {
    final String full = _join(parentPath, route.path);
    final bool covered = guarded || route.redirect != null;
    if (route.preview &&
        !covered &&
        !full.contains(':') &&
        !full.contains('*')) {
      DVRoutePreviews.register(
        full,
        (BuildContext context) =>
            route.builder(context, DVRouteState.preview(full)),
      );
    }
    final PageTransitionSpec spec = route.transition ?? transition;
    return GoRoute(
      path: route.path,
      redirect: _redirect(inherited, route.redirect),
      pageBuilder: (BuildContext context, GoRouterState state) {
        final DVRouteState routeState = DVRouteState._of(state);
        return dvTransitionPage<void>(
          key: state.pageKey,
          spec: spec,
          child: DartvelSeo(
            props: SeoProps(title: route.title),
            defaults: seo,
            child: DartvelRouteState(
              params: routeState.params,
              query: routeState.query,
              child: DVPageLifecycleHost(
                child: Builder(
                  builder: (BuildContext context) =>
                      route.builder(context, routeState),
                ),
              ),
            ),
          ),
        );
      },
      routes: _children(route.routes, full, covered),
    );
  }
}

/// [inherited] and then [own], as one `go_router` redirect.
GoRouterRedirect? _redirect(GoRouterRedirect? inherited, DVRouteRedirect? own) {
  if (inherited == null && own == null) return null;
  return (BuildContext context, GoRouterState state) {
    FutureOr<String?> runOwn() {
      if (own == null) return null;
      final FutureOr<DVRouteTarget?> target = own(
        context,
        DVRouteState._of(state),
      );
      if (target is Future<DVRouteTarget?>) {
        return target.then((DVRouteTarget? t) => t?.path);
      }
      return target?.path;
    }

    if (inherited == null) return runOwn();
    final FutureOr<String?> first = inherited(context, state);
    if (first is Future<String?>) {
      return first.then((String? to) => to ?? runOwn());
    }
    return first ?? runOwn();
  };
}
