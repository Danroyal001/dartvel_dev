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
  String type = 'website',
}) {
  final tags = <String>[
    '<title>${_escapeText(title)}</title>',
    _meta('name', 'description', description),
    if (siteUrl != null && siteUrl.isNotEmpty)
      '<link rel="canonical" href="${_escapeAttribute(siteUrl)}">',
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

  final at = out.indexOf('</head>');
  if (at < 0) return html;
  return '${out.substring(0, at)}$_open\n$head\n$_close\n${out.substring(at)}';
}

/// An Open Graph image has to be absolute: consumers fetch it with no base, so
/// a relative path resolves against their own host and 404s.
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
