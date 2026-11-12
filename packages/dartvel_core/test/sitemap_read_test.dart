// Reading the site's own sitemap.xml for the human /sitemap page (queue 6d10):
// one source, so the page a reader sees and the file a crawler reads never
// disagree.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String sitemap = '''<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="/sitemap.xsl"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://example.com/</loc><lastmod>2026-11-12</lastmod><priority>1.0</priority></url>
  <url><loc>https://example.com/docs/getting-started</loc><lastmod>2026-11-10T08:30:00+00:00</lastmod></url>
  <url><loc>https://example.com/pricing</loc></url>
</urlset>''';

void main() {
  test('every url, in the order the file lists them, with its path and date', () {
    final List<DVSitemapLink> links = dvReadSitemap(sitemap);
    expect(links.map((DVSitemapLink link) => link.path), <String>['/', '/docs/getting-started', '/pricing']);
    expect(links.first.url, 'https://example.com/');
    expect(links[0].lastModified, DateTime.utc(2026, 11, 12));
    expect(links[1].lastModified, DateTime.utc(2026, 11, 10, 8, 30));
    expect(links[2].lastModified, isNull, reason: 'lastmod is optional in the protocol');
  });

  test('a file that is not a sitemap gives no links rather than throwing', () {
    expect(dvReadSitemap('<html><body>Not found</body></html>'), isEmpty);
    expect(dvReadSitemap('not xml at all'), isEmpty);
    expect(dvReadSitemap(''), isEmpty);
  });

  test('a link to another site keeps its full address and is marked external', () {
    final List<DVSitemapLink> links = dvReadSitemap(sitemap.replaceFirst('https://example.com/pricing', 'https://other.example/pricing'), siteUrl: 'https://example.com');
    expect(links.last.path, 'https://other.example/pricing');
    expect(links.last.external, isTrue);
    expect(links.first.external, isFalse);
  });
}
