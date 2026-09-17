/// The router the generated `createDartvelRouter()` returns.
///
/// A `GoRouter` in every respect but one: while the first location is still
/// being resolved -- an async guard checking a session, a redirect waiting on
/// storage -- it paints [DVRoutePending] where go_router builds an empty box.
/// A deep link or a reload onto a guarded route was a black screen for as
/// long as the guard took (go_router #133746).
///
/// Only the first location. After that the router always has a page, and it
/// keeps showing it while the next one resolves.
library dartvel_flutter.routing.router;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dartvel_flutter.dart' show DVPageStore, DvDefaultLoading;

class DVRouter extends GoRouter {
  DVRouter({
    required List<RouteBase> routes,
    GoRouterRedirect? redirect,
    int redirectLimit = 5,
    GoRouterWidgetBuilder? errorBuilder,
    GoRouterPageBuilder? errorPageBuilder,
    super.onException,
    super.refreshListenable,
    super.initialLocation,
    super.initialExtra,
    List<NavigatorObserver>? observers,
    super.debugLogDiagnostics,
    super.navigatorKey,
    String? restorationScopeId,
    bool requestFocus = true,
    this.pending,
  }) : _errorBuilder = errorBuilder,
       _errorPageBuilder = errorPageBuilder,
       _observers = observers,
       _restorationScopeId = restorationScopeId,
       _requestFocus = requestFocus,
       // GoRouter() is a factory over this constructor; a subclass has to
       // call the generative one, with the fixed configuration it builds.
       super.routingConfig(
         routingConfig: _FixedRoutingConfig(
           RoutingConfig(
             routes: routes,
             redirect: redirect ?? _noRedirect,
             redirectLimit: redirectLimit,
           ),
         ),
         errorBuilder: errorBuilder,
         errorPageBuilder: errorPageBuilder,
         observers: observers,
         restorationScopeId: restorationScopeId,
         requestFocus: requestFocus,
       );

  static FutureOr<String?> _noRedirect(
    BuildContext context,
    GoRouterState state,
  ) => null;

  /// What to paint while the first location resolves. [DVRoutePending] when
  /// null.
  final WidgetBuilder? pending;

  final GoRouterWidgetBuilder? _errorBuilder;
  final GoRouterPageBuilder? _errorPageBuilder;
  final List<NavigatorObserver>? _observers;
  final String? _restorationScopeId;
  final bool _requestFocus;

  GoRouterDelegate? _delegate;

  @override
  GoRouterDelegate get routerDelegate => _delegate!;

  /// GoRouter's constructor assigns its delegate here; the one kept is the
  /// same delegate with the pending view in its empty state. Built from the
  /// arguments this router was given rather than read back off the one
  /// handed in, whose builder is not public API.
  @override
  set routerDelegate(GoRouterDelegate value) {
    _delegate = _DVPendingDelegate(
      configuration: configuration,
      errorPageBuilder: _errorPageBuilder,
      errorBuilder: _errorBuilder,
      routerNeglect: value.routerNeglect,
      observers: <NavigatorObserver>[...?_observers],
      restorationScopeId: _restorationScopeId,
      requestFocus: _requestFocus,
      builderWithNav: (BuildContext context, Widget child) =>
          InheritedGoRouter(goRouter: this, child: child),
      pending: pending ?? (BuildContext context) => const DVRoutePending(),
    );
  }
}

class _DVPendingDelegate extends GoRouterDelegate {
  _DVPendingDelegate({
    required super.configuration,
    required super.builderWithNav,
    required super.errorPageBuilder,
    required super.errorBuilder,
    required super.observers,
    required super.routerNeglect,
    super.restorationScopeId,
    super.requestFocus,
    required this.pending,
  });

  final WidgetBuilder pending;

  @override
  Widget build(BuildContext context) {
    final RouteMatchList current = currentConfiguration;
    if (current.isEmpty && !current.isError) return pending(context);
    return super.build(context);
  }
}

/// What a route shows while its first location is resolving.
///
/// The theme's page background with a progress indicator on it, announced as
/// loading, so the moment reads as the application working rather than as a
/// screen that failed to draw.
class DVRoutePending extends StatelessWidget {
  const DVRoutePending({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Semantics(
        label: 'Loading',
        liveRegion: true,
        child: const Center(child: DvDefaultLoading()),
      ),
    );
  }
}

/// A routing configuration that never changes, as `GoRouter()` makes one.
class _FixedRoutingConfig extends ValueListenable<RoutingConfig> {
  const _FixedRoutingConfig(this.value);

  @override
  final RoutingConfig value;

  // Nothing to listen to: the value never changes.
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// Where `dartvel.notFoundRedirect` sends a path no route serves, or null to
/// leave the location alone.
///
/// Called from the generated top-level redirect. It asks whether anything
/// matched ([GoRouterState.topRoute] is null only when nothing did) rather
/// than reading [GoRouterState.error]: go_router never sets `error` on the
/// state a top-level redirect receives, so a check on it is never true and
/// the setting was silently ignored.
///
/// Leaves alone a path that already is [to], so a target that is itself
/// unserved renders the 404 page instead of redirecting forever, and a path
/// a Studio page document is stored for, since that page is served by the
/// router's error builder and redirecting would make it unreachable.
String? dvNotFoundRedirect(GoRouterState state, String to) {
  if (to.isEmpty) return null;
  if (state.topRoute != null) return null;
  final String path = state.uri.path;
  if (path == to) return null;
  if (DVPageStore.cached(path) != null) return null;
  return to;
}
