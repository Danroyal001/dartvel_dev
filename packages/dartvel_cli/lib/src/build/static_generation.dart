/// Turning route templates into the concrete pages a static site needs.
library dartvel_cli.build.static_generation;

/// Whether [route] is a shape rather than a page.
///
/// `/posts/:slug` matches at run time and does not exist on disk. Writing it
/// out as a file produces a directory with a colon in its name that nothing
/// will ever request.
bool dvIsTemplateRoute(String route) => route.contains(':');

/// The routes that are pages already.
List<String> dvConcreteRoutes(Iterable<String> routes) =>
    routes.where((String route) => !dvIsTemplateRoute(route)).toList();

/// Fill [template]'s single parameter with [value].
///
/// The value is URL-encoded because the result is a URL. A slug derived from
/// a title can contain anything, and writing it raw produces a path the server
/// will not match and a file name that may not be legal.
String dvExpandStaticPath(String template, String value) {
  final RegExp parameter = RegExp(r':([A-Za-z_][A-Za-z0-9_]*)');
  final Iterable<RegExpMatch> matches = parameter.allMatches(template);
  if (matches.isEmpty) return template;
  if (matches.length > 1) {
    throw ArgumentError.value(
      template,
      'template',
      'This route has ${matches.length} parameters and one value was given. '
          'Half-filling it would write a page at a path containing a literal '
          'colon.',
    );
  }
  return template.replaceFirst(
    parameter,
    Uri.encodeComponent(value),
  );
}

/// The concrete paths one resolved manifest entry stands for.
///
/// [entry] is `{'route': String?, 'values': List}` as the generated resolver
/// reports it.
List<String> dvStaticPathsFor(Map<String, Object?> entry) {
  final Object? route = entry['route'];
  // A provider that never declared its route cannot become a page, and
  // guessing one would put the page at an address the router does not serve.
  if (route is! String || route.isEmpty) return const <String>[];

  final Object? values = entry['values'];
  if (values is! List) return const <String>[];

  final Set<String> paths = <String>{};
  for (final Object? value in values) {
    final String text = '$value'.trim();
    // An empty value expands to the parent -- /posts/ is the index, not a
    // post -- so generating it would overwrite a real page with an empty one.
    if (text.isEmpty) continue;
    paths.add(dvExpandStaticPath(route, text));
  }
  return paths.toList();
}
