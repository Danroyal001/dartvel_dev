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
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';


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

/// The server `dartvel build web-server` is for.
///
/// The static target prerenders a file per route. This one keeps one shell and
/// assembles the page when it is asked for, so a route's title, canonical and
/// crawler-visible text are computed per request rather than baked in.
///
/// Written because `dvServeRoute` had no caller: the build wrote a manifest,
/// deleted the static files it would otherwise have shadowed, and left
/// nothing that read either. `dartvel preview` fell through to files the same
/// build had just removed.
///
/// Assets are served from disk. Anything that is not a file on disk is a
/// route, including paths no route matches — a single-page application owns
/// its own not-found page, and returning the server's would replace it with a
/// blank one.
Handler dvWebServerHandler({
  required String webRoot,
  String? description,
  String? image,
  String? siteName,
}) {
  final manifestFile = File(p.join(webRoot, 'dartvel_routes.json'));
  final shellFile = File(p.join(webRoot, 'index.html'));

  final Map<String, Object?> manifest = manifestFile.existsSync()
      ? (jsonDecode(manifestFile.readAsStringSync()) as Map)
          .cast<String, Object?>()
      : <String, Object?>{};
  final Map<String, Object?> routeMap =
      (manifest['routes'] as Map?)?.cast<String, Object?>() ??
          <String, Object?>{};

  final titles = <String, String>{
    for (final MapEntry<String, Object?> e in routeMap.entries)
      if ((e.value as Map?)?['title'] is String)
        e.key: (e.value as Map)['title'] as String,
  };
  final text = <String, List<String>>{
    for (final MapEntry<String, Object?> e in routeMap.entries)
      e.key: <String>[
        for (final Object? line
            in ((e.value as Map?)?['text'] as List?) ?? const <Object?>[])
          '$line',
      ],
  };
  final siteUrl = manifest['siteUrl'] as String?;

  // dvServeRoute falls back to the site name and then to the path itself, so
  // without one a route nobody declared titles the tab with its own URL. The
  // shell already carries the site's title, written there by the same build.
  String? shellTitle;
  if (shellFile.existsSync()) {
    final match = RegExp(r'<title>(.*?)</title>', dotAll: true)
        .firstMatch(shellFile.readAsStringSync());
    shellTitle = match?.group(1)?.trim();
  }

  final files = createStaticHandler(webRoot);

  return (Request request) async {
    final path = '/${request.url.path}';

    // A file on disk wins, so main.dart.js and the assets are served as
    // themselves. index.html does not: it is the shell, and serving it raw
    // would hand back a page with no route metadata at all.
    final onDisk = File(p.join(webRoot, request.url.path));
    if (request.url.path.isNotEmpty && onDisk.existsSync()) {
      return files(request);
    }

    if (!shellFile.existsSync()) {
      return Response.notFound('No index.html in $webRoot.');
    }

    return Response.ok(
      dvServeRoute(
        shell: shellFile.readAsStringSync(),
        path: path == '/' ? '/' : path.replaceAll(RegExp(r'/+$'), ''),
        routes: titles,
        text: text,
        siteUrl: siteUrl,
        description: description,
        image: image,
        siteName: siteName ?? shellTitle,
      ),
      headers: const <String, String>{
        'content-type': 'text/html; charset=utf-8',
        // Assembled per request, so a cached copy is the thing this target
        // exists to avoid.
        'cache-control': 'no-store',
      },
    );
  };
}
