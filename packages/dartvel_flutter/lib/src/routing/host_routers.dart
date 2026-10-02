/// Dartvel's routes inside an app that already routes some other way.
///
/// Five integrations, one rule: Dartvel's routes answer Dartvel's paths under
/// the mount, and everything else goes to the app's own handler, which keeps
/// its own types.
///
/// * go_router: [dvGoRouter] builds one `GoRouter` from Dartvel's routes and
///   the app's own, with the app's redirect asked only about its own paths.
/// * Navigator 1.0: [dvRouteFactory] wraps the app's `onGenerateRoute`.
/// * Navigator 2.0: [dvNavigator2Routes] is every Dartvel route as entries for
///   the app's own route table, spread in beside its own; [dvNavigatorPages]
///   turns the table and the delegate's location into the navigator's pages.
/// * `MaterialApp.router` / `CupertinoApp.router`: [dvRouterConfig] composes
///   the app's `RouterConfig` -- its delegate and parser -- with Dartvel's.
/// * auto_route: the generated `dartvelAutoRoutes(existing:)`, over
///   [DVHostedPage].
///
/// A host that cannot take a `GoRoute` takes [DVHostedPage], which runs
/// Dartvel's routes in a router of their own, under the host's route.
/// Dartvel's guards and redirects run there as they do in a Dartvel app, and
/// the host's back button reaches Dartvel's stack before the host's.
///
/// The generated client wraps each of these (`dartvelGoRouter`,
/// `dartvelRouteFactory`, `dartvelNavigator2_0Routes`, `dartvelRouterConfig`,
/// `dartvelAutoRoutes`) with the application's own route table.
library;

import 'dart:async' show unawaited;

import 'package:dartvel_core/dartvel.dart' show dvRoutesOverlap;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:go_router/go_router.dart';

import '../../dartvel_flutter.dart' show DVNavigation;
import 'mount.dart' show dvMountRoutes, dvRoutePaths;

/// The Dartvel path a host [location] names under [at], or null when it is
/// not one of [routes]: the host's own route, which the host handles.
String? dvHostedLocation(
  String location,
  List<RouteBase> routes, {
  String at = '/',
}) {
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
  final bool ours = dvRoutePaths(routes)
      .any((String pattern) => dvRoutesOverlap(path, pattern));
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
  RouteSettings settings,
  List<RouteBase> routes, {
  String at = '/',
}) {
  final String? location = dvHostedLocation(
    settings.name ?? '/',
    routes,
    at: at,
  );
  if (location == null) return null;
  return MaterialPageRoute<Object?>(
    settings: settings,
    builder: (BuildContext context) =>
        DVHostedPage(location: location, routes: routes, at: at),
  );
}

/// For Navigator 1.0: the app's own [existing] `onGenerateRoute`, with
/// Dartvel's pages under [at] answered first.
///
/// A name that is one of Dartvel's paths gets Dartvel's page, even where
/// [existing] would also answer it. Every other name, with its arguments, is
/// [existing]'s, and a name neither answers is unknown as it was before.
RouteFactory dvRouteFactory(
  List<RouteBase> routes, {
  String at = '/',
  RouteFactory? existing,
}) =>
    (RouteSettings settings) =>
        dvOnGenerateRoute(settings, routes, at: at) ?? existing?.call(settings);

