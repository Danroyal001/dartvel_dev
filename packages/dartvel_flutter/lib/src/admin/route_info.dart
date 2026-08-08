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

  const DVRouteInfo({
    required this.path,
    required this.page,
    required this.directory,
    this.parameters = const <String>[],
  });

  /// Whether the route takes parameters, which is what makes it a pattern
  /// rather than a page you can simply open.
  bool get isDynamic => parameters.isNotEmpty;
}
