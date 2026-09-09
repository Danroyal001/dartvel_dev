/// The middleware a page declares, run before its route activates.
///
/// `@DVUseMiddleware` on a `@DVPage` was read by nothing. The backend
/// generator checked the spelling of every such annotation in `lib/**` --
/// pages included -- against the sets written for the HTTP chain, and the
/// router generator had never heard of the annotation, so a page could
/// declare `auth` and open for everybody with a green build behind it.
///
/// This is the page half, and it is deliberately narrow. A page middleware
/// runs inside the router's `redirect`, which can return a location or let
/// the route through, so the only decisions expressible here are the ones of
/// that shape. Which keys those are lives in `dartvel_core` next to the
/// backend sets, so the generator's refusals and this file cannot drift.
library dartvel_flutter.routing.page_middleware;

import 'package:dartvel_core/dartvel.dart'
    show dvPageMiddlewareKeysBuilt, dvPageMiddlewareRefusal;

/// Where a visitor who is not signed in is sent.
///
/// A variable rather than a constant so an application whose sign-in page is
/// somewhere else does not acquire a route it has never styled.
String dvSignInRoute = '/login';

/// Where a visitor is sent while the application is down.
String dvMaintenanceRoute = '/maintenance';

/// Runs a page's declared middleware, for the generated router.
class DVPageMiddleware {
  const DVPageMiddleware._();

  /// Whether somebody is signed in, for `DVMiddlewares.auth`.
  ///
  /// Null means nobody taught the application how to answer, and the key
  /// then refuses rather than admitting everybody. That is the same default
  /// [DVPagePolicy] takes, and for the same reason: a page that declared
  /// authentication and got none is not a public page.
  static Future<bool> Function()? isSignedIn;

  /// Whether the application is down, for `DVMiddlewares.maintenance`.
  ///
  /// Null means it is up -- the opposite default to [isSignedIn], and
  /// deliberately. Nobody wires this until they have a maintenance window to
  /// declare, so reading silence as "down" would black out every application
  /// on the release that added the feature. Failing open is wrong for
  /// authentication and right here: the risk of a wrong answer is a page
  /// served during a deploy, not a page served to the wrong person.
  static Future<bool> Function()? isDown;

  /// Routes that stay reachable while the application is down.
  ///
  /// [dvMaintenanceRoute] is always reachable and is not listed here: a
  /// maintenance page that redirects to itself is an infinite redirect, and
  /// the exception go_router raises for it names the router rather than the
  /// page anybody would go looking at.
  static List<String> maintenanceAllows = const <String>[];

  /// Where to send this visitor, or null to let the route activate.
  ///
  /// [keys] run in the order the page declared them and the first refusal
  /// wins, so nothing after a refusal is asked. Order is observable and
  /// worth preserving: a maintenance check behind an auth check sends a
  /// signed-out visitor to sign in to an application that is not serving
  /// anybody.
  static Future<String?> check(
    Object? context,
    Object? state,
    List<String> keys,
  ) async {
    if (keys.isEmpty) return null;
    final String location = _locationOf(state);
    for (final String key in keys) {
      if (!dvPageMiddlewareKeysBuilt.contains(key)) {
        // The generator refuses these at build time, so one arriving here
        // means a generated router is older than the framework running it.
        // Letting the route through as though the middleware had applied is
        // exactly the silence this feature exists to end.
        throw ArgumentError.value(
          key,
          'middleware',
          dvPageMiddlewareRefusal(key),
        );
      }
      final String? refusal = await _run(key, location);
      if (refusal != null) return refusal;
    }
    return null;
  }

  static Future<String?> _run(String key, String location) async {
    switch (key) {
      case 'auth':
        if (location == dvSignInRoute) return null;
        final Future<bool> Function()? answer = isSignedIn;
        if (answer == null) return dvSignInRoute;
        return await answer() ? null : dvSignInRoute;
      case 'maintenance':
        if (location == dvMaintenanceRoute) return null;
        if (maintenanceAllows.contains(location)) return null;
        final Future<bool> Function()? down = isDown;
        if (down == null) return null;
        return await down() ? dvMaintenanceRoute : null;
    }
    // Unreachable while the switch covers dvPageMiddlewareKeysBuilt, and the
    // test that walks that set is what keeps it so.
    throw ArgumentError.value(key, 'key', 'is listed as built and is not.');
  }

  /// The path a router state names, without depending on the router's type.
  ///
  /// Read dynamically for the reason [DVPagePolicy] reads it dynamically:
  /// this file is compiled into applications whose router is generated, and
  /// importing go_router here would make the routing engine an
  /// implementation detail of one more file.
  static String _locationOf(Object? state) {
    if (state == null) return '';
    try {
      // ignore: avoid_dynamic_calls
      final Object? location = (state as dynamic).matchedLocation;
      return location is String ? location : '';
    } on NoSuchMethodError {
      return '';
    }
  }
}

/// Forgets everything an application or a test configured.
///
/// The hooks are static and therefore shared between tests, which is how a
/// suite ends up passing in one order and failing in another.
void dvResetPageMiddleware() {
  DVPageMiddleware.isSignedIn = null;
  DVPageMiddleware.isDown = null;
  DVPageMiddleware.maintenanceAllows = const <String>[];
  dvSignInRoute = '/login';
  dvMaintenanceRoute = '/maintenance';
}
