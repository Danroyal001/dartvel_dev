/// Page data on request: the Web Server Rendering pipeline's pure parts.
///
/// Request received, route resolved, page data resolved, auth and
/// visibility checked, SEO and structured data generated, favicon selected,
/// raw semantic text generated, Flutter bootstrap embedded. The preview
/// server and the generated backend's server both render through these,
/// so the page a developer previews is the page the server sends.
library;

import 'dart:async';
import 'dart:convert';

import '../cache/adapters.dart';
import 'page_text.dart';
import 'seo_head.dart';

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
    Duration? staleFor,
    this.streaming = false,
    this.cache,
  }) : _staleFor = staleFor;

  final DVPageDataMode pageDataMode;
  final Duration cacheTtl;

  final Duration? _staleFor;

  /// How long past the ttl a kept page may still be served while it is
  /// refreshed behind the response. The ttl again unless the declaration
  /// says otherwise: a stale window of nothing makes
  /// stale-while-revalidate mean the same as awaiting.
  Duration get staleFor => _staleFor ?? cacheTtl;

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
    final Object? stale = m['staleForSeconds'];
    return DVWebServerSettings(
      pageDataMode: _modes['${m['pageDataMode'] ?? 'await'}'] ?? DVPageDataMode.await_,
      cacheTtl: ttl is num ? Duration(seconds: ttl.toInt()) : const Duration(seconds: 60),
      staleFor: stale is num ? Duration(seconds: stale.toInt()) : null,
      streaming: m['streaming'] == true,
      cache: m['cache'] is String ? m['cache']! as String : null,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'pageDataMode': _name(pageDataMode),
        'cacheTtlSeconds': cacheTtl.inSeconds,
        'staleForSeconds': staleFor.inSeconds,
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

  /// The page as JSON, for a cache shared between servers.
  Map<String, Object?> toJson() => <String, Object?>{
        'title': title,
        if (description != null) 'description': description,
        if (image != null) 'image': image,
        if (favicon != null) 'favicon': favicon,
        if (text.isNotEmpty) 'text': text,
        if (structuredData != null) 'structuredData': structuredData,
        if (visibility != DVPageVisibility.public) 'visibility': visibility.name,
      };

  /// A page from what [toJson] wrote. Throws [FormatException] for anything
  /// that is not one, so a cache holding something else is ignored rather
  /// than served as a page with no title.
  factory DVPageData.fromJson(Map<String, Object?> json) {
    final Object? title = json['title'];
    if (title is! String) {
      throw const FormatException('a kept page has no title, so it is not a page');
    }
    return DVPageData(
      title: title,
      description: json['description'] as String?,
      image: json['image'] as String?,
      favicon: json['favicon'] as String?,
      text: <String>[for (final Object? line in (json['text'] as List?) ?? const <Object?>[]) '$line'],
      structuredData: json['structuredData'] is Map
          ? (json['structuredData']! as Map).cast<String, Object?>()
          : null,
      visibility: DVPageVisibility.values.firstWhere(
        (DVPageVisibility v) => v.name == json['visibility'],
        orElse: () => DVPageVisibility.public,
      ),
    );
  }
}

typedef DVPageDataResolver = FutureOr<DVPageData?> Function(DVPageRequest request);

