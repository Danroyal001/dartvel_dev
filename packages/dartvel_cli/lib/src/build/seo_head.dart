/// The head tags a built web application ships with.
///
/// `dartvel build web` produced an `index.html` whose title was the package
/// name and which carried no Open Graph tags at all, above a body that stays
/// empty until JavaScript runs. A crawler, a link preview in a chat client and
/// a share on social all read exactly that, and none of them execute the app.
///
/// The failure is quiet in the worst way: the page is perfect in a browser.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Head tags for a page.
///
/// Open Graph and Twitter carry the same three facts under different names
/// because the consumers read different tags; a page that sets only one
/// previews as a blank card in whichever client reads the other.
String dvSeoHead({
  required String title,
  String? description,
  String? siteUrl,
  String? image,
  String? siteName,
  Map<String, String> alternates = const <String, String>{},
  String? defaultAlternate,
  String type = 'website',
}) {
  final tags = <String>[
    '<title>${_escapeText(title)}</title>',
    _meta('name', 'description', description),
    if (siteUrl != null && siteUrl.isNotEmpty)
      '<link rel="canonical" href="${_escapeAttribute(siteUrl)}">',
    // hreflang, one link per language this page exists in. Without them a
    // site with /fr/pricing and /de/pricing shows a crawler three unrelated
    // pages with the same content, which engines treat as duplicates rather
    // than translations. Written only when there is more than one: a lone
    // hreflang reads as a misconfiguration.
    if (alternates.length > 1)
      for (final MapEntry<String, String> alternate in alternates.entries)
        '<link rel="alternate" hreflang="${_escapeAttribute(alternate.key)}" '
            'href="${_escapeAttribute(alternate.value)}">',
    if (alternates.length > 1 && defaultAlternate != null)
      '<link rel="alternate" hreflang="x-default" '
          'href="${_escapeAttribute(defaultAlternate)}">',
    _meta('property', 'og:title', title),
    _meta('property', 'og:description', description),
    _meta('property', 'og:type', type),
    _meta('property', 'og:url', siteUrl),
    _meta('property', 'og:site_name', siteName),
    _meta('property', 'og:image', _absolute(image, siteUrl)),
    _meta('name', 'twitter:card',
        image == null ? 'summary' : 'summary_large_image'),
    _meta('name', 'twitter:title', title),
    _meta('name', 'twitter:description', description),
    _meta('name', 'twitter:image', _absolute(image, siteUrl)),
  ];

  return tags.where((String tag) => tag.isNotEmpty).join('\n');
}

/// The viewport meta a responsive web page cannot do without.
///
/// `width=device-width` is the whole point: without it a phone browser lays
/// the page out at a notional ~980 CSS pixels and scales the result down, so
/// the app is not narrow, it is a shrunken desktop. Everything downstream of a
/// width -- Dartvel's own breakpoints included -- then reports "desktop" on a
/// phone, which makes responsive layout not merely absent but actively wrong.
///
/// `viewport-fit=cover` pairs with `DV.Platform.screen.safeAreaBounds`:
/// without it the safe-area insets a notched phone reports are all zero, so
/// honouring them does nothing on the one class of device that has them.
///
/// Deliberately no `user-scalable=no` and no `maximum-scale`. Some Flutter
/// templates ship them and they stop a low-vision reader pinching to zoom; a
/// framework should not decide that on an application's behalf.
const String dvViewportMeta =
    '<meta name="viewport" content="width=device-width, initial-scale=1, '
    'viewport-fit=cover">';

/// Ensure [html] carries a viewport meta.
///
/// A page that already declares one is left alone: a developer who wrote their
/// own meant it, and two viewport metas is not additive -- which one the
/// browser honours is not something to guess at.
String dvViewportApply(String html) {
  if (RegExp(r"""<meta\s+name=["']viewport["']""", caseSensitive: false)
      .hasMatch(html)) {
    return html;
  }
  final int at = html.indexOf('</head>');
  // No head to put it in. Returning the page unchanged beats inventing
  // structure around someone's template.
  if (at < 0) return html;
  return '${html.substring(0, at)}  $dvViewportMeta\n${html.substring(at)}';
}

