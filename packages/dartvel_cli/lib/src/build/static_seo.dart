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
  Map<String, String> alternates = const <String, String>{},
  String? defaultAlternate,
  String? favicon,
  String? schemaType,
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
    schemaType: schemaType,
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
      alternates: alternates,
      defaultAlternate: defaultAlternate,
    ) + (jsonLd.isEmpty ? '' : '\n$jsonLd'),
  );

  // Outside the marked region deliberately. dvSeoApply rewrites what is
  // between its markers, and the shell's icon link is not in there -- it is a
  // tag Flutter wrote, and replacing it is the only way a page gets its own
  // icon rather than a second one next to the application's.
  html = dvApplyFavicon(html, favicon);

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

/// The routes a generated router guards, read back out of its source.
///
/// The generator knows: it computed the redirect chain to emit it. Nothing
/// downstream could tell, because the only way to ask was to scrape `path:`
/// literals, and a regular expression cannot see the guard block below the
/// path it matched. So the generator now writes the answer down and this
/// reads it.
///
/// A router without the list is one generated before this existed; that is
/// an empty answer rather than an error, because failing a build over a
/// stale generated file would strand anybody mid-upgrade.
Set<String> dvGuardedRoutes(String routerSource) {
  final RegExpMatch? list = RegExp(
    r'dartvelGuardedRoutes\s*=\s*<String>\[([^\]]*)\]',
    dotAll: true,
  ).firstMatch(routerSource);
  if (list == null) return const <String>{};
  return RegExp(r"'([^']*)'")
      .allMatches(list.group(1)!)
      .map((RegExpMatch m) => m.group(1)!)
      .where((String route) => route.isNotEmpty)
      .toSet();
}

/// What a page or a project says about how a URL should be crawled.
///
/// [changeFrequency] is the sitemaps.org token rather than the enum, because
/// this side of the build reads it back out of a generated file as text. The
/// enum lives in `dartvel_core`, where a page writes it.
class DVSitemapEntry {
  const DVSitemapEntry({this.priority, this.changeFrequency});

  /// Between 0 and 1, relative to the rest of this site and nothing else. It
  /// does not raise a page in anybody's results; it says which of your own
  /// pages to crawl first when a crawler cannot take them all.
  final double? priority;

  final String? changeFrequency;

  /// This entry over [other], field by field.
  ///
  /// Field by field rather than whole: a page that only says it changes
  /// daily should keep the project's priority rather than losing it to the
  /// null it did not write.
  DVSitemapEntry over(DVSitemapEntry? other) => DVSitemapEntry(
        priority: priority ?? other?.priority,
        changeFrequency: changeFrequency ?? other?.changeFrequency,
      );

  bool get isEmpty => priority == null && changeFrequency == null;
}

/// The seven words sitemaps.org defines for `<changefreq>`.
///
/// A crawler drops the whole `<url>` element when one of its children will
/// not validate, so an eighth word here removes the page rather than the
/// hint it was meant to carry.
const Set<String> dvSitemapChangeFrequencies = <String>{
  'always',
  'hourly',
  'daily',
  'weekly',
  'monthly',
  'yearly',
  'never',
};

/// The per-route sitemap entries a generated router declares.
///
/// The generator knows what each page's annotation said and writes it down,
/// for the same reason it writes down which routes it guards: the build
/// cannot read a Dart annotation, and scraping one out of the router with a
/// regular expression is what published every private route.
Map<String, DVSitemapEntry> dvSitemapEntries(String routerSource) {
  final RegExpMatch? map = RegExp(
    r'dartvelSitemapEntries\s*=\s*<String,\s*DVPageSitemap>\{(.*?)\n\};',
    dotAll: true,
  ).firstMatch(routerSource);
  if (map == null) return const <String, DVSitemapEntry>{};

  final Map<String, DVSitemapEntry> entries = <String, DVSitemapEntry>{};
  // `const` optional, because the emitter writes it and a page may have
  // written it too. This pattern required the constructor immediately after
  // the colon, so it matched nothing at all against a real generated router
  // and every entry came back empty -- the reader and the writer were
  // written against each other rather than against a file.
  final RegExp entry = RegExp(
    r"'([^']*)'\s*:\s*(?:const\s+)?DVPageSitemap\(([^)]*)\)",
    dotAll: true,
  );
  for (final RegExpMatch match in entry.allMatches(map.group(1)!)) {
    final String args = match.group(2)!;
    final RegExpMatch? priority =
        RegExp(r'priority:\s*([0-9.]+)').firstMatch(args);
    final RegExpMatch? frequency = RegExp(
      r'changeFrequency:\s*DVSitemapChangeFrequency\.([A-Za-z]+)',
    ).firstMatch(args);
    entries[match.group(1)!] = DVSitemapEntry(
      priority: priority == null ? null : double.tryParse(priority.group(1)!),
      changeFrequency: frequency?.group(1),
    );
  }
  return entries;
}