/// The path's parameters under [pattern], or null when it does not match.
Map<String, String>? dvRouteParams(String pattern, String path) {
  if (pattern == path) return const <String, String>{};
  if (!pattern.contains(':')) return null;
  final List<String> patternParts = pattern.split('/');
  final List<String> pathParts = path.split('/');
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

/// The first of [patterns] that [path] matches, with its parameters.
DVPageRequest? dvMatchRoute(String path, Iterable<String> patterns, {Map<String, String> headers = const <String, String>{}}) {
  for (final String pattern in patterns) {
    final Map<String, String>? params = dvRouteParams(pattern, path);
    if (params != null) return DVPageRequest(path: path, pattern: pattern, params: params, headers: headers);
  }
  return null;
}

/// [siteUrl] joined with [path], no trailing slash.
String dvCanonicalUrl(String siteUrl, String path) {
  final String base = siteUrl.replaceAll(RegExp(r'/+$'), '');
  final String trimmed = path.replaceAll(RegExp(r'/+$'), '');
  return trimmed.isEmpty ? base : '$base$trimmed';
}

/// The shell as the page for [path]: the head from [title] and the rest,
/// the crawler-visible text from [text].
String dvRenderRoute({
  required String shell,
  required String path,
  required String title,
  List<String> text = const <String>[],
  String? siteUrl,
  String? description,
  String? image,
  String? siteName,
}) {
  // The image is made absolute against the site, not against the page's
  // own URL: joined to the canonical it pointed at /products/1/img/x.png,
  // which is not where the asset is.
  final String html = dvSeoApply(
    shell,
    dvSeoHead(
      title: title,
      description: description,
      siteUrl: siteUrl == null ? null : dvCanonicalUrl(siteUrl, path),
      image: dvAbsoluteAsset(image, siteUrl),
      siteName: siteName,
    ),
  );
  return dvApplyPageText(html, text);
}

/// The shell as the page for [path] from [data]: the head, the text, the
/// structured data and the favicon, all from the data.
String dvRenderPage({
  required String shell,
  required String path,
  required DVPageData data,
  String? siteUrl,
  String? siteName,
  String? description,
  String? image,
}) =>
    dvApplyPageExtras(
      dvRenderRoute(
        shell: shell,
        path: path,
        title: data.title,
        text: data.text,
        siteUrl: siteUrl,
        description: data.description ?? description,
        image: data.image ?? image,
        siteName: siteName,
      ),
      data,
    );

/// [html] with the page's structured data and favicon in its head. Marked,
/// so rendering the same page again replaces rather than adds.
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
    final String json = jsonEncode(ld).replaceAll('</', r'<\/');
    out = out.replaceFirst('</head>', '<!--dv:ld--><script type="application/ld+json">$json</script><!--/dv:ld-->\n</head>');
  }
  return out;
}

class _Kept {
  const _Kept(this.data, this.at);
  final DVPageData? data;
  final DateTime at;

  Map<String, Object?> toJson() => <String, Object?>{
        'at': at.toUtc().toIso8601String(),
        'data': data?.toJson(),
      };

  static _Kept fromJson(Map<String, Object?> json) {
    final DateTime? at = DateTime.tryParse('${json['at']}');
    if (at == null) throw const FormatException('a kept page does not say when it was kept');
    final Object? data = json['data'];
    return _Kept(data is Map ? DVPageData.fromJson(data.cast<String, Object?>()) : null, at);
  }
}

/// The kept pages the modes work on: one per path, with when it was kept.
///
/// In this process by default. Given a [shared] store -- any DVCacheAdapter,
/// so redis on a deployment that has one -- the pages go there instead, and
/// the next server serves what this one kept rather than resolving every
/// page for itself. A page is fresh for [ttl] and servable stale for
/// [staleFor] after that; past both it is gone rather than served as a page
/// from an hour ago.
class DVPageDataCache {
  DVPageDataCache({
    this.ttl = const Duration(seconds: 60),
    Duration? staleFor,
    DateTime Function()? now,
    this.shared,
    this.prefix = 'dv:page:',
  })  : staleFor = staleFor ?? ttl,
        _now = now ?? DateTime.now;

  final Duration ttl;

  /// How long past [ttl] a page may still be served while it is refreshed.
  final Duration staleFor;

  /// Where the pages are kept, when they are not kept in this process.
  final DVCacheAdapter? shared;

  /// What the shared store's keys begin with, so pages cannot collide with
  /// whatever else the application keeps there.
  final String prefix;

  final DateTime Function() _now;
  final Map<String, _Kept> _kept = <String, _Kept>{};

  /// Paths this process is already refreshing, so one server does not ask
  /// the database twice for the same stale page. Two servers may each
  /// refresh once, which costs one query and no correctness.
  final Set<String> _refreshing = <String>{};

  /// The data for [request] by [mode]: resolved, kept, served stale, or not
  /// asked for at all.
  Future<DVPageData?> resolve(DVPageRequest request, DVPageDataResolver resolver, DVPageDataMode mode) async {
    if (mode == DVPageDataMode.defer) return null;
    if (mode == DVPageDataMode.await_) return resolver(request);

    final String key = request.path;
    final _Kept? have = await _read(key);
    if (have != null && _now().difference(have.at) <= ttl) return have.data;
    if (mode == DVPageDataMode.staleWhileRevalidate && have != null) {
      if (_refreshing.add(key)) {
        unawaited(Future<DVPageData?>.value(resolver(request)).then((DVPageData? data) async {
          await _write(key, data);
        }).whenComplete(() => _refreshing.remove(key)));
      }
      return have.data;
    }
    final DVPageData? data = await resolver(request);
    await _write(key, data);
    return data;
  }

