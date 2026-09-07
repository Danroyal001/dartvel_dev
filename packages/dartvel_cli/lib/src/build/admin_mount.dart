/// Where the admin dashboard lives, and who may reach it.
///
/// One dashboard for one application, serving every platform that
/// application ships to. Not a page in the client: the pages, models,
/// queues, jobs, telemetry and fleet an operator manages are the same on
/// every target, and an admin compiled into each client is the same editor
/// downloaded by every user, subject to that client's own guards, shell and
/// theme. A module with `shell: override` should not be able to change the
/// chrome of the screen somebody administers the application from.
///
/// So the backend mounts it, and this decides where and whether.
///
/// The path is a default rather than a constant. `/wp-admin` is fixed, which
/// is most of why it is the most scanned URL on the internet -- a framework
/// that shipped a fixed admin path would have created that for every
/// application built with it. The default exists so a new project works with
/// no configuration; the setting exists so a deployed one can move it
/// somewhere nobody is guessing.
library;

/// The default, and only the default.
const String dvAdminDefaultPath = '/__studio';

/// Everything below the mount belongs to the admin.
class DVAdminMount {
  const DVAdminMount({
    required this.path,
    required this.enabled,
    required this.requiresAuth,
  });

  /// The mount, with no trailing slash.
  final String path;

  /// Whether the backend serves it at all.
  final bool enabled;

  /// Whether a request has to be authenticated before it sees anything.
  ///
  /// Not a setting of its own. An admin reachable without a sign-in on a
  /// deployed application is the whole of the risk here, and making that
  /// optional is offering somebody a way to get it wrong on the one
  /// question where being wrong is expensive.
  final bool requiresAuth;

  /// Whether [route] is the admin's rather than the application's.
  bool owns(String route) => route == path || route.startsWith('$path/');
}

/// What `dartvel.admin` says, against what the build is.
///
/// [release] decides the default for [DVAdminMount.enabled], and that
/// default is the important one: an application deployed by somebody who
/// never read this page must not acquire an admin endpoint because a
/// framework thought it would be convenient. Development serves it with no
/// configuration at all, which is where zero-config belongs.
DVAdminMount dvAdminMount(Object? dartvel, {required bool release}) {
  final Object? admin = dartvel is Map ? dartvel['admin'] : null;
  final Object? declared = admin is Map ? admin['path'] : null;
  final Object? enabled = admin is Map ? admin['enabled'] : null;

  final String path = declared is String && declared.trim().isNotEmpty
      ? _normalise(declared)
      : dvAdminDefaultPath;

  return DVAdminMount(
    path: path,
    enabled: enabled is bool ? enabled : !release,
    requiresAuth: release,
  );
}

/// Why [path] cannot be a mount, or null when it can be.
///
/// Refused rather than repaired. A path with no leading slash never matches
/// a request, and quietly fixing it teaches the next person that either form
/// works -- until one of them does not.
String? dvAdminMountProblem(String path) {
  final String value = path.trim();
  if (!value.startsWith('/')) {
    return 'The admin path has to begin with "/". "$value" never matches a '
        'request, because a request path always does.';
  }
  if (_normalise(value).isEmpty) {
    return 'The admin cannot be mounted at "/": it owns everything below its '
        'mount, and everything below "/" is the application.';
  }
  if (value.contains(':') || value.contains('*')) {
    return 'The admin path is a literal, not a template. "$value" would '
        'match routes the application means to serve itself.';
  }
  return null;
}

/// Why a page cannot be where it is, given the mount, or null.
///
/// The admin owns its mount and everything under it, so an application page
/// at either is shadowed rather than colliding visibly -- and which of the
/// two disappears depends on the order they were registered in. That makes
/// it a build-time refusal: a build that picks silently is a build that
/// moves the bug somewhere else.
String? dvAdminMountConflict(String mount, Map<String, String> pages) {
  final DVAdminMount admin =
      DVAdminMount(path: mount, enabled: true, requiresAuth: false);
  for (final MapEntry<String, String> page in pages.entries) {
    if (!admin.owns(page.key)) continue;
    return 'The page in ${page.value} claims "${page.key}", which is inside '
        'the admin mount "$mount". One of the two would be unreachable, and '
        'which one depends on the order they are registered in. Move the '
        'page, or move the admin with dartvel.admin.path in pubspec.yaml.';
  }
  return null;
}

/// A path with no trailing slash, so `/admin/` and `/admin` are one mount.
String _normalise(String path) {
  String value = path.trim();
  while (value.length > 1 && value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value == '/' ? '' : value;
}

/// The directory `dartvel admin` writes its dashboard into.
const String dvAdminPagesDirectory = '_dartvel_admin';

/// Whether [path] is a page the client's router should carry.
///
/// The dashboard is written into `lib/pages/_dartvel_admin`, and the page
/// scanner walks `lib/pages` -- so the editor, the model browser, the queue
/// inspector and the telemetry read-out are compiled into every client the
/// application ships. On web that is bundle weight; on mobile it is app size
/// and review surface; everywhere it is the admin inheriting the
/// application's own guards, shell and theme, so a module with
/// `shell: override` can change the chrome of the screen somebody
/// administers the application from.
///
/// Where the backend is serving the admin, the client does not also carry
/// it. Where nothing is, it does -- an application with no backend admin
/// still reaches its dashboard the way it always has, and dropping the pages
/// then would remove the feature rather than move it.
bool dvPageBelongsToClient(String path, {required DVAdminMount? admin}) {
  if (admin == null || !admin.enabled) return true;
  // Both separators. The scanner hands back whatever the platform's paths
  // look like, and a rule that knew only forward slashes would ship the
  // admin to every client built on Windows and nowhere else.
  final String normalised = path.replaceAll(r'\', '/');
  return !normalised.contains('/$dvAdminPagesDirectory/');
}
