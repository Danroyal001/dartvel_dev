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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVPageData, DVPageDataCache, DVPageDataMode, DVPageDataResolver, DVPageRequest, DVPageVisibility, DVWebServerSettings, dvMatchRoute, dvRenderPage, dvRenderRoute;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

export 'package:dartvel_core/dartvel.dart' show DVPageData, DVPageDataCache, DVPageDataMode, DVPageDataResolver, DVPageRequest, DVPageVisibility, DVWebServerSettings, dvMatchRoute, dvRenderPage, dvRenderRoute, dvRouteParams;



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
  DVWebServerSettings server = const DVWebServerSettings(),
}) =>
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'siteUrl': siteUrl,
      'server': server.toJson(),
      'routes': <String, Object?>{
        for (final String route in routes)
          route: <String, Object?>{
            'title': titles[route],
            'text': text[route] ?? const <String>[],
          },
      },
    });

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
  final DVPageRequest? matched = dvMatchRoute(path, routes.keys);
  final String title = (matched == null ? null : routes[matched.pattern]) ?? siteName ?? path;
  return dvRenderRoute(
    shell: shell,
    path: path,
    title: title,
    text: matched == null ? const <String>[] : (text[matched.pattern] ?? const <String>[]),
    siteUrl: siteUrl,
    description: description,
    image: image,
    siteName: siteName,
  );
}

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
  DVPageDataResolver? pageData,
  DVPageDataMode? pageDataMode,
  Duration? cacheTtl,
  bool? streaming,
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
  final DVWebServerSettings declared = DVWebServerSettings.parse(manifest['server']);
  final DVPageDataMode mode = pageDataMode ?? declared.pageDataMode;
  final Duration ttl = cacheTtl ?? declared.cacheTtl;
  final bool stream = streaming ?? declared.streaming;
  final DVPageDataCache cache = DVPageDataCache(ttl: ttl);

  /// The data for [path], by the mode: resolved, kept, served stale, or not
  /// asked for at all.
  Future<DVPageData?> resolve(String path, Map<String, String> headers) async {
    final DVPageDataResolver? resolver = pageData;
    if (resolver == null) return null;
    final DVPageRequest? request = dvMatchRoute(path, routeMap.keys, headers: headers);
    if (request == null) return null;
    return cache.resolve(request, resolver, mode);
  }

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

    final String cleanPath = path == '/' ? '/' : path.replaceAll(RegExp(r'/+$'), '');
    final DVPageData? data = await resolve(cleanPath, request.headers);
    const Map<String, String> htmlHeaders = <String, String>{
      'content-type': 'text/html; charset=utf-8',
      // Assembled per request, so a cached copy is the thing this target
      // exists to avoid.
      'cache-control': 'no-store',
    };

    final String shell = shellFile.readAsStringSync();
    // Hidden or unauthorized: the shell with none of the data, and the
    // status that says why, so a crawler indexes nothing and the client can
    // sign the person in.
    if (data != null && data.visibility != DVPageVisibility.public) {
      final String bare = dvServeRoute(
        shell: shell,
        path: cleanPath,
        routes: const <String, String>{},
        text: const <String, List<String>>{},
        siteUrl: siteUrl,
        siteName: siteName ?? shellTitle,
      );
      return Response(data.visibility == DVPageVisibility.hidden ? 404 : 401, body: bare, headers: htmlHeaders);
    }

    final String page = data == null
        ? dvServeRoute(
            shell: shell,
            path: cleanPath,
            routes: titles,
            text: text,
            siteUrl: siteUrl,
            description: description,
            image: image,
            siteName: siteName ?? shellTitle,
          )
        : dvRenderPage(
            shell: shell,
            path: cleanPath,
            data: data,
            siteUrl: siteUrl,
            siteName: siteName ?? shellTitle,
            description: description,
            image: image,
          );

    if (!stream) return Response.ok(page, headers: htmlHeaders);

    // Streamed: the head goes out as its own chunk, the rest after it, so
    // the title is on the wire before the body is.
    final int headEnd = page.indexOf('</head>');
    final List<String> chunks = headEnd < 0
        ? <String>[page]
        : <String>[page.substring(0, headEnd + '</head>'.length), page.substring(headEnd + '</head>'.length)];
    // No content-length, so the server sends it chunked; shelf treats an
    // explicit chunked header as a body already encoded, which this is not.
    return Response.ok(
      Stream<List<int>>.fromIterable(<List<int>>[for (final String c in chunks) utf8.encode(c)]),
      headers: htmlHeaders,
    );
  };
}