/// Put a viewport into the project's own `web/index.html`.
///
/// Fixing only the built output leaves `dartvel run web` serving the source
/// template, which is the mode a developer is actually looking at when they
/// check a layout on a phone -- so the one place it matters most during
/// development would still be laying out at 980px.
///
/// Returns whether the file was changed, so a build can say it did something
/// to a file the developer owns rather than editing it silently. A project
/// with no `web/` at all is not an error: mobile-only and server-only projects
/// are ordinary.
bool dvEnsureProjectViewport(String root) {
  final File index = File(p.join(root, 'web', 'index.html'));
  if (!index.existsSync()) return false;

  final String before = index.readAsStringSync();
  final String after = dvViewportApply(before);
  if (after == before) return false;

  index.writeAsStringSync(after);
  return true;
}

/// Where the injected block starts and ends.
///
/// Marked so a rebuild replaces it rather than adding a second copy. A build
/// often runs over the previous build's output, and tags that accumulate are
/// worse than tags that are wrong: which one a crawler reads is undefined.
const String _open = '<!-- dartvel:seo -->';
const String _close = '<!-- /dartvel:seo -->';

/// Put [head] into [html], replacing anything already there.
///
/// The scaffolded `<title>` and `<meta name="description">` are removed rather
/// than left beside the generated ones, because two of either is not additive.
String dvSeoApply(String html, String head) {
  final headEnd = html.indexOf('</head>');
  // No head to put it in. Returning the page unchanged beats inventing
  // structure around someone's template.
  if (headEnd < 0) return html;

  // The trailing newline goes with the block. Leaving it behind means each
  // rebuild adds one, which is invisible in a diff of one build and obvious
  // after twenty.
  var out = html.replaceAll(
      RegExp('$_open.*?$_close\n?', dotAll: true, multiLine: true), '');
  out = out.replaceAll(RegExp(r'<title>.*?</title>', dotAll: true), '');
  out = out.replaceAll(
      RegExp(r'''<meta\s+name=["']description["'][^>]*>''', caseSensitive: false),
      '');

  // Before the block rather than after it, and that ordering is load-bearing
  // for idempotence: inserting the viewport last would put it after the SEO
  // block on a first pass and before it on a second, so two applies would not
  // produce the same page. A build often runs over the previous build's
  // output.
  //
  // Every path that writes a built page -- the web build, the web server, the
  // static per-route pages -- goes through here, so this is the one place a
  // viewport cannot be forgotten. Left as a separate call at each of those
  // three sites it is one new code path away from being missing again, and
  // when it is missing the failure is silent: the page is perfect in a
  // desktop browser.
  out = dvViewportApply(out);

  final at = out.indexOf('</head>');
  if (at < 0) return html;
  return '${out.substring(0, at)}$_open\n$head\n$_close\n${out.substring(at)}';
}

/// An Open Graph image has to be absolute: consumers fetch it with no base, so
/// a relative path resolves against their own host and 404s.
String? dvAbsoluteAsset(String? image, String? siteUrl) =>
    _absolute(image, siteUrl);

String? _absolute(String? image, String? siteUrl) {
  if (image == null || image.isEmpty) return null;
  if (image.startsWith('http://') || image.startsWith('https://')) return image;
  if (siteUrl == null || siteUrl.isEmpty) return image;
  final base = siteUrl.endsWith('/')
      ? siteUrl.substring(0, siteUrl.length - 1)
      : siteUrl;
  final path = image.startsWith('/') ? image.substring(1) : image;
  return '$base/$path';
}

String _meta(String keyAttribute, String key, String? value) =>
    (value == null || value.isEmpty)
        ? ''
        : '<meta $keyAttribute="$key" content="${_escapeAttribute(value)}">';

/// Values come from configuration a user wrote. One with a quote in it would
/// close the attribute and turn everything after it into markup.
///
/// The two modes matter. The default `HtmlEscape` also escapes `/`, which
/// turns every URL into `https:&#47;&#47;example.com` -- browsers decode it,
/// but it is unreadable and not every consumer of an Open Graph tag is a
/// browser. Attribute mode escapes `&`, `<`, `>` and `"` and leaves the slash
/// alone, which is what an attribute needs and all it needs.
String _escapeAttribute(String value) =>
    const HtmlEscape(HtmlEscapeMode.attribute).convert(value);

