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
}) =>
    <String>[
      for (final String path in paths)
        if (dvTemplateFor(path, declared) != null) path,
    ];

/// The template among [templates] that serves [path], or null when none does.
///
/// The same match [dvServedStaticPaths] filters on, given a name because a
/// written page has to be traced back to the model it came from -- that is
/// how a generated page finds out which favicon and which schema type it
/// should be wearing. Two matchers would be two ideas about which model a
/// page belongs to, and the wrong one would show up as a page quietly wearing
/// another model's icon.
String? dvTemplateFor(String path, Iterable<String> templates) {
  final List<String> segments = _segments(path);
  for (final String template in templates) {
    if (!dvIsTemplateRoute(template)) continue;
    if (_matches(_segments(template), segments)) return template;
  }
  return null;
}

/// Which favicon [route] should ask for: the model's own, else [application].
///
/// The specification's chain is model, then module, then application, and the
/// module level is not a third lookup here. A module's models are generated
/// from the module's own project, so a favicon the module declared is already
/// in the spec [modelFavicons] was read from.
///
/// A route belonging to no model still gets the application's. A site whose
/// product pages wear one icon and whose /about wears another is the sort of
/// inconsistency nobody files a bug about and everybody notices.
String? dvPageFavicon(
  String route,
  Map<String, String> modelFavicons, {
  String? application,
}) {
  final String? template = dvTemplateFor(route, modelFavicons.keys);
  return (template == null ? null : modelFavicons[template]) ?? application;
}

/// One string [attribute] of each model page spec, by route, read out of the
/// generated `model_pages.g.dart`.
///
/// The specs carry several decisions the static build needs and had no way to
/// ask for. Read with a pattern rather than by analysing the file, which is
/// how the build already reads the generated router: the specs come out of
/// Dartvel's own generator in a fixed shape, so the input is not arbitrary
/// Dart.
///
/// A spec that declared the attribute as null, or did not declare it at all,
/// is absent from the map rather than mapped to null. A caller falling back
/// to an application-wide value then does not have to tell "said nothing"
/// from "said nothing that parsed".
Map<String, String> dvModelPageAttribute(String source, String attribute) {
  if (source.isEmpty) return const <String, String>{};
  // Tempered so the search stops at the next spec. Left unbounded, an entry
  // carrying no such key at all -- a manifest written by an older generator
  // -- would reach forward and take the following model's value, which is a
  // wrong answer that looks exactly like a right one.
  final RegExp spec = RegExp(
    "route:\\s*'([^']+)'(?:(?!\\broute:)[\\s\\S])*?"
    "\\b$attribute:\\s*(?:'([^']*)'|null)",
  );
  final Map<String, String> values = <String, String>{};
  for (final RegExpMatch match in spec.allMatches(source)) {
    final String? value = match.group(2);
    if (value == null || value.isEmpty) continue;
    values[match.group(1)!] = value;
  }
  return values;
}

/// Which favicon each model page route declared.
///
/// `@DVModel(favicon:)` reached exactly one reader -- the web server's page
/// resolver -- so a site built statically served the shell's icon on every
/// generated page while the declaration sat in the model doing nothing.
Map<String, String> dvModelPageFavicons(String source) =>
    dvModelPageAttribute(source, 'favicon');

/// Which schema.org type each model page route declared.
///
/// `@DVModel(schemaType:)` was in the same state as the favicon: parsed,
/// written into the spec, read by the web server and by nothing on the static
/// side. So `dartvel build web` announced every product and job posting as a
/// plain WebPage -- valid structured data saying the wrong thing, on the
/// deployment where a rich result is most of the point.
Map<String, String> dvModelPageSchemaTypes(String source) =>
    dvModelPageAttribute(source, 'schemaType');

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
