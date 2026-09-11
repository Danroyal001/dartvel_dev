import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:dartvel_core/dartvel.dart'
    show DVCacheAdapter, DVPageData, DVPageDataCache, DVPageDataResolver, DVPageRequest, DVPageStreaming, DVPageVisibility, DVRoutePreloads, DVSiteSeo, DVWebServerSettings, dvFederatedTarget, dvMatchRoute, dvPageChunks, dvRenderPage, dvRenderRoute, dvRoutePreloadsFile, dvShellFirstChunks, dvWithPreloads, dvWithRequestTenant;
import 'package:dartvel_core/http.dart';

/// Serve the single-page app's index, with any prerendered metadata for this
/// route injected into it.
///
/// Two things here are deliberate rather than incidental.
///
/// The prerendered values are escaped. `meta.json` is written by prerendering
/// model pages, so a title is whatever is in the database -- a title of
/// `</title><script>...` interpolated raw closes the element and runs.
///
/// The page is encoded as UTF-8 rather than written out as `codeUnits`, which
/// is UTF-16: `é` came out as the single byte 233, which is not a valid UTF-8
/// lead byte, and anything above U+00FF came out as a value that is not a byte
/// at all. ASCII pages looked correct throughout, which is how it survived.
/// The tenant is resolved here and nowhere else on this path. Rendering
/// calls the application's page data resolver, which queries models --
/// tenant-scoped ones included -- and that ran under whatever tenant the
/// process happened to be set to. A customer on their own subdomain was
/// served the default tenant's rows in the title, the description, the
/// structured data and the crawler text, and a crawler indexed them there.
Future<Response> handleSsrFallback(
  Request req,
  String spaRoot, {
  DVPageDataResolver? pageData,
  DVPageDataCache? cache,
  DVCacheAdapter? pageStore,
}) =>
    dvWithRequestTenant(
      req,
      () => _handleSsrFallback(
        req,
        spaRoot,
        pageData: pageData,
        cache: cache,
        pageStore: pageStore,
      ),
    );

Future<Response> _handleSsrFallback(
  Request req,
  String spaRoot, {
  DVPageDataResolver? pageData,
  DVPageDataCache? cache,
  DVCacheAdapter? pageStore,
}) async {
  final indexFile = File(p.join(spaRoot, 'index.html'));
  if (!await indexFile.exists()) {
    return Response.text('SPA index.html not found', status: 404);
  }

  var html = await indexFile.readAsString();

  // A web-server build wrote a manifest beside the shell: the page is
  // assembled from it on request, with the route's data from the resolver
  // the backend was started with, by the declared mode.
  final manifestFile = File(p.join(spaRoot, 'dartvel_routes.json'));
  if (await manifestFile.exists()) {
    return _fromManifest(req, html, manifestFile, spaRoot: spaRoot, pageData: pageData, cache: cache, pageStore: pageStore);
  }

  // Check for prerendered metadata
  final route = req.url.path;
  final cleanRoute =
      route == '/' || route.isEmpty ? 'index' : route.substring(1);
  final metaFile = File(p.join(spaRoot, 'prerender', cleanRoute, 'meta.json'));

  if (await metaFile.exists()) {
    try {
      final metaJson = await metaFile.readAsString();
      final meta = jsonDecode(metaJson) as Map<String, dynamic>;

      final title = meta['title'] as String?;
      final content = meta['content'] as String?;

      if (title != null) {
        html = html.replaceFirst(RegExp(r'<title>.*?</title>'),
            '<title>${_escape(title)}</title>');
      }

      if (content != null) {
        // Inject semantic prerendered content before the Flutter bootstrap.
        final injection =
            '<div id="semantic-content" style="position:absolute;left:-9999px;'
            'top:auto;width:1px;height:1px;overflow:hidden;">'
            '${_escape(content)}</div>';
        html = html.replaceFirst('</body>', '$injection</body>');
      }

      // Inject defer to main.dart.js if not present (optional, usually build handles it)
      // html = html.replaceFirst('src="main.dart.js"', 'src="main.dart.js" defer');
    } catch (_) {
      // Keep serving the original HTML if optional SSR content injection fails.
    }
  }

  final headers = Headers()
    ..set('content-type', 'text/html; charset=utf-8');
  return Response(200,
      headers: headers, body: Stream<List<int>>.value(utf8.encode(html)));
}