  /// The kept page for [key], or null when there is none, when it is too
  /// old even to be stale, or when what is there is not a page.
  Future<_Kept?> _read(String key) async {
    final DVCacheAdapter? store = shared;
    _Kept? kept;
    if (store == null) {
      kept = _kept[key];
    } else {
      final Object? raw = await store.read('$prefix$key');
      if (raw == null) return null;
      try {
        final Object? decoded = jsonDecode('$raw');
        if (decoded is! Map) return null;
        kept = _Kept.fromJson(decoded.cast<String, Object?>());
      } on FormatException {
        // Something else is under this key. Ignored rather than served.
        return null;
      }
    }
    if (kept == null) return null;
    return _now().difference(kept.at) > ttl + staleFor ? null : kept;
  }

  Future<void> _write(String key, DVPageData? data) async {
    final _Kept kept = _Kept(data, _now());
    final DVCacheAdapter? store = shared;
    if (store == null) {
      _kept[key] = kept;
      return;
    }
    // Kept past the ttl so it can be served stale while it is refreshed;
    // an entry that expired on the ttl would leave nothing to serve.
    //
    // A lifetime of nothing is a page that cannot be kept, and a store is
    // entitled to refuse one -- Redis answers "invalid expire time" -- so
    // it is not written rather than written wrong.
    final Duration lifetime = ttl + staleFor;
    if (lifetime <= Duration.zero) return;
    await store.write('$prefix$key', jsonEncode(kept.toJson()), lifetime);
  }

  void clear() {
    _kept.clear();
    _refreshing.clear();
  }
}

/// What a generated model's public page is made from: where its rows are
/// and which fields carry the title, the content, the image and whether the
/// row is published. Pure data, so the backend -- which cannot import the
/// generated model class, a Flutter widget being part of it -- can render
/// the page from a row.
class DVModelPageSpec {
  const DVModelPageSpec({
    required this.model,
    required this.route,
    required this.param,
    required this.table,
    required this.keyField,
    this.titleField,
    this.contentFields = const <String>[],
    this.imageField,
    this.publishedField,
    this.schemaType,
  });

  final String model;
  final String route;
  final String param;
  final String table;
  final String keyField;
  final String? titleField;
  final List<String> contentFields;
  final String? imageField;
  final String? publishedField;

  /// The schema.org type the page is, from `@DVModel(schemaType:)`. Null is
  /// `Thing`: honestly general beats a guess from the model's name, which a
  /// search engine would act on.
  final String? schemaType;
}

/// The page data a model row is: the title field, the longest content
/// field as description and text, the image, and structured data naming
/// the record; hidden when the published field says so.
DVPageData dvModelPageData(DVModelPageSpec spec, Map<String, Object?> row) {
  String? text(Object? value) {
    if (value == null) return null;
    final String s = '$value'.trim();
    return s.isEmpty ? null : s;
  }

  final String title = text(spec.titleField == null ? null : row[spec.titleField]) ?? text(row[spec.keyField]) ?? spec.model;
  String? content;
  for (final String field in spec.contentFields) {
    final String? candidate = text(row[field]);
    if (candidate != null && (content == null || candidate.length > content.length)) content = candidate;
  }
  final String? image = text(spec.imageField == null ? null : row[spec.imageField]);
  final Object? published = spec.publishedField == null ? true : row[spec.publishedField];
  final bool visible = published == true || published == 1 || '$published'.toLowerCase() == 'true';
  return DVPageData(
    title: title,
    description: content,
    image: image,
    text: <String>[title, if (content != null && content != title) content],
    structuredData: <String, Object?>{
      '@context': 'https://schema.org',
      '@type': spec.schemaType ?? 'Thing',
      'name': title,
      if (content != null) 'description': content,
      if (image != null) 'image': image,
    },
    visibility: visible ? DVPageVisibility.public : DVPageVisibility.hidden,
  );
}

typedef DVPageQuery = Future<List<Map<String, Object?>>> Function(String sql, List<Object?> params);

/// A resolver over [specs]: the request's pattern names the model, the
/// parameter names the row, [query] reads it. A row that is not there is a
/// hidden page; a pattern no spec owns is nobody's, null.
DVPageDataResolver dvModelPageResolver(List<DVModelPageSpec> specs, DVPageQuery query) {
  return (DVPageRequest request) async {
    for (final DVModelPageSpec spec in specs) {
      if (spec.route != request.pattern) continue;
      final String? key = request.params[spec.param];
      if (key == null) return null;
      final List<Map<String, Object?>> rows = await query('SELECT * FROM ${spec.table} WHERE ${spec.keyField} = ?', <Object?>[key]);
      if (rows.isEmpty) return DVPageData(title: spec.model, visibility: DVPageVisibility.hidden);
      return dvModelPageData(spec, rows.first);
    }
    return null;
  };
}
