/// Where the documentation site lives, whether it is enabled, and who may reach it.
///
/// One documentation site for one application, serving every platform that
/// application ships to. Not a page in the client: the documentation is a
/// separate Flutter application compiled on its own and served by the backend.
/// The application's own theme, shell and guards do not apply to it.
///
/// The path is a default rather than a constant. A framework that shipped a
/// fixed docs path would have created that for every application built with it.
/// The default exists so a new project works with no configuration; the setting
/// exists so a deployed one can move it somewhere nobody is guessing.
library;

/// Who may access the documentation site.
enum DVDocsAccess {
  /// Open to anyone without authentication.
  public,

  /// Protected by Studio authentication and access grants.
  studio;
}

/// Everything below the mount belongs to the docs site.
class DVDocsMount {
  const DVDocsMount({
    required this.path,
    required this.enabled,
    this.access = DVDocsAccess.studio,
  });

  /// The mount, with no trailing slash.
  final String path;

  /// Whether the backend serves it at all.
  final bool enabled;

  /// Who may reach the documentation site.
  final DVDocsAccess access;

  /// Whether a request has to be authenticated before it sees anything.
  bool get requiresAuth => access == DVDocsAccess.studio;

  /// Whether [route] is the docs site's rather than the application's.
  bool owns(String route) => route == path || route.startsWith('$path/');
}

/// The default, and only the default.
const String dvDocsDefaultPath = '/docs';

/// What `dartvel.docs` says in pubspec.yaml.
///
/// The documentation site is OFF by default for every app. A build includes
/// it only when pubspec says so, e.g. `dartvel: docs: enabled: true`.
/// Access defaults to `studio` when enabled, requiring a Studio grant.
DVDocsMount dvDocsMount(Object? dartvel, {bool? release}) {
  final Object? docs = dartvel is Map ? dartvel['docs'] : null;
  final Object? declared = docs is Map ? docs['path'] : null;
  final Object? enabled = docs is Map ? docs['enabled'] : null;
  final Object? accessRaw = docs is Map ? docs['access'] : null;

  final String path = declared is String && declared.trim().isNotEmpty
      ? _normalise(declared)
      : dvDocsDefaultPath;

  final DVDocsAccess access = accessRaw is String &&
          accessRaw.trim().toLowerCase() == 'public'
      ? DVDocsAccess.public
      : DVDocsAccess.studio;

  return DVDocsMount(
    path: path,
    enabled: enabled == true,
    access: access,
  );
}

/// Why [path] cannot be a mount, or null when it can be.
///
/// Refused rather than repaired. A path with no leading slash never matches a
/// request, because a request path always does.
String? dvDocsMountProblem(String path) {
  final String value = path.trim();
  if (!value.startsWith('/')) {
    return 'The docs path has to begin with "/". "$value" never matches a '
        'request, because a request path always does.';
  }
  if (_normalise(value).isEmpty) {
    return 'The documentation cannot be mounted at "/": it owns everything '
        'below its mount, and everything below "/" is the application.';
  }
  if (value.contains(':') || value.contains('*')) {
    return 'The docs path is a literal, not a template. "$value" would match '
        'routes the application means to serve itself.';
  }
  return null;
}

/// Why a page cannot be where it is, given the mount, or null.
///
/// The docs site owns its mount and everything under it, so an application
/// page at either is shadowed rather than colliding visibly -- and which of
/// the two disappears depends on the order they were registered in. That
/// makes it a build-time refusal: a build that picks silently is a build that
/// moves the bug somewhere else.
String? dvDocsMountConflict(String mount, Map<String, String> pages) {
  final DVDocsMount docs =
      DVDocsMount(path: mount, enabled: true, access: DVDocsAccess.public);
  for (final MapEntry<String, String> page in pages.entries) {
    if (!docs.owns(page.key)) continue;
    return 'The page in ${page.value} claims "${page.key}", which is inside '
        'the docs mount "$mount". One of the two would be unreachable, and '
        'which one depends on the order they are registered in. Move the '
        'page, or move the docs with dartvel.docs.path in pubspec.yaml.';
  }
  return null;
}

/// A path with no trailing slash, so `/docs/` and `/docs` are one mount.
String _normalise(String path) {
  String value = path.trim();
  while (value.length > 1 && value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value == '/' ? '' : value;
}