/// For go_router: one `GoRouter` with Dartvel's [routes] mounted at [at]
/// beside the app's [existing] routes.
///
/// Dartvel's routes come first, so on a path both declare Dartvel's page
/// wins (and `dartvel routes` reports the clash as DV-ADOPT-002). The app's
/// [redirect] is asked about the app's own paths only; Dartvel's paths keep
/// Dartvel's guards. DV.Navigation is attached to the router.
GoRouter dvGoRouter(
  List<RouteBase> routes, {
  String at = '/',
  List<RouteBase> existing = const <RouteBase>[],
  GoRouterRedirect? redirect,
  String? initialLocation,
  GoRouterWidgetBuilder? errorBuilder,
  List<NavigatorObserver>? observers,
  GlobalKey<NavigatorState>? navigatorKey,
  Listenable? refreshListenable,
  int redirectLimit = 5,
}) {
  final List<RouteBase> mounted = dvMountRoutes(routes, at: at);
  final GoRouter router = GoRouter(
    routes: <RouteBase>[...mounted, ...existing],
    initialLocation: initialLocation,
    errorBuilder: errorBuilder,
    observers: observers,
    navigatorKey: navigatorKey,
    refreshListenable: refreshListenable,
    redirectLimit: redirectLimit,
    redirect: redirect == null
        ? null
        : (BuildContext context, GoRouterState state) {
            final bool ours =
                dvHostedLocation(state.uri.toString(), routes, at: at) != null;
            return ours ? null : redirect(context, state);
          },
  );
  DVNavigation.attach(router);
  return router;
}

/// One entry in a Navigator 2.0 app's own route table: a path [pattern] and
/// the page it builds for a matching location.
///
/// An app writes its own routes with it and spreads Dartvel's in beside them:
///
/// ```dart
/// final List<DVNavigatorRoute> table = <DVNavigatorRoute>[
///   DVNavigatorRoute('/profile', (Uri uri) => const MaterialPage(child: ProfileScreen())),
///   ...dartvelNavigator2_0Routes(at: '/app', onLocationChanged: go),
/// ];
/// // In the RouterDelegate's build:
/// Navigator(pages: [homePage, ...dvNavigatorPages(location, table)], ...)
/// ```
///
/// The app's RouterDelegate stays in charge: it owns the location, the stack
/// and the address bar, and asks the table which page a location is.
class DVNavigatorRoute {
  const DVNavigatorRoute(this.pattern, this.pageBuilder);

  /// The path this entry answers, with `:param` segments and `**` for the
  /// rest of a path, as go_router writes them.
  final String pattern;

  /// The page for a location this entry matches.
  final Page<Object?> Function(Uri location) pageBuilder;

  /// Whether this entry answers [location]'s path. The query is not part of
  /// the match; it reaches the page with the location.
  bool matches(Uri location) =>
      dvRoutesOverlap(location.path.isEmpty ? '/' : location.path, pattern) &&
      _segmentCountFits(location.path, pattern);

  Page<Object?> page(Uri location) => pageBuilder(location);

  /// A path is not answered by a pattern with more fixed segments than it
  /// has, unless the pattern ends in a catch-all.
  static bool _segmentCountFits(String path, String pattern) {
    final List<String> pathSegments =
        path.split('/').where((String part) => part.isNotEmpty).toList();
    final List<String> patternSegments =
        pattern.split('/').where((String part) => part.isNotEmpty).toList();
    if (patternSegments.isNotEmpty && patternSegments.last.startsWith('*')) {
      return pathSegments.length >= patternSegments.length - 1;
    }
    return pathSegments.length == patternSegments.length;
  }
}

/// For Navigator 2.0: every one of Dartvel's [routes], mounted at [at], as
/// entries for the app's own route table -- spread them in beside its own.
///
/// Each entry builds the same page, keyed by the mount, that runs Dartvel's
/// whole route table: moving between two Dartvel locations keeps that page
/// and its state, and Dartvel's guards, parameters, query and back stack
/// behave as in a Dartvel app. Under a prefix, a final `<at>/**` entry gives
/// an unknown path under the mount Dartvel's not-found page rather than the
/// app's. When somebody navigates inside Dartvel, the new location, under
/// the mount, is handed to [onLocationChanged] so the delegate keeps the
/// address bar in step.
List<DVNavigatorRoute> dvNavigator2Routes(
  List<RouteBase> routes, {
  String at = '/',
  ValueChanged<Uri>? onLocationChanged,
}) {
  Page<Object?> hostedPage(Uri location) {
    final String path = location.path.isEmpty ? '/' : location.path;
    final String inner = at == '/'
        ? path
        : path == at
            ? '/'
            : path.startsWith('$at/')
                ? path.substring(at.length)
                : path;
    return MaterialPage<Object?>(
      key: ValueKey<String>('dartvel:$at'),
      name: location.toString(),
      child: DVHostedPage(
        location: location.replace(path: inner).toString(),
        routes: routes,
        at: at,
        onLocationChanged: onLocationChanged,
      ),
    );
  }

  return <DVNavigatorRoute>[
    for (final String pattern in dvRoutePaths(routes))
      DVNavigatorRoute(dvHostedPath(pattern, at: at), hostedPage),
    if (at != '/') DVNavigatorRoute('$at/**', hostedPage),
  ];
}

