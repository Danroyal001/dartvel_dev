/// `dartvel build web-server` — the same pages, decided per request.
///
/// `dartvel build web` writes a file per route: head tags, page text, sitemap,
/// robots, all fixed at build time. That is right for a static host and wrong
/// the moment a page depends on something that changes. A model-backed page is
/// stale the instant it is written, and a parameterised route cannot be
/// written at all — `/post/:id` is a shape, not a document.
///
/// This target produces the same pages from the same pieces, on request. What
/// differs is *when*, not *what*: the bundle carries no per-route HTML, and
/// the server carries a manifest it can build one from for any path it is
/// asked for.
library;

import 'dart:convert';

import 'page_text.dart';
import 'seo_head.dart';
import 'static_seo.dart';

/// What a web-server build writes, as against a static one.
class DVWebServerPlan {
  const DVWebServerPlan({
    required this.writesPerRouteHtml,
    required this.writesManifest,
    required this.writesSitemap,
    required this.writesRobots,
  });

  /// False. The server writes those, which is the whole point.
  final bool writesPerRouteHtml;

  /// True. It is what the server builds pages from.
  final bool writesManifest;

  /// Both are one document that does not vary by request, so generating them
  /// per fetch would be work for nothing.
  final bool writesSitemap;
  final bool writesRobots;
}

DVWebServerPlan dvWebServerPlan({required List<String> routes}) =>
    const DVWebServerPlan(
      writesPerRouteHtml: false,
      writesManifest: true,
      writesSitemap: true,
      writesRobots: true,
    );

/// The manifest the server reads.
///
/// Every route, including the parameterised ones a static build has to skip:
/// the server can serve `/post/:id` and the file writer cannot, which is the
/// difference this target exists for.
String dvWebServerManifest({
  required List<String> routes,
  required Map<String, String> titles,
  required Map<String, List<String>> text,
  required String? siteUrl,
}) =>
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'siteUrl': siteUrl,
      'routes': <String, Object?>{
        for (final String route in routes)
          route: <String, Object?>{
            'title': titles[route],
            'text': text[route] ?? const <String>[],
          },
      },
    });

/// Build the page for [path].
///
/// The canonical is the URL that was asked for rather than the pattern that
/// matched it: `/post/hello-world` canonicalises to itself, not to
/// `/post/:id`, which is not a URL anyone can visit.
String dvServeRoute({
  required String shell,
  required String path,
  required Map<String, String> routes,
  required Map<String, List<String>> text,
  required String? siteUrl,
  String? description,
  String? image,
  String? siteName,
}) {
  final matched = _match(path, routes.keys);
  final title = (matched == null ? null : routes[matched]) ?? siteName ?? path;

  final html = dvSeoApply(
    shell,
    dvSeoHead(
      title: title,
      description: description,
      siteUrl: siteUrl == null ? null : dvStaticCanonical(siteUrl, path),
      image: image,
      siteName: siteName,
    ),
  );

  final lines = matched == null ? const <String>[] : (text[matched] ?? const <String>[]);
  return dvApplyPageText(html, lines);
}

/// The route pattern that covers [path], preferring an exact match.
///
/// Exact first, because `/post/new` should reach a real `/post/new` route
/// rather than being read as an id.
String? _match(String path, Iterable<String> patterns) {
  if (patterns.contains(path)) return path;

  for (final String pattern in patterns) {
    if (!pattern.contains(':')) continue;
    final patternParts = pattern.split('/');
    final pathParts = path.split('/');
    if (patternParts.length != pathParts.length) continue;

    var matches = true;
    for (var i = 0; i < patternParts.length; i++) {
      final segment = patternParts[i];
      if (segment.startsWith(':')) continue;
      if (segment != pathParts[i]) {
        matches = false;
        break;
      }
    }
    if (matches) return pattern;
  }
  return null;
}

/// Per-route HTML left behind by a previous static build.
///
/// A directory that held one still has `/docs/index.html` in it, and a server
/// that falls through to a file serves that instead of the page it just
/// rendered. The stale copy shadows the live one, and the symptom is a page
/// that will not update however many times it is deployed.
///
/// The root `index.html` is kept: it is the shell the server renders into.
/// Nothing else is touched, because deleting more than the pages would take
/// the application with them.
List<String> dvWebServerStaleFiles({required List<String> present}) =>
    present
        .where((String path) =>
            path.endsWith('/index.html') && path != 'index.html')
        .toList();
