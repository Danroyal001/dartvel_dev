/// Which document and which images a route prefetches, worked out from its
/// path and the manifest the build wrote. No DOM here, so every platform
/// can test it and the web implementation can share it.
library dartvel_flutter.routing.route_prefetch_paths;

import 'dart:convert';

/// The manifest `dartvel build web` writes next to index.html.
const String dvPrefetchManifestPath = 'dartvel_prefetch.json';

/// The prerendered page [path] is served as, relative to the base the site is
/// served from -- so a site under `/app/` prefetches `/app/docs`, not
/// `/docs`.
///
/// The address a new tab or a reload asks for, which is the one a prefetch
/// has to match to be of any use: the browser keys what it fetched by URL.
String dvPrefetchHref(String path) {
  final String route = _routeKey(path);
  return route == '/' ? './' : route.substring(1);
}

/// The images the build recorded [path] painting on load, or none.
///
/// Never throws. A missing, stale or mangled manifest is a site without
/// image prefetch, not a link that fails on the way to a tap.
List<String> dvPrefetchImages(String? manifest, String path) {
  if (manifest == null || manifest.isEmpty) return const <String>[];
  final Object? json;
  try {
    json = jsonDecode(manifest);
  } on FormatException {
    return const <String>[];
  }
  if (json is! Map) return const <String>[];
  final Object? routes = json['routes'];
  if (routes is! Map) return const <String>[];
  final Object? route = routes[_routeKey(path)];
  if (route is! Map) return const <String>[];
  final Object? images = route['images'];
  if (images is! List) return const <String>[];
  return <String>[
    for (final Object? image in images)
      if (image case {'url': final String url} when url.isNotEmpty) url,
  ];
}

/// The route as the build names it: no query, no fragment, no trailing
/// slash. `/docs?tab=2` and `/docs/` are the same page.
String _routeKey(String path) {
  String route = Uri.tryParse(path)?.path ?? path;
  if (route.isEmpty) route = '/';
  if (!route.startsWith('/')) route = '/$route';
  if (route.length > 1 && route.endsWith('/')) {
    route = route.substring(0, route.length - 1);
  }
  return route;
}