/// For Navigator 2.0: the page for [location] from the app's route [table],
/// the first entry that matches, or none -- what goes into the navigator's
/// `pages` after the app's own base pages.
List<Page<Object?>> dvNavigatorPages(
  Uri location,
  Iterable<DVNavigatorRoute> table,
) {
  for (final DVNavigatorRoute route in table) {
    if (route.matches(location)) return <Page<Object?>>[route.page(location)];
  }
  return const <Page<Object?>>[];
}

/// For `MaterialApp.router` and `CupertinoApp.router`: the app's own
/// [existing] `RouterConfig` composed with Dartvel's [routes] under [at].
///
/// A location that is one of Dartvel's paths is Dartvel's, and runs its whole
/// route table; any other is parsed by [existing]'s parser and handed to
/// [existing]'s delegate, in [existing]'s own configuration type. The app's
/// screens stay built while a Dartvel page shows, and back from Dartvel's
/// first page returns to them. With no [existing], the config is Dartvel's
/// alone.
RouterConfig<Object> dvRouterConfig<T extends Object>(
  List<RouteBase> routes, {
  String at = '/',
  RouterConfig<T>? existing,
}) {
  if (existing == null) {
    final GoRouter router = GoRouter(routes: dvMountRoutes(routes, at: at));
    DVNavigation.attach(router);
    return router;
  }
  final RouteInformationParser<T>? parser = existing.routeInformationParser;
  if (parser == null) {
    throw ArgumentError.value(
      existing,
      'existing',
      'has no routeInformationParser, so the locations that are not '
          "Dartvel's cannot be handed to it",
    );
  }
  final RouteInformationProvider? provider = existing.routeInformationProvider;
  return RouterConfig<Object>(
    routeInformationProvider: provider == null
        ? PlatformRouteInformationProvider(
            initialRouteInformation: RouteInformation(
              uri: Uri.parse(
                WidgetsBinding.instance.platformDispatcher.defaultRouteName,
              ),
            ),
          )
        : _DVComposedProvider(provider, routes, at),
    routeInformationParser: _DVComposedParser<T>(routes, at, parser),
    routerDelegate: _DVComposedDelegate<T>(routes, at, existing.routerDelegate),
    backButtonDispatcher:
        existing.backButtonDispatcher ?? RootBackButtonDispatcher(),
  );
}

/// The app's own route information provider, with Dartvel's locations kept
/// out of it.
///
/// The app's router still navigates through its provider -- `context.go` on
/// a GoRouter is a change to it -- so the composed router listens to it. But
/// a provider may only understand the information its own parser restores
/// (go_router's refuses any without its state), so a Dartvel location the
/// router reports is held here and sent to the platform directly.
class _DVComposedProvider extends RouteInformationProvider with ChangeNotifier {
  _DVComposedProvider(this.existing, this.routes, this.at) {
    existing.addListener(_existingChanged);
  }

  final RouteInformationProvider existing;
  final List<RouteBase> routes;
  final String at;
  RouteInformation? _dartvel;

  void _existingChanged() {
    _dartvel = null;
    notifyListeners();
  }

  @override
  RouteInformation get value => _dartvel ?? existing.value;