/// Whether [route] is covered by one of the project's [patterns].
///
/// `**` matches any number of segments, `*` matches one, and a pattern is
/// anchored at both ends -- so `/admin/**` does not take `/superadmin` with
/// it.
///
/// `/admin/**` also excludes `/admin` itself. Publishing the front door of a
/// section whose every child is hidden discloses the same thing the pattern
/// was written to hide, and a reader who writes `/admin/**` means the admin
/// area rather than the admin area minus its index.
bool dvSitemapExcluded(String route, List<String> patterns) {
  for (final String pattern in patterns) {
    if (_matchesGlob(route, pattern)) return true;
    if (pattern.endsWith('/**') &&
        route == pattern.substring(0, pattern.length - 3)) {
      return true;
    }
  }
  return false;
}

bool _matchesGlob(String route, String pattern) {
  final StringBuffer expr = StringBuffer('^');
  int i = 0;
  while (i < pattern.length) {
    if (pattern.startsWith('**', i)) {
      expr.write('.*');
      i += 2;
      continue;
    }
    if (pattern[i] == '*') {
      // One segment, so a single star cannot cross a slash.
      expr.write('[^/]*');
      i++;
      continue;
    }
    expr.write(RegExp.escape(pattern[i]));
    i++;
  }
  expr.write(r'$');
  return RegExp(expr.toString()).hasMatch(route);
}

/// What `dartvel.seo.sitemap` says.
class DVSitemapConfig {
  const DVSitemapConfig({
    this.enabled = true,
    this.exclude = const <String>[],
    this.defaults,
  });

  /// On unless the project turns it off. A site that never configured SEO is
  /// the one that most needs the file written for it.
  final bool enabled;
  final List<String> exclude;
  final DVSitemapEntry? defaults;
}

/// Read `dartvel.seo.sitemap` out of the `dartvel:` section of a pubspec.
///
/// [dv] is that section, which is what the build already holds.
DVSitemapConfig dvSitemapConfig(Object? dv) {
  final Object? seo = _mapValue(dv, 'seo');
  final Object? sitemap = _mapValue(seo, 'sitemap');
  if (sitemap == null) return const DVSitemapConfig();

  final Object? enabled = _mapValue(sitemap, 'enabled');
  final Object? exclude = _mapValue(sitemap, 'exclude');
  final Object? defaults = _mapValue(sitemap, 'defaults');

  return DVSitemapConfig(
    enabled: enabled is bool ? enabled : true,
    exclude: exclude is Iterable
        ? exclude
            .map((Object? e) => e?.toString() ?? '')
            .where((String e) => e.isNotEmpty)
            .toList(growable: false)
        : const <String>[],
    defaults: defaults == null ? null : _entryFromYaml(defaults),
  );
}

DVSitemapEntry? _entryFromYaml(Object? node) {
  final Object? priority = _mapValue(node, 'priority');
  // Both spellings. The XML element is <changefreq>, and a developer who
  // copied the name out of the file they are configuring should not get
  // silence for it.
  final Object? frequency = _mapValue(node, 'changeFrequency') ??
      _mapValue(node, 'changefreq') ??
      _mapValue(node, 'change_frequency');
  final DVSitemapEntry entry = DVSitemapEntry(
    priority: priority is num
        ? priority.toDouble()
        : double.tryParse(priority?.toString() ?? ''),
    changeFrequency: frequency?.toString(),
  );
  return entry.isEmpty ? null : entry;
}

Object? _mapValue(Object? node, String key) {
  if (node is Map) return node[key];
  return null;
}

