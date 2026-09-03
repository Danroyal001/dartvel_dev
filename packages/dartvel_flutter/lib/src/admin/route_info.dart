/// One generated route, as the route explorer sees it.
///
/// `DVRoutes` is a class of static consts, which nothing can enumerate — it
/// is for navigating to a known route, not for asking what routes exist. The
/// generated `dartvelRouteManifest` is a list of these.
class DVRouteInfo {
  /// The route pattern, parameters included: `/posts/:slug`.
  final String path;

  /// The generated page widget serving it.
  final String page;

  /// Where the page was declared, so a route can be traced back to a file.
  final String directory;

  /// The path parameters, in the order they appear.
  final List<String> parameters;

  /// The mounted module whose page this is, or null for the application's
  /// own. A route explorer that could not tell them apart would show a
  /// module's pages as the parent's.
  final String? module;

  /// Where a federated module's route answers from, or null for a route this
  /// application serves itself.
  ///
  /// A federated module is deployed elsewhere and its pages are not in this
  /// artifact. A sitemap or route explorer that listed them as local would
  /// point a crawler at a path this application answers with its own
  /// not-found page.
  final String? location;

  const DVRouteInfo({
    required this.path,
    required this.page,
    required this.directory,
    this.parameters = const <String>[],
    this.module,
    this.location,
  });

  /// Whether this application serves the route itself.
  bool get isLocal => location == null;

  /// Whether the route takes parameters, which is what makes it a pattern
  /// rather than a page you can simply open.
  bool get isDynamic => parameters.isNotEmpty;
}