  @override
  void routerReportsNewRouteInformation(
    RouteInformation routeInformation, {
    RouteInformationReportingType type = RouteInformationReportingType.none,
  }) {
    if (dvHostedLocation(routeInformation.uri.toString(), routes, at: at) ==
        null) {
      _dartvel = null;
      existing.routerReportsNewRouteInformation(routeInformation, type: type);
      return;
    }
    _dartvel = routeInformation;
    unawaited(SystemNavigator.selectMultiEntryHistory());
    unawaited(
      SystemNavigator.routeInformationUpdated(
        uri: routeInformation.uri,
        replace: type == RouteInformationReportingType.neglect,
      ),
    );
  }

  @override
  void dispose() {
    existing.removeListener(_existingChanged);
    super.dispose();
  }
}

/// A location of Dartvel's, as the host sees it: under the mount.
class _DVLocation {
  const _DVLocation(this.uri);
  final Uri uri;
}

/// A configuration of the app's own router, in its own type.
class _DVHostConfiguration<T> {
  const _DVHostConfiguration(this.value);
  final T value;
}

class _DVComposedParser<T extends Object> extends RouteInformationParser<Object> {
  _DVComposedParser(this.routes, this.at, this.existing);

  final List<RouteBase> routes;
  final String at;
  final RouteInformationParser<T> existing;

  @override
  Future<Object> parseRouteInformationWithDependencies(
    RouteInformation routeInformation,
    BuildContext context,
  ) async {
    final Uri uri = routeInformation.uri;
    if (dvHostedLocation(uri.toString(), routes, at: at) != null) {
      return _DVLocation(uri);
    }
    return _DVHostConfiguration<T>(
      await existing.parseRouteInformationWithDependencies(
        routeInformation,
        context,
      ),
    );
  }

  @override
  RouteInformation? restoreRouteInformation(Object configuration) =>
      switch (configuration) {
        _DVLocation(:final Uri uri) => RouteInformation(uri: uri),
        _DVHostConfiguration<T>(:final T value) =>
          existing.restoreRouteInformation(value),
        _ => null,
      };
}

class _DVComposedDelegate<T extends Object> extends RouterDelegate<Object>
    with ChangeNotifier {
  _DVComposedDelegate(this.routes, this.at, this.existing) {
    existing.addListener(_existingChanged);
  }

  final List<RouteBase> routes;
  final String at;
  final RouterDelegate<T> existing;
  final GlobalKey<_DVHostedPageState> _hosted =
      GlobalKey<_DVHostedPageState>();

  /// The Dartvel location showing, under the mount; null while the app's
  /// own screens show.
  Uri? _dartvel;

  /// Whether the app's own screens have been shown, so back from Dartvel's
  /// first page has somewhere to go.
  bool _existingShown = false;

  void _existingChanged() {
    if (_dartvel == null) notifyListeners();
  }

  @override
  Object? get currentConfiguration {
    final Uri? dartvel = _dartvel;
    if (dartvel != null) return _DVLocation(dartvel);
    final T? value = existing.currentConfiguration;
    return value == null ? null : _DVHostConfiguration<T>(value);
  }

  @override
  Future<void> setNewRoutePath(Object configuration) async {
    switch (configuration) {
      case _DVLocation(:final Uri uri):
        _dartvel = uri;
        notifyListeners();
      case _DVHostConfiguration<T>(:final T value):
        _dartvel = null;
        _existingShown = true;
        await existing.setNewRoutePath(value);
        notifyListeners();
    }
  }

  @override
  Future<void> setInitialRoutePath(Object configuration) async {
    switch (configuration) {
      case _DVLocation(:final Uri uri):
        _dartvel = uri;
        notifyListeners();
      case _DVHostConfiguration<T>(:final T value):
        _dartvel = null;
        _existingShown = true;
        await existing.setInitialRoutePath(value);
        notifyListeners();
    }
  }

  @override
  Future<bool> popRoute() async {
    if (_dartvel == null) return existing.popRoute();
    // Dartvel's own stack first, then back to the app's screens.
    final _DVHostedPageState? hosted = _hosted.currentState;
    if (hosted != null && hosted._router.canPop()) {
      hosted._router.pop();
      return true;
    }
    if (!_existingShown) return false;
    _dartvel = null;
    notifyListeners();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final Uri? dartvel = _dartvel;
    final String? inner = dartvel == null
        ? null
        : dvHostedLocation(dartvel.toString(), routes, at: at);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // The app's screens stay built behind a Dartvel page, so returning
        // to them finds them as they were.
        if (_existingShown)
          Offstage(
            offstage: inner != null,
            child: TickerMode(
              enabled: inner == null,
              child: existing.build(context),
            ),
          ),
        if (inner != null)
          DVHostedPage(
            key: _hosted,
            location: inner,
            routes: routes,
            at: at,
            onLocationChanged: (Uri uri) {
              _dartvel = uri;
              notifyListeners();
            },
          ),
      ],
    );
  }

  @override
  void dispose() {
    existing.removeListener(_existingChanged);
    super.dispose();
  }
}

