import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:dartvel_core/dartvel.dart'
    show DVPageData, DVPageDataCache, DVPageDataResolver, DVPageRequest, DVPageVisibility, DVWebServerSettings, dvMatchRoute, dvRenderPage, dvRenderRoute;
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
Future<Response> handleSsrFallback(
  Request req,
  String spaRoot, {
  DVPageDataResolver? pageData,
  DVPageDataCache? cache,
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
    return _fromManifest(req, html, manifestFile, pageData: pageData, cache: cache ?? _defaultCache);
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

/// The kept pages for the process, when the caller keeps none of its own.
final DVPageDataCache _defaultCache = DVPageDataCache();

Future<Response> _fromManifest(
  Request req,
  String shell,
  File manifestFile, {
  required DVPageDataResolver? pageData,
  required DVPageDataCache cache,
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
  final DVWebServerSettings settings = DVWebServerSettings.parse(manifest['server']);
  final String raw = req.url.path.isEmpty ? '/' : (req.url.path.startsWith('/') ? req.url.path : '/${req.url.path}');
  final String path = raw == '/' ? '/' : raw.replaceAll(RegExp(r'/+$'), '');

  final DVPageRequest? matched = dvMatchRoute(path, routeMap.keys, headers: req.headers.singleValueMap);
  DVPageData? data;
  if (pageData != null && matched != null) {
    data = await cache.resolve(matched, pageData, settings.pageDataMode);
  }

  final Map<String, Object?>? route = matched == null ? null : (routeMap[matched.pattern] as Map?)?.cast<String, Object?>();
  final String? shellTitle = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(shell)?.group(1)?.trim();
  final String title = route?['title'] is String ? route!['title']! as String : (shellTitle ?? path);
  final List<String> text = <String>[for (final Object? line in (route?['text'] as List?) ?? const <Object?>[]) '$line'];

  if (data != null && data.visibility != DVPageVisibility.public) {
    final String bare = dvRenderRoute(shell: shell, path: path, title: shellTitle ?? title, siteUrl: siteUrl, siteName: shellTitle);
    return _html(bare, status: data.visibility == DVPageVisibility.hidden ? 404 : 401);
  }
  final String page = data == null
      ? dvRenderRoute(shell: shell, path: path, title: title, text: text, siteUrl: siteUrl, siteName: shellTitle)
      : dvRenderPage(shell: shell, path: path, data: data, siteUrl: siteUrl, siteName: shellTitle);
  return _html(page);
}

Response _html(String page, {int status = 200}) {
  final headers = Headers()
    ..set('content-type', 'text/html; charset=utf-8')
    ..set('cache-control', 'no-store');
  return Response(status, headers: headers, body: Stream<List<int>>.value(utf8.encode(page)));
}

/// Escape a prerendered value for interpolation into HTML.
///
/// `HtmlEscape` covers `&`, `<`, `>`, `"` and `'`, which is the whole set that
/// matters for both element text and an attribute value.
String _escape(String value) => const HtmlEscape().convert(value);
