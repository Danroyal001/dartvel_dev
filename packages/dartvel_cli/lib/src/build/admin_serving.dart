/// What the backend does with a request for the admin.
///
/// Three answers, and the difference between two of them is the whole
/// security posture of the feature.
///
/// A request refused because nobody signed in has to be indistinguishable
/// from a request for a route that does not exist. An admin answering 401
/// where the rest of the site answers 404 is an oracle: it tells whoever is
/// scanning that this host is a Dartvel application, that it has a studio,
/// and where the studio is -- before anybody has typed a password. That is
/// the difference between an admin that announces itself and one nobody
/// outside the team can find, and it costs nothing to get right at the point
/// the decision is made and a great deal to retrofit afterwards.
///
/// Deciding it here, as a value rather than inside a handler, is what lets
/// it be asserted. A rule that lives in the middle of a shelf pipeline is a
/// rule that gets tested by starting a server and hoping.
library;

import 'admin_mount.dart';

/// What to do with one request.
enum DVAdminRequest {
  /// Not the admin's. The application answers it.
  notTheAdmin,

  /// The admin's, and this caller may have it.
  serve,

  /// The admin's, and this caller may not know that. Answered exactly as a
  /// route the application does not serve is answered.
  hidden,
}

/// The status a hidden request is answered with.
///
/// A number rather than a convention, because two people implementing
/// "hidden" independently is how one of them becomes a 403 -- and a 403 on
/// the admin mount and a 404 everywhere else is the oracle this exists to
/// avoid.
const int dvAdminHiddenStatus = 404;

/// The headers a hidden request is answered with.
///
/// Nothing that names the admin. A `WWW-Authenticate` here, or a body that
/// mentions a studio, gives away in one response everything the status code
/// was chosen to withhold.
const Map<String, String> dvAdminHiddenHeaders = <String, String>{
  'content-type': 'text/plain; charset=utf-8',
};

/// What the backend should do with [path].
///
/// [authenticated] is the caller's state as the application's own auth
/// decided it -- this does not authenticate anybody, it decides what an
/// already-known answer means for this route.
DVAdminRequest dvAdminFor(
  String path,
  DVAdminMount mount, {
  required bool authenticated,
}) {
  // The mount, not the default path. A project that moved its admin
  // somewhere private must not lose the check by doing so, which is what
  // happens the moment any of this is written against a literal.
  if (!mount.owns(path)) return DVAdminRequest.notTheAdmin;
  if (!mount.enabled) return DVAdminRequest.hidden;
  if (mount.requiresAuth && !authenticated) return DVAdminRequest.hidden;
  return DVAdminRequest.serve;
}
