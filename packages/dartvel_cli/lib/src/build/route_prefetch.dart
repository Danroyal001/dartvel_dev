/// Each prerendered page names its own JavaScript and images in its head, and
/// the build writes down per route what a link to it can fetch early.
///
/// Every page is a deferred import, so its code is in parts that
/// `loadLibrary()` fetches once main.dart.js has booted. On a page opened
/// directly that is a round trip after the HTML arrived saying nothing about
/// them. A `<link rel="preload">` in the head starts those downloads alongside
/// main.dart.js instead of after it; the same goes for the images the page
/// paints on its first frame.
///
/// dart2js writes which parts belong to which import into main.dart.js, and
/// that table is the only authority used here. A preload for the wrong file
/// is not harmless: it is a second download on every page load.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'semantics_capture.dart' show dvSemanticsPathFor;
import 'static_seo.dart' show dvStaticRoutePath;

/// What a link can fetch for each route, next to index.html. Read by
/// `DVRoutePrefetch` in dartvel_flutter; the shape is
/// `{"routes": {"/docs": {"scripts": [...], "images": [{"url", "as"}]}}}`.
const String dvPrefetchManifestFile = 'dartvel_prefetch.json';

const String _open = '<!-- dartvel:preload -->';
const String _close = '<!-- /dartvel:preload -->';

/// An image a page asked for while it rendered, and how it asked.
///
/// [as] is `fetch` for bytes Flutter read with fetch(), `image` for an
/// `<img>`. A preload is only reused when it was requested the same way as
/// the request it is meant to answer, so this is not cosmetic.
class DVCapturedImage {
  const DVCapturedImage({required this.url, required this.as});

  /// Null for anything that is not a well-formed entry.
  static DVCapturedImage? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? url = json['url'];
    final Object? as = json['as'];
    if (url is! String || url.isEmpty) return null;
    return DVCapturedImage(url: url, as: as == 'image' ? 'image' : 'fetch');
  }

  /// Relative to the site when it is the site's own, absolute otherwise.
  final String url;
  final String as;

  Map<String, Object?> toJson() => <String, Object?>{'url': url, 'as': as};
}

/// What [dvWriteRoutePrefetch] wrote.
class DVPrefetchSummary {
  const DVPrefetchSummary({required this.pages, required this.images});

  /// Pages whose head now names something.
  final int pages;

  /// Images named across them.
  final int images;
}

/// Each deferred import's part files, from the table dart2js wrote into
/// main.dart.js.
///
/// An import with an empty list has no code of its own: all of it is in
/// main.dart.js already. A build with no deferred code has no table at all,
/// and gets an empty map.
Map<String, List<String>> dvDeferredParts(String mainJs) {
  final RegExpMatch? table =
      RegExp(r'deferredLibraryParts:\{([^}]*)\}').firstMatch(mainJs);
  final RegExpMatch? uris =
      RegExp(r'deferredPartUris:\[([^\]]*)\]').firstMatch(mainJs);
  if (table == null || uris == null) return const <String, List<String>>{};

  final List<String> files = <String>[
    for (final RegExpMatch m in RegExp(r'"([^"]*)"').allMatches(uris.group(1)!))
      m.group(1)!,
  ];
  return <String, List<String>>{
    for (final RegExpMatch m
        in RegExp(r'(?:"([^"]+)"|([A-Za-z_$][\w$]*)):\[([\d,\s]*)\]')
            .allMatches(table.group(1)!))
      m.group(1) ?? m.group(2)!: <String>[
        for (final String index in m.group(3)!.split(','))
          if (int.tryParse(index.trim()) case final int i
              when i >= 0 && i < files.length)
            files[i],
      ],
  };
}

/// Which deferred import each route's page loads, read from the generated
/// router.
///
/// Only routes registered with a generated page's `loadLibrary`. A route
/// registered with a loader of the application's own says nothing about
/// which import it loads, and gets no preload rather than a guessed one.
Map<String, String> dvDeferredPrefixes(String routerSource) {
  final List<RegExpMatch> classes = RegExp(r'^class (\w+) extends ',
          multiLine: true)
      .allMatches(routerSource)
      .toList();
  final Map<String, String> prefixOf = <String, String>{};
  for (int i = 0; i < classes.length; i++) {
    final int end =
        i + 1 < classes.length ? classes[i + 1].start : routerSource.length;
    final RegExpMatch? load = RegExp(r'_libraryFuture \?\?= (\w+)\.loadLibrary\(\)')
        .firstMatch(routerSource.substring(classes[i].end, end));
    if (load != null) prefixOf[classes[i].group(1)!] = load.group(1)!;
  }

  return <String, String>{
    for (final RegExpMatch m in RegExp(
            r"DVRoutePreloaders\.register\(\s*'([^']*)',\s*(\w+)\.loadLibrary\b")
        .allMatches(routerSource))
      if (prefixOf[m.group(2)] case final String prefix) m.group(1)!: prefix,
  };
}

/// The request types a page makes itself. `other` is what Chrome calls the
/// favicon and the manifest icons it fetches on its own account; those are
/// on every page and belong to none of them.
const Set<String> _pageRequestTypes = <String>{'fetch', 'xhr', 'image'};

