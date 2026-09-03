/// The head tags a web page ships with, assembled from what is known about
/// the page: the same tags whether a build writes them once or a server
/// writes them per request.
library;

import 'dart:convert';

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

/// Markers, so a rebuild replaces the block rather than adding another.
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