/// The `<priority>` text for [value], refusing what sitemaps.org will not
/// accept.
///
/// Refused rather than clamped, and named with the route it came from: a 5
/// that silently became a 1 reads as working, and the page somebody wrote it
/// on is the page they cared most about.
String dvSitemapPriority(double value, String where) {
  if (value.isNaN || value < 0 || value > 1) {
    throw ArgumentError.value(
      value,
      'priority',
      'sitemap priority for $where must be between 0 and 1',
    );
  }
  final String text = value.toStringAsFixed(1);
  // 0.85 is a priority somebody meant; keep it rather than rounding it to
  // the nearest tenth behind their back.
  return double.parse(text) == value ? text : value.toString();
}

/// The `<changefreq>` text for [value], refusing an eighth word.
String dvSitemapChangeFrequency(String value, String where) {
  if (!dvSitemapChangeFrequencies.contains(value)) {
    throw ArgumentError.value(
      value,
      'changeFrequency',
      'sitemap changefreq for $where must be one of '
          '${dvSitemapChangeFrequencies.join(', ')}',
    );
  }
  return value;
}

/// A sitemap listing every route that is a page and is not guarded.
///
/// [guarded] is left out entirely rather than listed with a lower priority.
/// The specification's wording is that private routes are excluded, and a
/// sitemap is read by people who were not invited: the guard still refuses
/// them at the door, but the address of an internal tool is worth having on
/// its own.
///
/// [entries] is what each page's own `@DVPage(sitemap: ...)` said, and
/// [defaults] what the project said for the rest. A route neither of them
/// mentions is written as a bare `<loc>`: a priority nobody asked for says
/// the same thing as no priority at all, in more bytes, and a crawler
/// reading it cannot tell it was invented.
String dvSitemap({
  required List<String> routes,
  required String siteUrl,
  List<String> federated = const <String>[],
  Set<String> guarded = const <String>{},
  Map<String, DVSitemapEntry> entries = const <String, DVSitemapEntry>{},
  DVSitemapEntry? defaults,
  List<String> exclude = const <String>[],
}) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    // Before the root element, or it is ignored and the page renders as the
    // browser's raw XML tree with no sign of why. Crawlers skip XSLT
    // entirely, so this costs them nothing.
    ..writeln('<?xml-stylesheet type="text/xsl" href="/sitemap.xsl"?>')
    ..writeln('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');

  // A federated module's routes are listed under the parent, because that is
  // the URL a reader has and the one the parent answers -- it redirects, and
  // the module serves its own HTML from there. A cross-domain entry would be
  // ignored by crawlers, which would make mounting a micro-site under a
  // parent's domain pointless.
  for (final String route in <String>[...routes, ...federated]) {
    // Applied to the federated list too. A module mounted under the parent's
    // domain is advertised on the parent's path, so skipping the check there
    // would make mounting a module the way around this.
    if (guarded.contains(route)) continue;
    if (dvSitemapExcluded(route, exclude)) continue;
    // Same filter as the writer: a route with no file behind it has no URL to
    // advertise, and a crawler following one gets a 404 from the sitemap that
    // was meant to help it.
    if (dvStaticRoutePath(route) == null) continue;
    final url = const HtmlEscape(HtmlEscapeMode.element)
        .convert(dvStaticCanonical(siteUrl, route));
    final DVSitemapEntry entry =
        (entries[route] ?? const DVSitemapEntry()).over(defaults);
    buffer
      ..writeln('  <url>')
      ..writeln('    <loc>$url</loc>');
    final double? priority = entry.priority;
    if (priority != null) {
      buffer.writeln(
        '    <priority>${dvSitemapPriority(priority, route)}</priority>',
      );
    }
    final String? frequency = entry.changeFrequency;
    if (frequency != null) {
      buffer.writeln(
        '    <changefreq>'
        '${dvSitemapChangeFrequency(frequency, route)}</changefreq>',
      );
    }
    buffer.writeln('  </url>');
  }

  buffer.writeln('</urlset>');
  return buffer.toString();
}

/// A robots.txt that allows crawling and names the sitemap.
///
/// [sitemap] is false when `dartvel.seo.sitemap.enabled` turned the file
/// off. Naming a sitemap the build did not write points a crawler at a 404,
/// which is worse than saying nothing about it.
String dvRobots({required String siteUrl, bool sitemap = true}) {
  final base = siteUrl.replaceAll(RegExp(r'/+$'), '');
  const String head = 'User-agent: *\n'
      'Allow: /\n';
  if (!sitemap) return head;
  return '$head'
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
