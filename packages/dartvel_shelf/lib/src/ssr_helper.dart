import 'dart:io';
import 'dart:convert';
import 'package:dartvel_core/dartvel.dart'
    show DVCacheAdapter, DVRoutePage, DVServerCrashes, dvStatusPageRoute, dvMinifyHtml, dvRenderRoutePage, DVPageData, DVPageDataCache, DVPageDataResolver, DVPageRequest, DVPageStreaming, DVPageVisibility, DVRoutePreloads, DVSiteSeo, DVWebServerSettings, dvFederatedTarget, dvMatchRoute, dvPageChunks, dvRenderPage, dvRenderRoute, dvRoutePreloadsFile, dvShellFirstChunks, dvWithPreloads, dvWithRequestTenant, dvSignInLocation, dvStudioSessionUserId, DVConfiguredRedirect, dvConfiguredRedirect, DVClientAddress, DVHostedRequest, DVHostSiteFile, DVHosts, dvEffectiveHost, dvHostedRequest, dvHostSiteFileFor;
import 'package:dartvel_core/http.dart';
import 'package:dartvel_core/framework.dart' show dvAssetPath;
import 'package:dartvel_core/framework.dart' show DVRenderedPageCache, DVRenderedPage, dvRenderedPagesGeneration, dvMayCacheRenderedPage, dvRenderedPageKey, dvRenderedPageHeaders, dvRenderedPageNotModified, dvPageResolverIsStatic;

import 'site_files.dart';

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
  Future<Set<String>> Function()? publishedRoutes,
}) =>
    dvWithRequestTenant(
      req,
      () => _cachedSsrFallback(
        req,
        spaRoot,
        pageData: pageData,
        cache: cache,
        pageStore: pageStore,
        publishedRoutes: publishedRoutes,
      ),
    );

