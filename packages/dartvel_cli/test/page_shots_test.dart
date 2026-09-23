// `dartvel capture pages`: every page in a web build's sitemap, photographed
// at each size, with a page that shows no text reported as a failure.
//
// The site's zip used to be checked by screenshotting every page by hand.
// Chrome's own --screenshot fires on a timer, and on a runner it caught the
// three heaviest pages with their backgrounds drawn and their text not yet
// painted -- pictures that exist, pass a blank check and show nothing. These
// are the pieces that decide what gets photographed and what it is called.
import 'package:dartvel_cli/src/build/page_shots.dart';
import 'package:test/test.dart';

void main() {
  group('routes come from the sitemap', () {
    test('as paths, with the site root as /', () {
      const String xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://dartvel.dev</loc></url>
  <url><loc>https://dartvel.dev/docs</loc></url>
  <url><loc>https://dartvel.dev/docs/ai</loc></url>
  <url><loc>https://dartvel.dev/docs/ai</loc></url>
</urlset>''';

      expect(dvSitemapRoutes(xml), <String>['/', '/docs', '/docs/ai']);
    });

    test('an empty sitemap photographs the home page', () {
      expect(dvSitemapRoutes('<urlset></urlset>'), <String>['/']);
    });
  });

  group('a page is photographed once its text stops changing', () {
    // The docs shell draws its sidebar before the article, which loads
    // separately: waiting for any text at all photographed /docs/workers
    // with a sidebar and an empty page.
    test('not while it is still growing', () {
      final DVTextSettle settle = DVTextSettle();
      expect(<bool>[for (final int n in <int>[0, 120, 120, 2400]) settle.add(n)],
          <bool>[false, false, false, false]);
    });

    test('once it has held for three looks', () {
      final DVTextSettle settle = DVTextSettle();
      expect(<bool>[for (final int n in <int>[120, 2400, 2400, 2400]) settle.add(n)],
          <bool>[false, false, false, true]);
    });

    // Three looks is 1.5 seconds, and the docs sidebar holds still for
    // longer than that while the route's own code is still being fetched:
    // each page is a deferred library, so the article arrives in a second
    // chunk after the shell has drawn. One build photographed 23 of 57 pages
    // that way, 12 of them byte-identical to each other, and the check that
    // every page painted something passed on all of them, because a sidebar
    // is something.
    //
    // So the page is only still once the network is still too. The count of
    // resources the page has fetched stands in for that: it climbs while the
    // chunk is on its way and stops when it has arrived.
    test('not while the page is still fetching its own code', () {
      final DVTextSettle settle = DVTextSettle();
      expect(
        <bool>[
          for (final (int, int) look in <(int, int)>[
            (420, 14),
            (420, 15),
            (420, 16),
            (420, 17),
          ])
            settle.add(look.$1, look.$2),
        ],
        everyElement(isFalse),
        reason: 'the text held still at the shell while the article was '
            'still being fetched',
      );
    });

    test('once the text and the fetching have both stopped', () {
      final DVTextSettle settle = DVTextSettle();
      expect(
        <bool>[
          for (final (int, int) look in <(int, int)>[
            (420, 14),
            (420, 15),
            (2400, 18),
            (2400, 18),
            (2400, 18),
          ])
            settle.add(look.$1, look.$2),
        ],
        <bool>[false, false, false, false, true],
      );
    });

    test('never while there is none', () {
      final DVTextSettle settle = DVTextSettle();
      expect(<bool>[for (final int n in <int>[0, 0, 0, 0]) settle.add(n)],
          everyElement(isFalse));
    });
  });

  test('each shot is named for its route and size', () {
    expect(dvShotName('/', const DVShotSize(1440, 900)), 'home-1440x900.png');
    expect(dvShotName('/docs/ai', const DVShotSize(390, 844)),
        'docs_ai-390x844.png');
  });

  group('sizes', () {
    test('parse from the flag', () {
      expect(dvParseShotSizes('1440x900, 390x844'), const <DVShotSize>[
        DVShotSize(1440, 900),
        DVShotSize(390, 844),
      ]);
    });

    test('a malformed size is refused, not skipped', () {
      expect(() => dvParseShotSizes('1440x900,wide'), throwsFormatException);
    });
  });
}