/// The kept pages, one cache per site, built from what that site's manifest
/// declares: a cache built before the manifest is read would keep every
/// page for the default sixty seconds however long the declaration says.
final Map<String, DVPageDataCache> _caches = <String, DVPageDataCache>{};

DVPageDataCache _cacheFor(String spaRoot, DVWebServerSettings settings, DVCacheAdapter? store) =>
    _caches.putIfAbsent(
      spaRoot,
      () => DVPageDataCache(ttl: settings.cacheTtl, staleFor: settings.staleFor, shared: store),
    );

/// Each site's route preloads, with the modification time they were read at.
///
/// Kept rather than read per request, and re-read when the file changes: a
/// deploy writes a new build over the old one, and a server that kept the
/// first list forever would preload the previous build's parts -- files that
/// no longer exist, fetched on every page.
final Map<String, (DateTime, DVRoutePreloads)> _preloads =
    <String, (DateTime, DVRoutePreloads)>{};

DVRoutePreloads _preloadsFor(String spaRoot) {
  final File file = File(p.join(spaRoot, dvRoutePreloadsFile));
  final FileStat stat = file.statSync();
  if (stat.type == FileSystemEntityType.notFound) {
    _preloads.remove(spaRoot);
    return DVRoutePreloads.none;
  }
  final (DateTime, DVRoutePreloads)? kept = _preloads[spaRoot];
  if (kept != null && kept.$1 == stat.modified) return kept.$2;
  final DVRoutePreloads read = DVRoutePreloads.parse(file.readAsStringSync());
  _preloads[spaRoot] = (stat.modified, read);
  return read;
}

