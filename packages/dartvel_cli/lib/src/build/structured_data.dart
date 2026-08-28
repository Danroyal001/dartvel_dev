/// Schema.org structured data for a generated page.
library dartvel_cli.build.structured_data;

import 'dart:convert';

import 'static_seo.dart' show dvStaticCanonical;

/// JSON-LD describing what this page is.
///
/// OpenGraph and Twitter tags say how a link should *look* when shared. They
/// do not say what the page is: `og:type` is `website` for every page on
/// every site. Schema.org is the vocabulary that does, and it is what
/// produces a site name in a result, a breadcrumb trail under a link, and a
/// sitelinks search box.
///
/// The root gets `WebSite` and nothing else gets it — repeating it on every
/// page tells a crawler the site begins again at each URL. Inner pages get
/// `WebPage` pointing back at the site, and a `BreadcrumbList` built from the
/// path, because the path is the hierarchy in a URL-first framework.
String dvStructuredData({
  required String route,
  required String title,
  required String siteName,
  String? description,
  String? siteUrl,
  String? image,
}) {
  // Every identifier in this vocabulary is an absolute URL. Emitting it with
  // relative ones produces a block that validates and describes nothing.
  if (siteUrl == null || siteUrl.isEmpty) return '';

  final String root = siteUrl.endsWith('/')
      ? siteUrl.substring(0, siteUrl.length - 1)
      : siteUrl;
  final String canonical = dvStaticCanonical(root, route);
  final blocks = <Map<String, Object?>>[];

  if (route == '/') {
    blocks.add(<String, Object?>{
      '@context': 'https://schema.org',
      '@type': 'WebSite',
      'name': siteName,
      'url': root,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (image != null && image.isNotEmpty) 'image': image,
    });
  } else {
    blocks.add(<String, Object?>{
      '@context': 'https://schema.org',
      '@type': 'WebPage',
      'name': title,
      'url': canonical,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (image != null && image.isNotEmpty) 'image': image,
      'isPartOf': <String, Object?>{
        '@type': 'WebSite',
        'name': siteName,
        'url': root,
      },
    });
    blocks.add(_breadcrumbs(root: root, route: route, title: title));
  }

  return blocks.map(_script).join('\n');
}

/// A trail from the root to this page, one step per path segment.
Map<String, Object?> _breadcrumbs({
  required String root,
  required String route,
  required String title,
}) {
  final segments = route
      .split('/')
      .where((String segment) => segment.isNotEmpty)
      .toList();

  final items = <Map<String, Object?>>[
    <String, Object?>{
      '@type': 'ListItem',
      'position': 1,
      'name': 'Home',
      'item': root,
    },
  ];

  var path = '';
  for (var i = 0; i < segments.length; i++) {
    path = '$path/${segments[i]}';
    final bool last = i == segments.length - 1;
    items.add(<String, Object?>{
      '@type': 'ListItem',
      'position': i + 2,
      // The page's own title for the leaf, which is what it calls itself; a
      // readable version of the segment for the steps above it, which have no
      // page of their own to ask.
      'name': last ? title : _label(segments[i]),
      'item': '$root$path',
    });
  }

  return <String, Object?>{
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    'itemListElement': items,
  };
}

/// `getting-started` reads as `Getting Started`.
String _label(String segment) => segment
    .split(RegExp(r'[-_]'))
    .where((String word) => word.isNotEmpty)
    .map((String word) =>
        word[0].toUpperCase() + word.substring(1).toLowerCase())
    .join(' ');

/// One `<script type="application/ld+json">`.
///
/// `</script>` inside the JSON would end the element early and the rest of the
/// block would become markup in the page, so the slash is escaped. JSON reads
/// `<\/script>` as `</script>`, and HTML never sees the closing tag.
String _script(Map<String, Object?> data) {
  final String json = const JsonEncoder.withIndent('  ')
      .convert(data)
      .replaceAll('</', r'<\/');
  return '<script type="application/ld+json">\n$json\n</script>';
}
