/// A route's own page: the shell with that page's head, structured data,
/// icon and crawler-visible document, minified.
///
/// One function for both ways a Dartvel site is served. `dartvel build web`
/// calls [dvRenderRoutePage] for every route at build time and writes the
/// result; the web-server binary calls the same function for each request,
/// with the same inputs the build wrote into its manifest. A second path was
/// how the served pages lost the captured links, headings and code blocks
/// and went out unminified while the static build kept them.
library;

import 'dart:convert';

import 'minify.dart';
import 'page_text.dart';
import 'page_data.dart' show dvApplyFavicon;
import 'seo_head.dart';
import 'structured_data.dart';

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
  String? robots,
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
      robots: robots,
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


/// What one route's page is made from: everything [dvRenderRoutePage] needs,
/// and nothing that varies by request.
///
/// The static build makes one per route and renders it; the web-server build
/// writes the same values into its manifest, and the server reads them back
/// and renders the same page on request.
class DVRoutePage {
  const DVRoutePage({
    required this.route,
    required this.title,
    this.description,
    this.siteUrl,
    this.image,
    this.siteName,
    this.alternates = const <String, String>{},
    this.defaultAlternate,
    this.favicon,
    this.schemaType,
    this.robots,
    this.content,
    this.html,
    this.text = const <String>[],
  });

  factory DVRoutePage.fromJson(Map<String, Object?> json) => DVRoutePage(
        route: '${json['route'] ?? '/'}',
        title: '${json['title'] ?? ''}',
        description: json['description'] as String?,
        siteUrl: json['siteUrl'] as String?,
        image: json['image'] as String?,
        siteName: json['siteName'] as String?,
        alternates: <String, String>{
          for (final MapEntry<Object?, Object?> e
              in ((json['alternates'] as Map?) ?? const <Object?, Object?>{}).entries)
            '${e.key}': '${e.value}',
        },
        defaultAlternate: json['defaultAlternate'] as String?,
        favicon: json['favicon'] as String?,
        schemaType: json['schemaType'] as String?,
        robots: json['robots'] as String?,
        content: json['content'] as String?,
        html: json['html'] as String?,
        text: <String>[
          for (final Object? line in (json['text'] as List?) ?? const <Object?>[])
            '$line',
        ],
      );

  final String route;
  final String title;
  final String? description;
  final String? siteUrl;
  final String? image;
  final String? siteName;
  final Map<String, String> alternates;
  final String? defaultAlternate;

  /// The page's own icon, as the build resolved it.
  final String? favicon;

  /// What the page is, for its structured data; null is a WebPage.
  final String? schemaType;

  /// What crawlers may do with the page, as a robots meta says it:
  /// `noindex, nofollow` for a page no search engine should keep, such as
  /// Studio's. Null writes no tag.
  final String? robots;

  /// Prerendered text a model page carries in its metadata.
  final String? content;

  /// The crawler-visible document captured from the page's semantics tree:
  /// headings, links, emphasis and code blocks, as the app declares them.
  final String? html;

  /// Plain lines from the page's source, used only when nothing was captured.
  final List<String> text;

  /// The same page at [path], for a route matched by a pattern.
  DVRoutePage at(String path) => path == route
      ? this
      : DVRoutePage(
          route: path,
          title: title,
          description: description,
          siteUrl: siteUrl,
          image: image,
          siteName: siteName,
          alternates: alternates,
          defaultAlternate: defaultAlternate,
          favicon: favicon,
          schemaType: schemaType,
          robots: robots,
          content: content,
          html: html,
          text: text,
        );

  Map<String, Object?> toJson() => <String, Object?>{
        'route': route,
        'title': title,
        if (description != null) 'description': description,
        if (siteUrl != null) 'siteUrl': siteUrl,
        if (image != null) 'image': image,
        if (siteName != null) 'siteName': siteName,
        if (alternates.isNotEmpty) 'alternates': alternates,
        if (defaultAlternate != null) 'defaultAlternate': defaultAlternate,
        if (favicon != null) 'favicon': favicon,
        if (schemaType != null) 'schemaType': schemaType,
        if (robots != null) 'robots': robots,
        if (content != null) 'content': content,
        if (html != null) 'html': html,
        if (text.isNotEmpty) 'text': text,
      };
}

/// [page] rendered into [shell]: the head, the structured data, the icon, the
/// crawler-visible document, minified. Called by the static build for every
/// route and by the web server for every request, so the two agree byte for
/// byte.
///
/// The captured document when there is one. The source-literal lines are the
/// last resort for a route nothing captured, and [onUncaptured] is told, so a
/// server that falls back says so.
String dvRenderRoutePage(
  String shell,
  DVRoutePage page, {
  void Function(String route)? onUncaptured,
}) {
  final String head = dvStaticPage(
    shell: shell,
    route: page.route,
    title: page.title,
    description: page.description,
    siteUrl: page.siteUrl,
    image: page.image,
    siteName: page.siteName,
    alternates: page.alternates,
    defaultAlternate: page.defaultAlternate,
    favicon: page.favicon,
    schemaType: page.schemaType,
    robots: page.robots,
    content: page.content,
  );
  final String? captured = page.html;
  final String body;
  if (captured != null && captured.trim().isNotEmpty) {
    body = dvApplyPageHtml(head, captured, path: page.route);
  } else {
    if (page.text.isNotEmpty) onUncaptured?.call(page.route);
    body = dvApplyPageText(head, page.text, path: page.route);
  }
  return dvMinifyHtml(body);
}
