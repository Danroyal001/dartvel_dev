import 'package:dartvel_shelf/src/server.dart' show getMimeType;
import 'package:test/test.dart';

/// Files every site serves for crawlers and people, by their real types.
void main() {
  test('a sitemap and its stylesheet are XML, not a download', () {
    expect(getMimeType('/srv/web/sitemap.xml'), 'application/xml; charset=utf-8');
    expect(getMimeType('/srv/web/sitemap.xsl'), 'application/xml; charset=utf-8');
  });

  test('robots.txt and llms.txt are plain text in UTF-8', () {
    expect(getMimeType('/srv/web/robots.txt'), 'text/plain; charset=utf-8');
    expect(getMimeType('/srv/web/llms.txt'), 'text/plain; charset=utf-8');
  });

  test('the extension decides, whatever its case', () {
    expect(getMimeType('/srv/web/SITEMAP.XML'), 'application/xml; charset=utf-8');
  });

  test('common web types are named', () {
    expect(getMimeType('/srv/web/manifest.webmanifest'), 'application/manifest+json');
    expect(getMimeType('/srv/web/favicon.ico'), 'image/x-icon');
    expect(getMimeType('/srv/web/hero.webp'), 'image/webp');
    expect(getMimeType('/srv/web/fonts/inter.woff2'), 'font/woff2');
    expect(getMimeType('/srv/web/main.dart.js.map'), 'application/json');
  });

  test('a contact card and a calendar invite open on a phone instead of downloading as bytes', () {
    // Served as octet-stream, a phone saves /card.vcf as an unknown file
    // instead of offering to add the contact (sigmadev.digital, 13 Nov 2026).
    expect(getMimeType('/srv/web/card.vcf'), 'text/vcard; charset=utf-8');
    expect(getMimeType('/srv/web/Contact.VCARD'), 'text/vcard; charset=utf-8');
    expect(getMimeType('/srv/web/call.ics'), 'text/calendar; charset=utf-8');
  });

  test('types that were already right are unchanged', () {
    expect(getMimeType('/srv/web/index.html'), 'text/html');
    expect(getMimeType('/srv/web/main.dart.js'), 'application/javascript');
    expect(getMimeType('/srv/web/manifest.json'), 'application/json');
    expect(getMimeType('/srv/web/LICENSE'), 'application/octet-stream');
  });
}
