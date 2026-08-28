/// Per-route HTML, a sitemap and robots.txt for a static build.
///
/// `dartvel build web` produced one `index.html` for every route. On a static
/// host that is what a crawler gets: four URLs, one title, one description,
/// one body — which is `flutter build web` with extra steps.
///
/// `dartvel prerender` already captures a title and semantic content per
/// route, but it writes `prerender/<route>/meta.json` for a *server* to inject,
/// and a static host has no server to do it. This writes the pages out.
library;

import 'dart:convert';

import 'seo_head.dart';

/// Where a route's HTML file goes, relative to the build output.
///
/// Returns null for a route that is not a page: one with a parameter names a
/// shape rather than a document, and writing it produces a file literally
/// called `:id`.
String? dvStaticRoutePath(String route) {
  if (!route.startsWith('/')) return null;
  // A traversal or an empty segment would write outside the output directory.
  if (route.contains('..') || route.contains('//')) return null;
  if (route.contains(':') || route.contains('*')) return null;

  final trimmed = route.replaceAll(RegExp(r'/+$'), '');
  if (trimmed.isEmpty) return 'index.html';
  return '${trimmed.substring(1)}/index.html';
}

/// The absolute URL for a route.
String dvStaticCanonical(String siteUrl, String route) {
  final base = siteUrl.replaceAll(RegExp(r'/+$'), '');
  final trimmed = route.replaceAll(RegExp(r'/+$'), '');
  return trimmed.isEmpty ? base : '$base$trimmed';
}

/// A route's own HTML: the app shell with this page's head tags and, where
/// prerendering captured it, this page's text.
String dvStaticPage({
  required String shell,
  required String route,
  required String title,
  String? description,
  String? content,
  String? siteUrl,
  String? image,
  String? siteName,
}) {
  final canonical =
      siteUrl == null ? null : dvStaticCanonical(siteUrl, route);

  var html = dvSeoApply(
    shell,
    dvSeoHead(
      title: title,
      description: description,
      // Its own URL, not the site root. Every page canonicalising to `/` tells
      // a crawler they are the same page, which is worse than no canonical.
      siteUrl: canonical,
      // Resolved against the site root here, because dvSeoHead resolves a
      // relative image against whatever it is given as siteUrl -- and that is
      // the page's canonical URL, which is what the canonical link and og:url
      // need. Passing both through one argument put the route into the image:
      // /docs asked for https://example.com/docs/icons/Icon-512.png, which
      // does not exist. A broken og:image is invisible until someone shares
      // the link.
      image: dvAbsoluteAsset(image, siteUrl),
      siteName: siteName,
    ),
  );

  if (content != null && content.trim().isNotEmpty) {
    html = _injectContent(html, content);
  }
  return html;
}

/// Markers so a rebuild replaces the block rather than adding another.
const String _openBody = '<!-- dartvel:prerendered -->';
const String _closeBody = '<!-- /dartvel:prerendered -->';

/// Put the prerendered text in the body.
///
/// The body is empty until JavaScript runs, so without this a crawler sees
/// nothing. The text comes from the rendered page, which renders whatever is
/// in the database, so it is escaped like any other untrusted value.
String _injectContent(String html, String content) {
  final cleaned = html.replaceAll(
      RegExp('$_openBody.*?$_closeBody\n?', dotAll: true), '');
  final at = cleaned.indexOf('</body>');
  if (at < 0) return cleaned;

  // Off-screen rather than hidden: `display: none` is ignored by some
  // crawlers and treated as cloaking by others, while a positioned element is
  // read normally and never seen.
  final block = '$_openBody\n'
      '<div id="dartvel-prerendered" style="position:absolute;left:-9999px;'
      'top:auto;width:1px;height:1px;overflow:hidden;">'
      '${const HtmlEscape(HtmlEscapeMode.element).convert(content)}'
      '</div>\n$_closeBody\n';
  return '${cleaned.substring(0, at)}$block${cleaned.substring(at)}';
}

/// A sitemap listing every route that is a page.
String dvSitemap({required List<String> routes, required String siteUrl}) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');

  for (final String route in routes) {
    // Same filter as the writer: a route with no file behind it has no URL to
    // advertise, and a crawler following one gets a 404 from the sitemap that
    // was meant to help it.
    if (dvStaticRoutePath(route) == null) continue;
    final url = const HtmlEscape(HtmlEscapeMode.element)
        .convert(dvStaticCanonical(siteUrl, route));
    buffer
      ..writeln('  <url>')
      ..writeln('    <loc>$url</loc>')
      ..writeln('  </url>');
  }

  buffer.writeln('</urlset>');
  return buffer.toString();
}

/// A robots.txt that allows crawling and names the sitemap.
String dvRobots({required String siteUrl}) {
  final base = siteUrl.replaceAll(RegExp(r'/+$'), '');
  return 'User-agent: *\n'
      'Allow: /\n'
      '\n'
      'Sitemap: $base/sitemap.xml\n';
}

/// What `dartvel prerender` captured for one route.
class DVPrerenderedMeta {
  const DVPrerenderedMeta({this.title, this.content});
  final String? title;
  final String? content;
}

/// Read a prerender `meta.json`, or null if it cannot be read.
///
/// A prerender that half-ran should not stop a release: the page falls back to
/// its configured title rather than failing the build.
DVPrerenderedMeta? dvPrerenderedMeta(String source) {
  try {
    final decoded = jsonDecode(source);
    if (decoded is! Map) return null;
    return DVPrerenderedMeta(
      title: decoded['title'] as String?,
      content: decoded['content'] as String?,
    );
  } on FormatException {
    return null;
  }
}

/// The title each route's page declares, read from the generated router.
///
/// The page already says what it is called -- `@DVPage(title: ...)` reaches
/// the router as a `DVPageScaffoldSpec`. Deriving a title from the path
/// instead throws that away and produces things like
/// "Docs — Dartvel — Flutter, full stack": a capitalised path segment glued to
/// a site title that already contained the site name.
Map<String, String> dvRouteTitles(String routerSource) {
  // class <Name> ... title: '<title>'
  final byClass = <String, String>{};
  final classPattern = RegExp(
    r"class\s+(\w+)\s+extends[\s\S]*?DVPageScaffoldSpec\(title:\s*'([^']*)'",
  );
  for (final RegExpMatch match in classPattern.allMatches(routerSource)) {
    byClass[match.group(1)!] = match.group(2)!;
  }

  // path: '<route>' ... const <Name>()
  final titles = <String, String>{};
  final routePattern = RegExp(
    r"path:\s*'([^']+)'[\s\S]{0,600}?const\s+(\w+)\(\)",
  );
  for (final RegExpMatch match in routePattern.allMatches(routerSource)) {
    final title = byClass[match.group(2)!];
    if (title != null && title.isNotEmpty) titles[match.group(1)!] = title;
  }
  return titles;
}
