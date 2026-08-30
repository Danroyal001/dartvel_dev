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


/// Keep only the paths a declared route can serve.
///
/// The static-path manifest derives its route from the model's name, and
/// nothing used to check the router had one. That generated a page at an
/// address the application 404s on -- a crawler follows the link, gets HTML,
/// the app boots and renders its own not-found page, which is worse than the
/// page not existing.
List<String> dvServedStaticPaths(
  Iterable<String> paths, {
  required Iterable<String> declared,
}) {
  final List<List<String>> templates = <List<String>>[
    for (final String route in declared)
      if (dvIsTemplateRoute(route)) _segments(route),
  ];

  return <String>[
    for (final String path in paths)
      if (templates.any((List<String> t) => _matches(t, _segments(path)))) path,
  ];
}

/// Templates that no declared route serves.
///
/// Reported by name: a model whose pages all go nowhere is exactly what this
/// is meant to make visible.
List<String> dvUnservedTemplates(
  Iterable<String> templates, {
  required Iterable<String> declared,
}) {
  final Set<String> served = declared.toSet();
  return <String>[
    for (final String template in templates)
      if (!served.contains(template)) template,
  ];
}

List<String> _segments(String path) =>
    path.split('/').where((String s) => s.isNotEmpty).toList();

bool _matches(List<String> template, List<String> path) {
  // A route with one parameter serves one segment in its place, so a path
  // with more segments belongs to a different route or to none.
  if (template.length != path.length) return false;
  for (int i = 0; i < template.length; i++) {
    if (template[i].startsWith(':')) continue;
    if (template[i] != path[i]) return false;
  }
  return true;
}
