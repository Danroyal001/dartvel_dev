/// The routes an app serves when a page cannot be shown: nothing is at the
/// path, or the device cannot reach anything.
///
/// These were two hand-written documents emitted by the build, and the
/// service worker served the second one whenever a navigation failed. Two
/// pages in the application that no `@DVPage` declared, no theme reached, no
/// capture saw and nobody could edit — and the offline page, which is shown
/// by definition when the network is gone, could not have been a real page
/// even in principle: a real page would have needed the network to load.
///
/// They are routes now. The generator declares them in every app, the
/// framework's widgets draw them, `dartvel build web` prerenders them through
/// the same path as every other route, and the worker redirects a failed
/// navigation to the offline one.
///
/// The two strings live here, not next to the widgets that draw them, because
/// the CLI declares and redirects to them and does not depend on
/// `dartvel_flutter`, while the widgets need the same two paths to be built.
/// One place, so a rename cannot leave a worker pointing at a path nothing
/// serves.
library;

/// The route a request for a path with no page lands on.
const String dvNotFoundRoute = '/404';

/// The route a navigation that could not reach the network lands on.
const String dvOfflineRoute = '/offline';

/// Whether [path] is one of the two error routes.
///
/// Reads the path as the request was written, because that is all a build
/// gets: the same page is asked about as `/offline`, as `/offline/` by a
/// static host serving a directory index, and as
/// `/offline?from=%2Farticles` when the worker redirected a person to it.
/// Query and fragment are dropped first, and the route must be the whole
/// path.
///
/// A site served under a mount is asked about its routes with the mount
/// already stripped, the same as every other route, so a build mounts its
/// answer rather than guessing at one here — and a nested `/blog/404` is
/// still a real page whose slug is 404, which this must not swallow.
bool dvIsErrorPageRoute(String path) {
  if (path.isEmpty) return false;
  final Uri? uri = Uri.tryParse(path);
  if (uri == null) return false;
  if (uri.hasScheme || uri.hasAuthority) return false;
  String route = uri.path;
  while (route.endsWith('/')) {
    route = route.substring(0, route.length - 1);
  }
  return route == dvNotFoundRoute || route == dvOfflineRoute;
}

/// Where the offline page sends a person once the network is back: the page
/// they were trying to reach, or the home page.
///
/// `from` arrives in a query string, which anybody can write, and following
/// it would make the application's own offline page an open redirect. The
/// offline route is refused as well, because a redirect to itself is one that
/// never lands — which is exactly what a failure *while serving the offline
/// page* would otherwise write.
String dvOfflineReturn(String? from) {
  final String safe = dvSafeInternalPath(from);
  return dvIsErrorPageRoute(safe) ? '/' : safe;
}

/// A path inside this application, or `/` when [value] could leave it.
///
/// The one rule for a `from` parameter: absolute URLs, a protocol-relative
/// `//host`, a backslash, and anything unparseable all become the home page
/// rather than somewhere a person did not mean to go.
String dvSafeInternalPath(String? value) {
  if (value == null || value.isEmpty) return '/';
  if (!value.startsWith('/') || value.startsWith('//') || value.contains(r'\')) {
    return '/';
  }
  final Uri? uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return '/';
  return value;
}