Future<Response> _handleSsrFallback(
  Request req,
  String spaRoot, {
  DVPageDataResolver? pageData,
  DVPageDataCache? cache,
  DVCacheAdapter? pageStore,
  Future<Set<String>> Function()? publishedRoutes,
}) async {
  // Read through the source registered for the root: the pack inside a
  // web-server binary, the directory everywhere else.
  final String? shell = dvSiteText(spaRoot, 'index.html');
  if (shell == null) {
    return Response.text('SPA index.html not found', status: 404);
  }

  var html = shell;

  // A web-server build wrote a manifest beside the shell: the page is
  // assembled from it on request, with the route's data from the resolver
  // the backend was started with, by the declared mode.
  if (dvSiteHash(spaRoot, 'dartvel_routes.json') != null) {
    return _fromManifest(req, html, spaRoot: spaRoot, pageData: pageData, cache: cache, pageStore: pageStore, publishedRoutes: publishedRoutes);
  }

  // Check for prerendered metadata
  final route = req.url.path;
  final cleanRoute =
      route == '/' || route.isEmpty ? 'index' : route.substring(1);
  final String? metaPath = dvAssetPath('prerender/$cleanRoute/meta.json');
  final String? metaJson = metaPath == null ? null : dvSiteText(spaRoot, metaPath);

  if (metaJson != null) {
    try {
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

/// Each site's route preloads, with the content hash they were read at.
///
/// Kept rather than read per request, and re-read when the file changes: a
/// deploy writes a new build over the old one, and a server that kept the
/// first list forever would preload the previous build's parts -- files that
/// no longer exist, fetched on every page.
final Map<String, (String, DVRoutePreloads)> _preloads =
    <String, (String, DVRoutePreloads)>{};

DVRoutePreloads _preloadsFor(String spaRoot) {
  final String? hash = dvSiteHash(spaRoot, dvRoutePreloadsFile);
  if (hash == null) {
    _preloads.remove(spaRoot);
    return DVRoutePreloads.none;
  }
  final (String, DVRoutePreloads)? kept = _preloads[spaRoot];
  if (kept != null && kept.$1 == hash) return kept.$2;
  final DVRoutePreloads read = DVRoutePreloads.parse(dvSiteText(spaRoot, dvRoutePreloadsFile)!);
  _preloads[spaRoot] = (hash, read);
  return read;
}

Future<Response> _fromManifest(
  Request req,
  String shell, {
  required String spaRoot,
  required DVPageDataResolver? pageData,
  required DVPageDataCache? cache,
  required DVCacheAdapter? pageStore,
  required Future<Set<String>> Function()? publishedRoutes,
}) async {
  Map<String, Object?> manifest;
  try {
    final Object? decoded = dvSiteJson(spaRoot, 'dartvel_routes.json');
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
  final String raw = _rawPath(req);

  // dartvel.redirects: answered before routing, the guard or any rendering, so
  // a declared address never reaches the application's not-found page. On
  // the path as requested, before any host maps it.
  final DVConfiguredRedirect? redirect = dvConfiguredRedirect(manifest['redirects'], raw);
  if (redirect != null) {
    final String target = req.url.hasQuery && !redirect.to.contains('?') ? '${redirect.to}?${req.url.query}' : redirect.to;
    return Response(redirect.status, headers: Headers()..set('location', target), body: const Stream<List<int>>.empty());
  }

  // dartvel.hosts: the host asked shows a part of the route tree, so `path`
  // is the route the request means and the page is rendered at its own path
  // on the origin of the host that owns it. Without hosts `hosted` is null
  // and every value below is what it always was.
  final DVHosts hosts = DVHosts.fromJson(manifest['hosts']);
  final DVHostedRequest? hosted = hosts.isEmpty
      ? null
      : dvHostedRequest(
          hosts,
          host: _requestHost(req),
          rawPath: raw,
          query: req.url.query,
          isRoute: (String p) => dvMatchRoute(p, routeMap.keys) != null,
        );
  final String? hostedRedirect = hosted?.redirect;
  if (hostedRedirect != null) {
    return Response(301, headers: Headers()..set('location', hostedRedirect), body: const Stream<List<int>>.empty());
  }
  final String path = hosted?.path ?? _trimmed(raw);
  final String pagePath = hosted?.pagePath ?? path;
  final String? pageSiteUrl = hosted?.siteUrl ?? siteUrl;
  final DVSiteSeo pageSite = hosted == null
      ? site
      : DVSiteSeo(
          name: hosted.siteName ?? site.name,
          description: hosted.description ?? site.description,
          image: site.image,
        );

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
        path: pagePath,
        route: route,
        resolving: (cache ?? _cacheFor(spaRoot, settings, pageStore))
            .resolve(matched, pageData, settings.pageDataMode),
        siteUrl: pageSiteUrl,
        site: pageSite,
        preloads: preloads,
      );
      if (early != null) return early;
    }
  }

  DVPageData? data;
  if (pageData != null && matched != null) {
    try {
      data = await (cache ?? _cacheFor(spaRoot, settings, pageStore))
          .resolve(matched, pageData, settings.pageDataMode);
    } catch (error, stack) {
      return _statusPage(500, error, stack, shell: shell, path: pagePath, routeMap: routeMap, siteUrl: pageSiteUrl);
    }
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
  // A guarded route, asked for by nobody signed in: sent to the sign-in page
  // with where they were going, as the client's gate would. Rendering it
  // instead served the page the build captured -- the guarded screen and
  // whatever it showed -- to anybody, before Flutter loaded to redirect.
  // Without a sign-in page to send them to, the bare shell and a 401.
  if (route?['guarded'] == true &&
      (data == null || data.visibility == DVPageVisibility.public) &&
      await dvStudioSessionUserId(req) == null) {
    final Object? signIn = manifest['signIn'];
    if (signIn is String && signIn.isNotEmpty && signIn != path) {
      final String from = '$path${req.url.hasQuery ? '?${req.url.query}' : ''}';
      return Response(
        302,
        headers: Headers()
          ..set('location', _signInLocation(hosted, signIn, from))
          ..set('cache-control', 'no-store'),
        body: const Stream<List<int>>.empty(),
      );
    }
    final String? bareTitle = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(shell)?.group(1)?.trim();
    return _html(dvMinifyHtml(dvRenderRoute(shell: shell, path: pagePath, title: bareTitle ?? pagePath, siteUrl: pageSiteUrl, siteName: pageSite.name ?? bareTitle)), status: 401);
  }
  final String? shellTitle = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(shell)?.group(1)?.trim();
  final String title = route?['title'] is String ? route!['title']! as String : (shellTitle ?? pagePath);
  final List<String> text = <String>[for (final Object? line in (route?['text'] as List?) ?? const <Object?>[]) '$line'];
  // The declared name, and the shell's title only as a last resort: that
  // title is the homepage's, so falling back to it names the site with a
  // sentence in every link preview.
  final String? siteName = pageSite.name ?? shellTitle;

  if (data != null && data.visibility != DVPageVisibility.public) {
    // No description and no image: they describe a page the reader is not
    // being shown.
    final String bare = dvMinifyHtml(dvRenderRoute(shell: shell, path: pagePath, title: shellTitle ?? title, siteUrl: pageSiteUrl, siteName: siteName));
    // Not streamed whatever the declaration says: there is no slow half to
    // wait for, and a refusal is smaller than the chunk framing around it.
    return _html(bare, status: data.visibility == DVPageVisibility.hidden ? 404 : 401);
  }
  // The page as `dartvel build web` renders it, by the same function, from
  // what the build wrote into the manifest. The older fields are for a
  // manifest from before it carried the page.
  final Object? routePage = route?['page'];
  final String page = data == null && routePage is Map
      ? dvRenderRoutePage(shell, DVRoutePage.fromJson(routePage.cast<String, Object?>()).at(pagePath, siteUrl: hosted?.siteUrl),
          onUncaptured: (String r) => stderr.writeln('dartvel: $r has no captured page; serving its source text'))
      : data == null
      ? dvRenderRoute(shell: shell, path: pagePath, title: title, text: text, siteUrl: pageSiteUrl, siteName: siteName, description: pageSite.description, image: site.image)
      : dvRenderPage(shell: shell, path: pagePath, data: data, siteUrl: pageSiteUrl, siteName: siteName, description: pageSite.description, image: site.image);
  // A path nothing serves is a 404, with the shell still the body so the app
  // draws its not-found page. A 200 here was a soft 404 a crawler indexed as
  // a page. A Studio page is a route the manifest does not list, so the
  // published ones are asked first; a manifest listing no routes says
  // nothing about what is missing.
  final bool missing = matched == null &&
      routeMap.isNotEmpty &&
      !(await publishedRoutes?.call() ?? const <String>{}).contains(path);
  return _html(dvMinifyHtml(dvWithPreloads(page, preloads)), status: missing ? 404 : 200, streaming: settings.streaming);
}

/// The page for [path] as three writes, the first before the data: the
/// rendering is [dvShellFirstChunks]', shared with `dartvel dev --release`, and
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

/// The answer to a page request that failed: [code] as the status, the shell
/// as the body so the application still loads, and the captured page of the
/// code's status route in it for a reader with no JavaScript.
///
/// The detail a developer needs goes to the log and to crash reporting; the
/// body never carries it. A build with no status page for the code still
/// answers the code, with the shell's own title rather than the error.
Response _statusPage(
  int code,
  Object error,
  StackTrace stack, {
  required String shell,
  required String path,
  required Map<String, Object?> routeMap,
  required String? siteUrl,
}) {
  DVServerCrashes.record(error, stack);
  stderr
    ..writeln('dartvel: $path answered $code: its page data failed: $error')
    ..writeln(stack);
  final String? route = dvStatusPageRoute(code);
  final Map<String, Object?>? statusRoute =
      route == null ? null : (routeMap[route] as Map?)?.cast<String, Object?>();
  final String? shellTitle = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(shell)?.group(1)?.trim();
  final Object? captured = statusRoute?['page'];
  final String page = captured is Map
      ? dvRenderRoutePage(shell, DVRoutePage.fromJson(captured.cast<String, Object?>()).at(path, siteUrl: siteUrl))
      : dvRenderRoute(
          shell: shell,
          path: path,
          title: statusRoute?['title'] is String ? statusRoute!['title']! as String : (shellTitle ?? '$code'),
          text: <String>[for (final Object? line in (statusRoute?['text'] as List?) ?? const <Object?>[]) '$line'],
          siteUrl: siteUrl,
        );
  return _html(dvMinifyHtml(page), status: code);
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

final Map<String, DVRenderedPageCache> _documents = {};

Future<Response> _cachedSsrFallback(
  Request req,
  String spaRoot, {
  DVPageDataResolver? pageData,
  DVPageDataCache? cache,
  DVCacheAdapter? pageStore,
  Future<Set<String>> Function()? publishedRoutes,
}) async {
  Future<Response> render() => _handleSsrFallback(
    req,
    spaRoot,
    pageData: pageData,
    cache: cache,
    pageStore: pageStore,
    publishedRoutes: publishedRoutes,
  );
  Object? manifest;
  try {
    manifest = dvSiteJson(spaRoot, 'dartvel_routes.json');
  } on FormatException {
    return render();
  }
  final routes = manifest is Map ? manifest['routes'] : null;
  // With dartvel.hosts the route is the one the host maps the path to, and
  // the host decides the document: kept per effective host, which is not
  // always the Host header -- behind a trusted proxy it is the forwarded one.
  final DVHosts hosts =
      DVHosts.fromJson(manifest is Map ? manifest['hosts'] : null);
  final String? effectiveHost = hosts.isEmpty ? null : _requestHost(req);
  final path = hosts.isEmpty
      ? (req.url.path == '/'
          ? '/'
          : req.url.path.replaceAll(RegExp(r'/+$'), ''))
      : dvHostedRequest(
          hosts,
          host: effectiveHost,
          rawPath: _rawPath(req),
          isRoute: (_) => false,
        ).path;
  final matched = routes is Map
      ? dvMatchRoute(path, routes.keys.cast<String>())
      : null;
  final route = matched == null ? null : routes[matched.pattern];
  final headers = req.headers.singleValueMap;
  if (!dvMayCacheRenderedPage(
    req.method,
    headers,
    route is Map ? route : null,
    staticContent: dvPageResolverIsStatic(pageData, matched?.pattern),
  )) {
    return render();
  }
  // A directory can be replaced in place; its content hashes change the key.
  final stamp = [
    spaRoot,
    dvSiteHash(spaRoot, 'index.html'),
    dvSiteHash(spaRoot, 'dartvel_routes.json'),
    dvSiteHash(spaRoot, dvRoutePreloadsFile),
    if (hosts.isNotEmpty) 'host=${hosts.matchOrPrimary(effectiveHost).origin}',
  ].join('|');
  final key = dvRenderedPageKey(stamp, req.url, headers);
  final documents = _documents.putIfAbsent(
    spaRoot,
    () => DVRenderedPageCache(),
  );
  DVRenderedPage? kept = documents.get(key);
  if (kept == null) {
    final generation = dvRenderedPagesGeneration;
    final response = await render();
    if (response.status != 200 ||
        response.headers.has('set-cookie') ||
        (response.headers.get('content-type') ?? '')
                .split(';')
                .first
                .trim()
                .toLowerCase() !=
            'text/html') {
      return response;
    }
    final bytes = await response.body?.bytes() ?? <int>[];
    final keptHeaders = {
      ...response.headers.singleValueMap,
      ...dvRenderedPageHeaders(bytes),
    };
    documents.put(
      key,
      bytes,
      keptHeaders,
      status: response.status,
      generation: generation,
    );
    kept = DVRenderedPage(bytes, keptHeaders);
  }
  final notModified = dvRenderedPageNotModified(
    req.headers.get('if-none-match'),
    kept.headers['etag']!,
  );
  return Response(
    notModified ? 304 : 200,
    headers: Headers(kept.headers),
    body: notModified
        ? const Stream<List<int>>.empty()
        : Stream<List<int>>.value(kept.bytes),
  );
}

/// The request's path with a leading `/`, `/` when empty.
String _rawPath(Request req) => req.url.path.isEmpty
    ? '/'
    : (req.url.path.startsWith('/') ? req.url.path : '/${req.url.path}');

/// [raw] without trailing slashes, as a route is matched.
String _trimmed(String raw) => raw == '/' ? '/' : raw.replaceAll(RegExp(r'/+$'), '');

/// The host [req] was made for: `X-Forwarded-Host` from a peer
/// `dartvel.server.trustedProxies` trusts, `Host` otherwise. The trust is
/// the client-address resolver's, so there is one list of trusted proxies.
String? _requestHost(Request req) {
  final List<String> forwarded = req.headers.getAll('x-forwarded-host').toList();
  return dvEffectiveHost(
    host: req.headers.get('host'),
    forwardedHost: forwarded.isEmpty ? null : forwarded.join(','),
    peerIsTrustedProxy: DVClientAddress.current.peerIsTrusted(req),
  );
}

/// Where a signed-out request for a guarded route goes: the sign-in page,
/// at its public URL when the site has hosts -- it may be on another host
/// from the one asked.
String _signInLocation(DVHostedRequest? hosted, String signIn, String from) {
  final String location = dvSignInLocation(signIn, from);
  if (hosted == null) return location;
  final Uri uri = Uri.parse(location);
  return hosted.publicUrl(uri.path, query: uri.query);
}

/// `/robots.txt` and `/sitemap.xml` for the host asked, when the site's
/// manifest declares `dartvel.hosts`; null for any other path, and for a
/// site without hosts, whose files are served as they were built.
///
/// The build writes one sitemap listing every page's public URL. Each host
/// is answered with the entries on its own origin, and a robots.txt naming
/// its own sitemap. A host that serves no route at all -- a wildcard label
/// nothing is published under -- has neither. An unknown host is the
/// primary, as it is for pages.
Future<Response?> dvHostSiteFile(Request req, String spaRoot) async {
  final String path = _rawPath(req);
  if (path != '/robots.txt' && path != '/sitemap.xml') return null;
  final Object? manifest;
  try {
    manifest = dvSiteJson(spaRoot, 'dartvel_routes.json');
  } on FormatException {
    return null;
  }
  if (manifest is! Map) return null;
  final DVHosts hosts = DVHosts.fromJson(manifest['hosts']);
  if (hosts.isEmpty) return null;
  final Object? routes = manifest['routes'];
  final DVHostSiteFile? file = dvHostSiteFileFor(
    hosts,
    host: _requestHost(req),
    path: path,
    patterns: routes is Map ? routes.keys.map((Object? k) => '$k') : const <String>[],
    robots: dvSiteText(spaRoot, 'robots.txt'),
    sitemap: dvSiteText(spaRoot, 'sitemap.xml'),
  );
  if (file == null) return null;
  return Response.text(
    file.body,
    status: file.status,
    headers: Headers()
      ..set('content-type', file.contentType)
      ..set('cache-control', file.status == 200 ? 'public, no-cache' : 'no-store'),
  );
}
