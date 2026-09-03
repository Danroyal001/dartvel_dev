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

/// How page data is waited for on a request.
enum DVPageDataMode {
  /// Resolved on every request, before the page is sent.
  await_,

  /// Resolved once and kept for the ttl.
  cache,

  /// A kept page is sent at once, stale or not, and refreshed behind it.
  staleWhileRevalidate,

  /// Never resolved on the server; the client renders the data.
  defer,
}

/// `dartvel.web.server` in pubspec.yaml.
class DVWebServerSettings {
  const DVWebServerSettings({
    this.pageDataMode = DVPageDataMode.await_,
    this.cacheTtl = const Duration(seconds: 60),
    this.streaming = false,
    this.cache,
  });

  final DVPageDataMode pageDataMode;
  final Duration cacheTtl;

  /// The head first, the text after: a crawler and a person both see the
  /// title before the data is done.
  final bool streaming;

  /// Where a cache lives when it is shared -- `redis` -- and null for this
  /// process's memory.
  final String? cache;

  static const Map<String, DVPageDataMode> _modes = <String, DVPageDataMode>{
    'await': DVPageDataMode.await_,
    'cache': DVPageDataMode.cache,
    'stale-while-revalidate': DVPageDataMode.staleWhileRevalidate,
    'defer': DVPageDataMode.defer,
  };

  static String _name(DVPageDataMode mode) =>
      _modes.entries.firstWhere((MapEntry<String, DVPageDataMode> e) => e.value == mode).key;

  static DVWebServerSettings parse(Object? section) {
    final Map<Object?, Object?> m = section is Map ? section : const <Object?, Object?>{};
    final Object? ttl = m['cacheTtlSeconds'];
    return DVWebServerSettings(
      pageDataMode: _modes['${m['pageDataMode'] ?? 'await'}'] ?? DVPageDataMode.await_,
      cacheTtl: ttl is num ? Duration(seconds: ttl.toInt()) : const Duration(seconds: 60),
      streaming: m['streaming'] == true,
      cache: m['cache'] is String ? m['cache']! as String : null,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'pageDataMode': _name(pageDataMode),
        'cacheTtlSeconds': cacheTtl.inSeconds,
        'streaming': streaming,
        if (cache != null) 'cache': cache,
      };
}

/// What a request resolved to: the route pattern it matched and the
/// parameters the path filled in.
class DVPageRequest {
  const DVPageRequest({required this.path, required this.pattern, required this.params, this.headers = const <String, String>{}});

  final String path;
  final String pattern;
  final Map<String, String> params;

  /// The request's headers, for a resolver that checks who is asking.
  final Map<String, String> headers;
}

enum DVPageVisibility { public, hidden, unauthorized }

/// A page's data, resolved on request: what the head, the structured data
/// and the crawler-visible text are made from. Every value is untrusted --
/// a title is whatever is in the database -- and escaped where it lands.
class DVPageData {
  const DVPageData({
    required this.title,
    this.description,
    this.image,
    this.favicon,
    this.text = const <String>[],
    this.structuredData,
    this.visibility = DVPageVisibility.public,
  });

  final String title;
  final String? description;
  final String? image;

  /// A favicon for this page, replacing the shell's.
  final String? favicon;
  final List<String> text;

  /// JSON-LD, written as the page's structured data.
  final Map<String, Object?>? structuredData;
  final DVPageVisibility visibility;
}

typedef DVPageDataResolver = FutureOr<DVPageData?> Function(DVPageRequest request);

class _Kept {
  _Kept(this.data, this.at);
  final DVPageData? data;
  final DateTime at;
  bool refreshing = false;
}

/// The path's parameters under [pattern], or null when it does not match.
Map<String, String>? dvRouteParams(String pattern, String path) {
  if (pattern == path) return const <String, String>{};
  if (!pattern.contains(':')) return null;
  final patternParts = pattern.split('/');
  final pathParts = path.split('/');
  if (patternParts.length != pathParts.length) return null;
  final Map<String, String> params = <String, String>{};
  for (var i = 0; i < patternParts.length; i++) {
    final String segment = patternParts[i];
    if (segment.startsWith(':')) {
      params[segment.substring(1)] = Uri.decodeComponent(pathParts[i]);
    } else if (segment != pathParts[i]) {
      return null;
    }
  }
  return params;
}

/// [html] with the page's structured data and favicon in its head.
String dvApplyPageExtras(String html, DVPageData data) {
  var out = html.replaceAll(RegExp(r'<!--dv:ld-->.*?<!--/dv:ld-->\n?', dotAll: true), '');
  if (data.favicon != null) {
    final String href = const HtmlEscape(HtmlEscapeMode.attribute).convert(data.favicon!);
    final RegExp icon = RegExp(r'<link[^>]*rel="(?:shortcut )?icon"[^>]*>');
    out = icon.hasMatch(out)
        ? out.replaceAll(icon, '<link rel="icon" href="$href">')
        : out.replaceFirst('</head>', '<link rel="icon" href="$href">\n</head>');
  }
  final Map<String, Object?>? ld = data.structuredData;
  if (ld != null) {
    // `</` cannot appear inside the script: a value of `</script>` would
    // end it, so the slash is escaped the way JSON allows.
    final String json = jsonEncode(ld).replaceAll('</', '<\\/');
    out = out.replaceFirst('</head>', '<!--dv:ld--><script type="application/ld+json">$json</script><!--/dv:ld-->\n</head>');
  }
  return out;
}

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
  final Map<String, _Kept> kept = <String, _Kept>{};

  /// The data for [path], by the mode: resolved, kept, served stale, or not
  /// asked for at all.
  Future<DVPageData?> resolve(String path, Map<String, String> headers) async {
    final DVPageDataResolver? resolver = pageData;
    if (resolver == null || mode == DVPageDataMode.defer) return null;
    String? pattern;
    Map<String, String>? params;
    for (final String candidate in routeMap.keys) {
      params = dvRouteParams(candidate, path);
      if (params != null) {
        pattern = candidate;
        break;
      }
    }
    if (pattern == null) return null;
    final DVPageRequest request = DVPageRequest(path: path, pattern: pattern, params: params!, headers: headers);

    if (mode == DVPageDataMode.await_) return resolver(request);

    final _Kept? have = kept[path];
    final bool fresh = have != null && DateTime.now().difference(have.at) <= ttl;
    if (have != null && fresh) return have.data;
    if (mode == DVPageDataMode.staleWhileRevalidate && have != null) {
      if (!have.refreshing) {
        have.refreshing = true;
        unawaited(Future<DVPageData?>.value(resolver(request)).then((DVPageData? data) {
          kept[path] = _Kept(data, DateTime.now());
        }).catchError((Object _) {
          have.refreshing = false;
        }));
      }
      return have.data;
    }
    final DVPageData? data = await resolver(request);
    kept[path] = _Kept(data, DateTime.now());
    return data;
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
        : dvApplyPageExtras(
            dvServeRoute(
              shell: shell,
              path: cleanPath,
              routes: <String, String>{cleanPath: data.title},
              text: <String, List<String>>{cleanPath: data.text},
              siteUrl: siteUrl,
              description: data.description ?? description,
              image: data.image ?? image,
              siteName: siteName ?? shellTitle,
            ),
            data,
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
