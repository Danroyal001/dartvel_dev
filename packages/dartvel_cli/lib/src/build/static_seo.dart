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
import 'structured_data.dart';

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

  // What the page *is*, which OpenGraph cannot say: og:type is "website" for
  // every page on every site. This is what produces a site name in a result
  // and a breadcrumb trail under a link.
  //
  // Folded into the one head application rather than applied after it.
  // dvSeoApply writes into a marked region, so a second call replaces the
  // first call's tags -- which took the title and the canonical with it.
  final String jsonLd = dvStructuredData(
    route: route,
    title: title,
    siteName: siteName ?? title,
    description: description,
    siteUrl: siteUrl,
    image: dvAbsoluteAsset(image, siteUrl),
  );

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
    ) + (jsonLd.isEmpty ? '' : '\n$jsonLd'),
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
    // Before the root element, or it is ignored and the page renders as the
    // browser's raw XML tree with no sign of why. Crawlers skip XSLT
    // entirely, so this costs them nothing.
    ..writeln('<?xml-stylesheet type="text/xsl" href="/sitemap.xsl"?>')
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

/// The stylesheet that makes `sitemap.xml` readable.
///
/// A bare urlset renders as the browser's XML tree view: a wall of angle
/// brackets that says nothing about the site. Yoast and AIOSEO have shipped a
/// styled one for years and it costs one processing instruction — crawlers
/// ignore XSLT entirely, because it is applied by browsers.
///
/// The colours come from the application's own theme, so a Dartvel site's
/// sitemap looks like that site rather than like Dartvel. A project that wants
/// something else replaces `web/sitemap.xsl`; this is only written when that
/// file is absent.
String dvSitemapStylesheet({
  required String siteName,
  required String tagline,
  required String accent,
  required String ink,
}) {
  const HtmlEscape text = HtmlEscape(HtmlEscapeMode.element);
  final String name = text.convert(siteName);
  final String sub = text.convert(tagline);

  return '''<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:sitemap="http://www.sitemaps.org/schemas/sitemap/0.9">
  <xsl:output method="html" encoding="UTF-8" indent="yes"/>

  <xsl:template match="/">
    <html lang="en">
      <head>
        <meta charset="UTF-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title>$name — XML sitemap</title>
        <style>
          :root {
            color-scheme: light dark;
            --accent: $accent;
            --ink: $ink;
            --surface: #FFFFFF;
            --raised: #F7F8FB;
            --rule: #E4E7EE;
            --muted: #5A6478;
          }
          /* A sitemap opens in whatever the reader has. One hard-coded
             background is unreadable in the other. */
          @media (prefers-color-scheme: dark) {
            :root {
              --ink: #F3F5F9;
              --surface: #0B1020;
              --raised: #121A2E;
              --rule: #223052;
              --muted: #98A3BA;
            }
          }
          * { box-sizing: border-box; }
          body {
            margin: 0;
            background: var(--surface);
            color: var(--ink);
            font-family: ui-sans-serif, system-ui, -apple-system,
              "Segoe UI", Roboto, sans-serif;
            line-height: 1.55;
          }
          header {
            padding: 56px 24px 40px;
            border-bottom: 1px solid var(--rule);
            background:
              radial-gradient(circle at 88% -10%,
                color-mix(in srgb, var(--accent) 22%, transparent), transparent 45%),
              var(--raised);
          }
          .wrap { width: min(1040px, calc(100% - 44px)); margin: 0 auto; }
          .eyebrow {
            margin: 0 0 10px; color: var(--accent); font-size: 12px;
            font-weight: 700; letter-spacing: .16em; text-transform: uppercase;
          }
          h1 { margin: 0; font-size: clamp(28px, 4vw, 42px); line-height: 1.1; }
          header p { margin: 14px 0 0; color: var(--muted); max-width: 62ch; }
          main { padding: 32px 0 72px; }
          .count {
            display: flex; align-items: baseline; gap: 10px;
            margin: 0 0 18px; color: var(--muted); font-size: 14px;
          }
          .count strong { color: var(--ink); font-size: 22px; }
          table { width: 100%; border-collapse: collapse; font-size: 15px; }
          th {
            text-align: left; padding: 12px 14px; color: var(--muted);
            font-size: 11px; font-weight: 700; letter-spacing: .12em;
            text-transform: uppercase; border-bottom: 1px solid var(--rule);
          }
          td { padding: 13px 14px; border-bottom: 1px solid var(--rule); }
          tr:hover td { background: var(--raised); }
          a { color: var(--accent); text-decoration: none; font-weight: 600; }
          a:hover { text-decoration: underline; }
          .note {
            margin: 26px 0 0; color: var(--muted); font-size: 13px;
            max-width: 70ch;
          }
        </style>
      </head>
      <body>
        <header>
          <div class="wrap">
            <p class="eyebrow">XML sitemap</p>
            <h1>$name</h1>
            <p>$sub</p>
          </div>
        </header>
        <main class="wrap">
          <p class="count">
            <strong><xsl:value-of select="count(sitemap:urlset/sitemap:url)"/></strong>
            <span>pages in this sitemap</span>
          </p>
          <table>
            <tr>
              <th>URL</th>
              <th>Last modified</th>
            </tr>
            <xsl:for-each select="sitemap:urlset/sitemap:url">
              <tr>
                <td><a href="{sitemap:loc}"><xsl:value-of select="sitemap:loc"/></a></td>
                <td><xsl:value-of select="sitemap:lastmod"/></td>
              </tr>
            </xsl:for-each>
          </table>
          <p class="note">
            This page is a stylesheet applied by your browser. A crawler reads
            the XML underneath and never sees any of it.
          </p>
        </main>
      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>
''';
}