/// Dartvel's routes, run by a router of their own inside a host's route.
class DVHostedPage extends StatefulWidget {
  const DVHostedPage({
    super.key,
    required this.location,
    required this.routes,
    this.at = '/',
    this.onLocationChanged,
  });

  /// The Dartvel path to open, without the mount point. A different one
  /// given later is navigated to.
  final String location;
  final List<RouteBase> routes;

  /// Where the host serves Dartvel, for the address bar.
  final String at;

  /// Told the location, under the mount, when somebody navigates inside
  /// Dartvel. A host whose own router keeps the address -- a Navigator 2.0
  /// delegate -- keeps its configuration in step with it; without one the
  /// page updates the address bar on the web itself.
  final ValueChanged<Uri>? onLocationChanged;

  @override
  State<DVHostedPage> createState() => _DVHostedPageState();
}

class _DVHostedPageState extends State<DVHostedPage> {
  late final GoRouter _router = GoRouter(
    routes: widget.routes,
    initialLocation: widget.location,
  );

  @override
  void initState() {
    super.initState();
    _router.routerDelegate.addListener(_changed);
    // DVNavLink and DV.Navigation reach the router the page is in.
    DVNavigation.attach(_router);
  }

  @override
  void didUpdateWidget(DVHostedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The host moved to another Dartvel location: go there, rather than
    // staying on the one this page was first opened at.
    if (widget.location != oldWidget.location &&
        widget.location != _current) {
      _router.go(widget.location);
    }
  }

  /// Where Dartvel's router is now, without the mount point.
  String get _current =>
      _router.routerDelegate.currentConfiguration.uri.toString();

  void _changed() {
    // Whether Dartvel's stack can pop is known once its navigator has
    // rebuilt with the new page, a frame after the router says it changed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    final ValueChanged<Uri>? report = widget.onLocationChanged;
    if (report != null) {
      final String current = _current;
      if (current != widget.location) {
        // After the frame: the host rebuilds on it, and this is called
        // while Dartvel's router is still notifying.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) report(Uri.parse(dvHostedPath(current, at: widget.at)));
        });
      }
      return;
    }
    // The address bar follows the Dartvel route, under the host's mount.
    if (kIsWeb) {
      final String location = _router.routerDelegate.currentConfiguration.uri
          .toString();
      unawaited(
        SystemNavigator.routeInformationUpdated(
          uri: Uri.parse(dvHostedPath(location, at: widget.at)),
        ),
      );
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
    canPop: !_router.canPop(),
    onPopInvokedWithResult: (bool didPop, Object? _) {
      if (!didPop && _router.canPop()) _router.pop();
    },
    // No back button dispatcher of its own: the system back goes to the
    // host, whose route asks the PopScope above, which pops this stack
    // first. A second root dispatcher here answered back before the host
    // and took the whole page with it.
    child: Router<Object>(
      routerDelegate: _router.routerDelegate,
      routeInformationParser: _router.routeInformationParser,
      routeInformationProvider: _router.routeInformationProvider,
    ),
  );
}