/// The image in a response the capture saw, or null when it is not one the
/// page asked for.
DVCapturedImage? dvPageImage({
  required String url,
  required String base,
  required String? contentType,
  required String resourceType,
}) {
  if (url.startsWith('data:') || url.startsWith('blob:')) return null;
  final String type = resourceType.toLowerCase();
  if (!_pageRequestTypes.contains(type)) return null;
  if (contentType == null ||
      !contentType.trim().toLowerCase().startsWith('image/')) {
    return null;
  }
  final String site = base.endsWith('/') ? base : '$base/';
  return DVCapturedImage(
    url: url.startsWith(site) ? url.substring(site.length) : url,
    as: type == 'image' ? 'image' : 'fetch',
  );
}

/// Where the capture keeps a route's images: beside its semantics tree, so
/// the two are written, and deleted, together.
String dvCapturedImagesPathFor(String projectRoot, String route) {
  final String tree = dvSemanticsPathFor(projectRoot, route);
  return tree.endsWith('.json')
      ? '${tree.substring(0, tree.length - '.json'.length)}.images.json'
      : '$tree.images.json';
}

/// The images the capture recorded for [route]; none when it recorded
/// nothing or the file is unreadable.
List<DVCapturedImage> dvReadCapturedImages(String projectRoot, String route) {
  final File file = File(dvCapturedImagesPathFor(projectRoot, route));
  if (!file.existsSync()) return const <DVCapturedImage>[];
  try {
    final Object? json = jsonDecode(file.readAsStringSync());
    if (json is! List) return const <DVCapturedImage>[];
    return <DVCapturedImage>[
      for (final Object? entry in json)
        if (DVCapturedImage.fromJson(entry) case final DVCapturedImage image)
          image,
    ];
  } on FormatException {
    return const <DVCapturedImage>[];
  }
}

/// [html] with its preload list replaced by one naming [scripts] and
/// [images].
///
/// Between markers, so a second build replaces the first one's list rather
/// than adding to it. With nothing to name the list is removed and the page
/// is left exactly as it was.
String dvApplyPreloadHead(
  String html, {
  required List<String> scripts,
  required List<DVCapturedImage> images,
}) {
  final String cleared = html.replaceAll(
    RegExp('${RegExp.escape(_open)}[\\s\\S]*?${RegExp.escape(_close)}\\n?'),
    '',
  );
  if (scripts.isEmpty && images.isEmpty) return cleared;
  final int at = cleared.indexOf('</head>');
  if (at < 0) return cleared;

  final String block = <String>[
    _open,
    for (final String script in scripts)
      '<link rel="preload" href="${_attribute(script)}" as="script">',
    for (final DVCapturedImage image in images)
      image.as == 'image'
          ? '<link rel="preload" href="${_attribute(image.url)}" as="image">'
          // crossorigin because fetch() is a CORS request even to its own
          // site. Without it the preload is a no-cors request, and the
          // browser does not hand one to the other.
          : '<link rel="preload" href="${_attribute(image.url)}" '
              'as="fetch" crossorigin="anonymous">',
    _close,
  ].join('\n');
  return '${cleared.substring(0, at)}$block\n${cleared.substring(at)}';
}

String _attribute(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Names each route's parts and images in the head of its page, and writes
/// the manifest a link reads.
///
/// A route with no page on disk is left alone rather than created: that is a
/// route the static build did not write, for whatever reason, and a page
/// holding nothing but preloads would be worse than none.
///
/// The root's list goes in index.html, which is also what a host answers for
/// a path that has no page of its own. Such a visitor downloads the home
/// page's parts for nothing; they are the parts most likely to be needed
/// next, and the alternative is the home page itself -- the most visited page
/// on most sites -- going without.
DVPrefetchSummary dvWriteRoutePrefetch({
  required String projectRoot,
  required String webRoot,
  required String routerSource,
  required List<String> routes,
}) {
  final File mainJs = File(p.join(webRoot, 'main.dart.js'));
  final Map<String, List<String>> parts = mainJs.existsSync()
      ? dvDeferredParts(mainJs.readAsStringSync())
      : const <String, List<String>>{};
  final Map<String, String> prefixes = dvDeferredPrefixes(routerSource);

  final Map<String, Object?> manifest = <String, Object?>{};
  var pages = 0;
  var imageCount = 0;
  for (final String route in routes) {
    final List<String> scripts = parts[prefixes[route]] ?? const <String>[];
    final List<DVCapturedImage> images =
        dvReadCapturedImages(projectRoot, route);
    manifest[route] = <String, Object?>{
      'scripts': scripts,
      'images': <Object?>[
        for (final DVCapturedImage image in images) image.toJson(),
      ],
    };

    final String? target = dvStaticRoutePath(route);
    if (target == null) continue;
    final File page = File(p.join(webRoot, target));
    if (!page.existsSync()) continue;
    final String before = page.readAsStringSync();
    final String after =
        dvApplyPreloadHead(before, scripts: scripts, images: images);
    if (after != before) page.writeAsStringSync(after);
    if (scripts.isNotEmpty || images.isNotEmpty) {
      pages++;
      imageCount += images.length;
    }
  }

  File(p.join(webRoot, dvPrefetchManifestFile)).writeAsStringSync(
    const JsonEncoder.withIndent('  ')
        .convert(<String, Object?>{'routes': manifest}),
  );
  return DVPrefetchSummary(pages: pages, images: imageCount);
}
