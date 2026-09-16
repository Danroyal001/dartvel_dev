/// The routes the generated router serves the prebuilt account pages at, and
/// the entries an application places in its own navigation.
///
/// `dartvel routes` gives each page in `dartvel.auth.pages` a route --
/// `DV.Auth.ProfilePage` at `/account/profile` unless the pubspec says
/// otherwise -- and writes `dartvelAccountPages`, the list of
/// [DVAccountPageEntry] for the ones it served. A page the application put at
/// the same path is the application's, and gets no generated route.
///
/// Every page but sign-up is behind [DVAccountPages.requireSession]. The
/// endpoints each page calls refuse without a session anyway; the gate is
/// what makes that a sign-in rather than a page of failed requests that reads
/// as a broken server.
library dartvel_flutter.routing.account_pages;

import 'package:dartvel_core/dartvel.dart' show DVSession;

import '../../dartvel_flutter.dart' show DVRouteTarget;
import '../auth/session_client.dart' show DVSessionClient;
import 'page_middleware.dart' show dvSignInRoute;

/// One of the prebuilt account pages.
enum DVAccountPage {
  /// `DV.Auth.ProfilePage`: the address, changed once verified.
  profile('Profile', requiresSession: true),

  /// `DV.Auth.SecurityPage`: password, authenticator app and recovery codes.
  security('Security', requiresSession: true),

  /// `DV.Auth.SessionsPage`: every signed-in device, with sign-out for each.
  sessions('Devices', requiresSession: true),

  /// `DV.Auth.DeletePage`.
  delete('Delete account', requiresSession: true),

  /// `DV.Auth.SignUpPage`, for somebody with no account yet.
  signUp('Sign up', requiresSession: false),

  /// `DV.Auth.SignInWithEmailAndPasswordPage`, where the others send somebody
  /// signed out.
  signIn('Sign in', requiresSession: false);

  const DVAccountPage(this.label, {required this.requiresSession});

  /// What a menu calls the page.
  final String label;

  /// Whether the generated route sends somebody not signed in to sign in.
  final bool requiresSession;
}

/// A navigation entry for an account page the generated router serves.
class DVAccountPageEntry {
  const DVAccountPageEntry(this.page, this.target);

  final DVAccountPage page;

  /// Where the generated route is: the configured path, not the default.
  final DVRouteTarget target;

  String get label => page.label;

  bool get requiresSession => page.requiresSession;

  @override
  String toString() => 'DVAccountPageEntry(${page.name}, ${target.path})';
}

/// The gate the generated router puts in front of an account page, and the
/// entries a person can follow.
class DVAccountPages {
  const DVAccountPages._();

  /// The route to redirect to, or null to let the page render.
  ///
  /// Nobody signed in goes to [dvSignInRoute], carrying where they were going
  /// as `from` for a sign-in page that returns there. When the device has not
  /// yet asked the server which session it is on -- a browser that has just
  /// loaded, whose cookie is the session -- it asks before refusing.
  static Future<String?> requireSession(Object? context, Object? state) async {
    final DVSessionClient? client = DVSessionClient.installed;
    DVSession? session = client?.current;
    if (session == null && client != null) {
      try {
        session = await client.refresh();
      } on Object {
        session = null;
      }
    }
    if (session != null) return null;
    final String location = _locationOf(state);
    if (location.isEmpty || Uri.tryParse(location)?.path == dvSignInRoute) {
      return dvSignInRoute;
    }
    return Uri(
      path: dvSignInRoute,
      queryParameters: <String, String>{'from': location},
    ).toString();
  }

  /// The entries somebody [signedIn] or not can open: a menu offering a
  /// signed-out person the security page would only send them to sign in.
  static List<DVAccountPageEntry> visible(
    List<DVAccountPageEntry> entries, {
    required bool signedIn,
  }) =>
      <DVAccountPageEntry>[
        for (final DVAccountPageEntry entry in entries)
          if (entry.requiresSession == signedIn) entry,
      ];

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
