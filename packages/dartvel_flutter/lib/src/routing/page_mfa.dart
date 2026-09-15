/// The check a page's declared second factor runs before its route
/// activates: `@DVPage(mfa: DVMfa.required)`.
///
/// The page is the interface. The backend functions it calls enforce their
/// own `mfa:`, so this decides what a person sees, not what data they get --
/// and what goes wrong in it is still silent: a page that declared a second
/// factor opening for a password-only session reads exactly like one that
/// asked.
///
/// The generated router calls this from the route's `redirect`, like
/// [DVPagePolicy]. An unsatisfied page redirects to the challenge at
/// [dvSecondFactorRoute] carrying where the person was going, and the
/// challenge sends them back there once a factor is presented -- the
/// suspend-challenge-resume shape a redirect already has.
library dartvel_flutter.routing.page_mfa;

import 'package:dartvel_core/dartvel.dart' show DVMfa, DVSession;

import '../auth/session_client.dart' show DVSessionClient;
import 'page_middleware.dart' show dvSignInRoute;

/// Where a page that needs a second factor sends a session without one. The
/// generated router serves `DV.Auth.SecondFactorPage` here when any page
/// declares `mfa:`.
String dvSecondFactorRoute = '/second-factor';

/// Answers whether this device's session may open a page, for the generated
/// router.
class DVPageMfa {
  const DVPageMfa._();

  /// The route to redirect to, or null to let the page render.
  ///
  /// Nobody signed in goes to [dvSignInRoute]. When the device has not yet
  /// asked the server which session it is on -- a browser that has just
  /// loaded, whose cookie is the session -- it asks before refusing, rather
  /// than sending a signed-in person to sign in.
  static Future<String?> check(
    Object? context,
    Object? state,
    DVMfa policy,
  ) async {
    final DVSessionClient? client = DVSessionClient.installed;
    DVSession? session = client?.current;
    if (session == null && client != null) {
      try {
        session = await client.refresh();
      } on Object {
        session = null;
      }
    }
    if (session == null) return dvSignInRoute;
    if (policy.isSatisfiedBy(session, DateTime.now().toUtc())) return null;
    final String location = _locationOf(state);
    if (Uri.tryParse(location)?.path == dvSecondFactorRoute) return null;
    return Uri(
      path: dvSecondFactorRoute,
      queryParameters: <String, String>{
        if (location.isNotEmpty) 'from': location,
      },
    ).toString();
  }

  /// [check] for `@DVPage(mfa: DVMfa.required)`, as the generated router
  /// calls it.
  static Future<String?> required(Object? context, Object? state) =>
      check(context, state, DVMfa.required);

  /// [check] for `@DVPage(mfa: DVMfa.recent(window))`.
  static Future<String?> recent(
    Object? context,
    Object? state,
    Duration window,
  ) =>
      check(context, state, DVMfa.recent(window));

  /// Where a completed challenge goes: [from] when it is a path in this
  /// application, otherwise `/`.
  ///
  /// `from` arrives in the query string, which anybody can write. A
  /// challenge that followed `//evil.example` or `https://evil.example`
  /// after the person proved who they are would be an open redirect with the
  /// application's own second factor as the lure.
  static String safeReturn(String? from) {
    if (from == null || from.isEmpty) return '/';
    if (!from.startsWith('/') || from.startsWith('//') || from.contains(r'\')) {
      return '/';
    }
    final Uri? uri = Uri.tryParse(from);
    if (uri == null || uri.hasScheme || uri.hasAuthority) return '/';
    return from;
  }

  /// The location a router state names, query included, without depending
  /// on the router's type -- the same reason [DVPagePolicy] reads it
  /// dynamically.
  static String _locationOf(Object? state) {
    if (state == null) return '';
    try {
      // ignore: avoid_dynamic_calls
      final Object? uri = (state as dynamic).uri;
      if (uri is Uri) return uri.toString();
    } on NoSuchMethodError {
      // Not a router state with a uri; try the matched location.
    }
    try {
      // ignore: avoid_dynamic_calls
      final Object? location = (state as dynamic).matchedLocation;
      return location is String ? location : '';
    } on NoSuchMethodError {
      return '';
    }
  }
}
