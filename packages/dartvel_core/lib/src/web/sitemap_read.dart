/// The site's own sitemap.xml, read back for the human `/sitemap` page.
///
/// One source: the page a reader sees lists exactly what the file a crawler
/// reads lists, in the same order, so the two can never disagree. A file that
/// is not a sitemap (a 404 page, an empty body) gives no links rather than an
/// exception, and the page says so.
library;

import 'package:xml/xml.dart';

/// One `<url>` of a sitemap.
class DVSitemapLink {
  const DVSitemapLink({required this.url, required this.path, this.lastModified, this.external = false});

  /// The address as the file gives it.
  final String url;

  /// The path on this site (`/docs/start`), or the full address when the link
  /// leaves the site.
  final String path;

  /// `<lastmod>`, which the protocol makes optional.
  final DateTime? lastModified;

  /// True when the link points at another site than [dvReadSitemap]'s
  /// `siteUrl`.
  final bool external;
}

/// The links in [xml], a sitemap `<urlset>`, in file order. [siteUrl], when
/// given, decides which links are this site's (shown as paths) and which leave
/// it; without it every absolute link is read as this site's.
List<DVSitemapLink> dvReadSitemap(String xml, {String? siteUrl}) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(xml);
  } on Object {
    return const <DVSitemapLink>[];
  }
  final XmlElement root = document.rootElement;
  if (root.name.local != 'urlset') return const <DVSitemapLink>[];
  final Uri? site = siteUrl == null ? null : Uri.tryParse(siteUrl);
  final List<DVSitemapLink> links = <DVSitemapLink>[];
  for (final XmlElement url in root.childElements.where((XmlElement element) => element.name.local == 'url')) {
    final String loc = _child(url, 'loc')?.trim() ?? '';
    if (loc.isEmpty) continue;
    final Uri? address = Uri.tryParse(loc);
    final bool external = site != null && address != null && address.hasAuthority && address.host != site.host;
    final String path = external || address == null || !address.hasAuthority
        ? loc
        : (address.path.isEmpty ? '/' : address.path) + (address.hasQuery ? '?${address.query}' : '');
    final String? lastmod = _child(url, 'lastmod')?.trim();
    links.add(DVSitemapLink(
      url: loc,
      path: path,
      lastModified: lastmod == null || lastmod.isEmpty ? null : _date(lastmod),
      external: external,
    ));
  }
  return links;
}

/// A W3C date: a bare day (`2026-11-12`) is that calendar day, not midnight in
/// whatever zone reads it.
DateTime? _date(String text) =>
    DateTime.tryParse(text.contains('T') ? text : '${text}T00:00:00Z')?.toUtc();

String? _child(XmlElement parent, String name) {
  for (final XmlElement child in parent.childElements) {
    if (child.name.local == name) return child.innerText;
  }
  return null;
}