/// Element content, where a quote is harmless and a `<` is not.
String _escapeText(String value) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(value);

/// The title for a project, from whichever key it uses.
///
/// The scaffold writes `defaultTitle` and this reads `title`; for a while it
/// read only the latter, so the configuration a new project shipped with was
/// ignored and the page kept the package name. Both are read, the explicit one
/// wins, and [fallback] is used before the package name ever is.
String dvSeoTitle(Map<Object?, Object?> seo, String fallback) {
  final title = seo['title'] ?? seo['defaultTitle'];
  final text = title == null ? '' : '$title'.trim();
  return text.isEmpty ? fallback : text;
}

/// The description for a project, from whichever key it uses.
String? dvSeoDescription(Map<Object?, Object?> seo) {
  final value = seo['description'] ?? seo['defaultDescription'];
  final text = value == null ? '' : '$value'.trim();
  return text.isEmpty ? null : text;
}

/// Strip what `flutter build web` leaves behind for the developer, and fill
/// in what it leaves blank.
///
/// The file Flutter writes is a template and it ships as one. Two long
/// comments address the developer directly — one explaining `--base-href`,
/// one explaining how to customise `flutter_bootstrap.js` — and both reach
/// production on every page of every Dartvel site. The
/// `apple-mobile-web-app-title` carries the Dart package name, which is what
/// iOS shows under the icon when someone saves the page, and `<html>` declares
/// no language at all.
///
/// The comments are instructions *about* the tags, so only the comments go:
/// removing `<base href>` or the bootstrap script with them would be a far
/// worse bug than shipping them.
String dvCleanShell(
  String shell, {
  required String siteName,
  String locale = 'en',
}) {
  var html = shell;

  // Only comments Flutter wrote. An application's own comment in its
  // index.html is not this function's business.
  for (final RegExp template in <RegExp>[
    RegExp(r'\s*<!--\s*\n?\s*If you are serving your web app.*?-->',
        dotAll: true),
    RegExp(r'\s*<!--\s*\n?\s*You can customize the "flutter_bootstrap\.js".*?-->',
        dotAll: true),
  ]) {
    html = html.replaceAll(template, '');
  }

  // A page with no lang is read in the reader's default voice.
  html = html.replaceFirstMapped(
    RegExp(r'<html(?![^>]*\blang=)([^>]*)>'),
    (Match m) => '<html lang="$locale"${m.group(1)}>',
  );

  final String escaped = const HtmlEscape(HtmlEscapeMode.attribute)
      .convert(siteName);
  html = html.replaceFirstMapped(
    RegExp(r'(<meta name="apple-mobile-web-app-title" content=")[^"]*(")'),
    (Match m) => '${m.group(1)}$escaped${m.group(2)}',
  );

  return html;
}


/// One URL per locale for [route]: the default locale unprefixed, every
/// other under its own path prefix, on [siteUrl].
///
/// A route that already carries a locale prefix -- the prerender walks
/// /fr/pricing as well as /pricing -- gets the same set as its unprefixed
/// form, so the prefix is never doubled. A single locale yields nothing, so
/// no lone hreflang is written.
Map<String, String> dvSeoAlternatesFor({
  required String siteUrl,
  required String route,
  required List<String> locales,
  required String defaultLocale,
}) {
  if (locales.length < 2) return const <String, String>{};
  final String base = siteUrl.endsWith('/') ? siteUrl.substring(0, siteUrl.length - 1) : siteUrl;

  // Strip a leading locale segment, whichever locale it is.
  List<String> segments = route.split('/').where((String s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty &&
      locales.any((String l) => l.toLowerCase() == segments.first.toLowerCase())) {
    segments = segments.sublist(1);
  }
  final String bare = segments.isEmpty ? '/' : '/${segments.join('/')}';

  return <String, String>{
    for (final String locale in locales)
      locale: locale == defaultLocale
          ? '$base$bare'
          : '$base/${locale.toLowerCase()}$bare',
  };
}