Future<Response> _fromManifest(
  Request req,
  String shell,
  File manifestFile, {
  required String spaRoot,
  required DVPageDataResolver? pageData,
  required DVPageDataCache? cache,
  required DVCacheAdapter? pageStore,
}) async {
  Map<String, Object?> manifest;
  try {
    final Object? decoded = jsonDecode(await manifestFile.readAsString());
    manifest = decoded is Map ? decoded.cast<String, Object?>() : <String, Object?>{};
  } on FormatException {
    manifest = <String, Object?>{};
  }
  final Map<String, Object?> routeMap =
      (manifest['routes'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
  final String? siteUrl = manifest['siteUrl'] as String?;
  // What dartvel.seo declared. Rendering a route replaces the head block the
  // build wrote into the shell, so without these every served page came out
  // with no description, no image and no site name -- less than the shell it
  // was rendered from, and no worse-looking in a browser.
  final DVSiteSeo site = DVSiteSeo.parse(manifest['site']);
  final DVWebServerSettings settings = DVWebServerSettings.parse(manifest['server']);
  final String raw = req.url.path.isEmpty ? '/' : (req.url.path.startsWith('/') ? req.url.path : '/${req.url.path}');
  final String path = raw == '/' ? '/' : raw.replaceAll(RegExp(r'/+$'), '');

  final DVPageRequest? matched = dvMatchRoute(path, routeMap.keys, headers: req.headers.singleValueMap);
  // The route's own deferred parts and first-frame images, by the pattern it
  // matched. They depend on the route and never on the data, so they go in
  // whatever part of the head goes first.
  final String preloads = matched == null
      ? ''
      : _preloadsFor(spaRoot).linksFor(matched.pattern, shell: shell);

  // `streaming: shell`: the head goes out before the data exists. Only where
  // nothing about the answer depends on the data -- not a guarded route, whose
  // status does, and not a federated one, which is a redirect.
  if (settings.streamingMode == DVPageStreaming.shell && pageData != null && matched != null) {
    final Map<String, Object?>? route = (routeMap[matched.pattern] as Map?)?.cast<String, Object?>();
    if (route?['guarded'] != true && route?['location'] is! String) {
      final Response? early = _shellFirst(
        shell: shell,
        path: path,
        route: route,
        resolving: (cache ?? _cacheFor(spaRoot, settings, pageStore))
            .resolve(matched, pageData, settings.pageDataMode),
        siteUrl: siteUrl,
        site: site,
        preloads: preloads,
      );
      if (early != null) return early;
    }
  }

  DVPageData? data;
  if (pageData != null && matched != null) {
    data = await (cache ?? _cacheFor(spaRoot, settings, pageStore))
        .resolve(matched, pageData, settings.pageDataMode);
  }

  final Map<String, Object?>? route = matched == null ? null : (routeMap[matched.pattern] as Map?)?.cast<String, Object?>();

  // A federated module's route: the parent answers the path and sends the
  // reader on, and the module serves its own HTML from there. Listed in the
  // sitemap and unanswered, a crawler following the link would get the
  // parent's not-found page; answered and unlisted, nobody would find it.
  final Object? location = route?['location'];
  if (matched != null && location is String) {
    final String target = dvFederatedTarget(location, matched);
    if (target.isNotEmpty) {
      return Response(
        302,
        headers: Headers()..set('location', target),
      );
    }
  }
  final String? shellTitle = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(shell)?.group(1)?.trim();
  final String title = route?['title'] is String ? route!['title']! as String : (shellTitle ?? path);
  final List<String> text = <String>[for (final Object? line in (route?['text'] as List?) ?? const <Object?>[]) '$line'];
  // The declared name, and the shell's title only as a last resort: that
  // title is the homepage's, so falling back to it names the site with a
  // sentence in every link preview.
  final String? siteName = site.name ?? shellTitle;

  if (data != null && data.visibility != DVPageVisibility.public) {
    // No description and no image: they describe a page the reader is not
    // being shown.
    final String bare = dvRenderRoute(shell: shell, path: path, title: shellTitle ?? title, siteUrl: siteUrl, siteName: siteName);
    // Not streamed whatever the declaration says: there is no slow half to
    // wait for, and a refusal is smaller than the chunk framing around it.
    return _html(bare, status: data.visibility == DVPageVisibility.hidden ? 404 : 401);
  }
  final String page = data == null
      ? dvRenderRoute(shell: shell, path: path, title: title, text: text, siteUrl: siteUrl, siteName: siteName, description: site.description, image: site.image)
      : dvRenderPage(shell: shell, path: path, data: data, siteUrl: siteUrl, siteName: siteName, description: site.description, image: site.image);
  return _html(dvWithPreloads(page, preloads), streaming: settings.streaming);
}

/// The page for [path] as three writes, the first before the data: the
/// rendering is [dvShellFirstChunks]', shared with `dartvel preview`, and
/// this is the response around it. Null when the shell has no head to split,
/// and the caller falls back to waiting for the data.
Response? _shellFirst({
  required String shell,
  required String path,
  required Map<String, Object?>? route,
  required Future<DVPageData?> resolving,
  required String? siteUrl,
  required DVSiteSeo site,
  required String preloads,
}) {
  final String? shellTitle = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(shell)?.group(1)?.trim();
  final String title = route?['title'] is String ? route!['title']! as String : (shellTitle ?? path);
  final Stream<String>? chunks = dvShellFirstChunks(
    shell: shell,
    path: path,
    title: title,
    text: <String>[for (final Object? line in (route?['text'] as List?) ?? const <Object?>[]) '$line'],
    refusedTitle: shellTitle ?? title,
    resolving: resolving,
    siteUrl: siteUrl,
    siteName: site.name ?? shellTitle,
    description: site.description,
    image: site.image,
    preloads: preloads,
  );
  if (chunks == null) return null;

  return Response(
    200,
    headers: Headers()
      ..set('content-type', 'text/html; charset=utf-8')
      ..set('cache-control', 'no-store'),
    isStream: true,
    body: chunks.map<List<int>>(utf8.encode),
  );
}

Response _html(String page, {int status = 200, bool streaming = false}) {
  final headers = Headers()
    ..set('content-type', 'text/html; charset=utf-8')
    ..set('cache-control', 'no-store');
  if (!streaming) {
    return Response(status, headers: headers, body: Stream<List<int>>.value(utf8.encode(page)));
  }
  // The head as its own write, so the title is on the wire before the body
  // is. `isStream` is what makes that survive the trip out: the runtime
  // gathers the whole body of anything it is not told is a stream and sends
  // it with a content-length, which puts the split back together again and
  // leaves the setting doing nothing.
  return Response(
    status,
    headers: headers,
    isStream: true,
    body: Stream<List<int>>.fromIterable(
      <List<int>>[for (final String chunk in dvPageChunks(page)) utf8.encode(chunk)],
    ),
  );
}

/// Escape a prerendered value for interpolation into HTML.
///
/// `HtmlEscape` covers `&`, `<`, `>`, `"` and `'`, which is the whole set that
/// matters for both element text and an attribute value.
String _escape(String value) => const HtmlEscape().convert(value);
