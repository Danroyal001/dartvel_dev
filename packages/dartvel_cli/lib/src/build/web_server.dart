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

import 'package:dartvel_core/dartvel.dart' show DVCacheAdapter, DVPageData, DVPageDataCache, DVPageDataMode, DVPageDataResolver, DVPageRequest, DVPageVisibility, DVWebServerSettings, dvFederatedTarget, dvMatchRoute, dvPageChunks, dvRenderPage, dvRenderRoute;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

import 'admin_mount.dart';
import 'admin_serving.dart';

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
  Map<String, String> federated = const <String, String>{},
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
        // A federated module's routes, and where each answers. The
        // specification asks for a micro-site that serves its own HTML while
        // still appearing in the parent's index and sitemap, so the parent
        // answers the path and sends the reader on rather than rendering a
        // page it does not have. The presence of a location is what says so,
        // which is why the parent's own routes carry none.
        for (final MapEntry<String, String> mounted in federated.entries)
          mounted.key: <String, Object?>{'location': mounted.value},
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
            path.endsWith('/index.html') &&
            path != 'index.html' &&
            // The admin's shell is called index.html and is not a route: it
            // is written by this same build into a directory the server
            // reads from, and sweeping it away leaves the mount answering
            // nothing again. It survives the order it is written in today,
            // and would not survive somebody reordering two lines.
            !path.startsWith('__admin/'))
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
  Duration? staleFor,
  bool? streaming,
  DVCacheAdapter? pageStore,
  // The admin, served by the backend rather than compiled into the client.
  // Null is no admin at all, which is what a release build that never asked
  // for one gets: not a disabled route, no route.
  DVAdminMount? admin,
  String? adminRoot,
  Future<bool> Function(Request request)? adminAuthenticated,
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
  // A mounted micro-site's routes, and where each one really answers. The
  // build has written these since federation landed and the deployed backend
  // has acted on them; this server read the same file and skipped the key,
  // so `dartvel preview` handed back the parent's own empty shell for a
  // module path and gave the developer nothing to go on.
  final locations = <String, String>{
    for (final MapEntry<String, Object?> e in routeMap.entries)
      if ((e.value as Map?)?['location'] is String)
        e.key: (e.value as Map)['location'] as String,
  };
  final siteUrl = manifest['siteUrl'] as String?;
  final DVWebServerSettings declared = DVWebServerSettings.parse(manifest['server']);
  final DVPageDataMode mode = pageDataMode ?? declared.pageDataMode;
  final Duration ttl = cacheTtl ?? declared.cacheTtl;
  final Duration stale = staleFor ?? declared.staleFor;
  final bool stream = streaming ?? declared.streaming;
  // Given a store, the kept pages live there rather than in this process,
  // so a second server serves what the first resolved.
  final DVPageDataCache cache = DVPageDataCache(ttl: ttl, staleFor: stale, shared: pageStore);

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

    // The admin, before anything else looks at the path.
    //
    // First because the answer for a hidden admin has to be the same nothing
    // the application returns for a route it does not serve. Falling through
    // to the static handler or the shell would answer a request for the
    // admin with the application's own page, which tells whoever asked that
    // the path means something here.
    if (admin != null) {
      final DVAdminRequest decision = dvAdminFor(
        path,
        admin,
        authenticated: adminAuthenticated == null
            ? false
            : await adminAuthenticated(request),
      );
      switch (decision) {
        case DVAdminRequest.hidden:
          return Response(dvAdminHiddenStatus,
              body: '', headers: dvAdminHiddenHeaders);
        case DVAdminRequest.serve:
          final String root = adminRoot ?? p.join(webRoot, '__admin');
          final String rest = path.substring(admin.path.length);
          final String relative =
              rest.isEmpty || rest == '/' ? 'index.html' : rest.substring(1);
          // A Uri does not normalise dot segments on its own, so this was
          // joined onto the admin root and opened as it arrived:
          // /__studio/../../secrets read a file outside the directory the
          // admin is served from, and on a deployment that directory sits
          // inside the build output next to everything else the server can
          // reach. Refused with the same nothing everything else here
          // answers with, rather than an error naming what was attempted.
          String decoded;
          try {
            // Decoded before it is normalised, so %2e%2e is the same two dots
            // to this check as it is to any proxy in front of it. An invalid
            // escape is not a filename either.
            decoded = Uri.decodeComponent(relative);
          } on ArgumentError {
            return Response(dvAdminHiddenStatus,
                body: '', headers: dvAdminHiddenHeaders);
          }
          final String normalized = p.normalize(decoded.replaceAll('\\', '/'));
          if (normalized.startsWith('..') ||
              normalized.startsWith('/') ||
              p.isAbsolute(normalized)) {
            return Response(dvAdminHiddenStatus,
                body: '', headers: dvAdminHiddenHeaders);
          }
          final File asset = File(p.join(root, normalized));
          if (asset.existsSync()) {
            return Response.ok(asset.readAsBytesSync(), headers: <String, String>{
              'content-type': _adminContentType(normalized),
            });
          }
          // The admin is one application with its own routes, so anything
          // under the mount that is not a file is its shell -- the same
          // rule the site itself follows one branch down.
          final File shell = File(p.join(root, 'index.html'));
          if (!shell.existsSync()) {
            return Response(dvAdminHiddenStatus,
                body: '', headers: dvAdminHiddenHeaders);
          }
          return Response.ok(shell.readAsStringSync(),
              headers: <String, String>{'content-type': 'text/html; charset=utf-8'});
        case DVAdminRequest.notTheAdmin:
          break;
      }
    }

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

    // Federated first, ahead of resolving anything: the page belongs to the
    // module and the parent has no data for it, so asking a resolver would
    // be work thrown away at best and a wrong answer at worst.
    if (locations.isNotEmpty) {
      final DVPageRequest? mounted = dvMatchRoute(cleanPath, locations.keys);
      if (mounted != null) {
        final String target =
            dvFederatedTarget(locations[mounted.pattern]!, mounted);
        if (target.isNotEmpty) {
          return Response.found(target);
        }
        // A location that is not somewhere to send anybody falls through to
        // the ordinary page rather than redirecting: dvFederatedTarget
        // refuses anything that is not http or https with a host, and
        // obeying it anyway is how an open redirect starts.
      }
    }

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
    // the title is on the wire before the body is. Where the cut goes is
    // dvPageChunks' decision rather than this file's, because the backend
    // streams too and two copies of the rule drift.
    // No content-length, so the server sends it chunked; shelf treats an
    // explicit chunked header as a body already encoded, which this is not.
    return Response.ok(
      Stream<List<int>>.fromIterable(
        <List<int>>[for (final String c in dvPageChunks(page)) utf8.encode(c)],
      ),
      headers: htmlHeaders,
    );
  };
}

/// The content type for a file the admin serves.
///
/// A short table rather than a package: the admin is one Flutter web build
/// and these are the kinds it is made of. Serving main.dart.js as
/// text/plain would leave a blank page and a console error about a MIME
/// type, which reads as a broken admin rather than a missing line here.
String _adminContentType(String relative) {
  final String name = relative.toLowerCase();
  if (name.endsWith('.html')) return 'text/html; charset=utf-8';
  if (name.endsWith('.js') || name.endsWith('.mjs')) {
    return 'text/javascript; charset=utf-8';
  }
  if (name.endsWith('.css')) return 'text/css; charset=utf-8';
  if (name.endsWith('.json')) return 'application/json; charset=utf-8';
  if (name.endsWith('.wasm')) return 'application/wasm';
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.svg')) return 'image/svg+xml';
  if (name.endsWith('.woff2')) return 'font/woff2';
  if (name.endsWith('.ttf')) return 'font/ttf';
  return 'application/octet-stream';
}
