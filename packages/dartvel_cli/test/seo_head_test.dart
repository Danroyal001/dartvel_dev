// The head tags a built web app ships with.
//
// `dartvel build web` produced an index.html whose title was the package name
// -- `dartvel_site` -- with no Open Graph tags at all, and a body that is empty
// until JavaScript runs. A crawler, a link preview in Slack, and a share on
// social all read exactly that, and none of them execute the app.
//
// The failure is quiet in the worst way: the page is perfect in a browser.
import 'package:dartvel_cli/src/build/seo_head.dart';
import 'package:test/test.dart';

void main() {
  group('building the tags', () {
    test('the title is the configured one, not the package name', () {
      final head = dvSeoHead(title: 'Dartvel — Flutter, full stack');

      expect(head, contains('<title>Dartvel — Flutter, full stack</title>'));
    });

    test('a description reaches both the meta tag and Open Graph', () {
      // Two consumers read two different tags for the same sentence, and a
      // page that sets only one previews as a blank card.
      final head = dvSeoHead(title: 'T', description: 'Flutter, full stack.');

      expect(head, contains('name="description" content="Flutter, full stack."'));
      expect(head, contains('property="og:description"'));
    });

    test('an image is absolute, because a relative one previews as nothing', () {
      // Open Graph consumers fetch the URL without a base. A relative path
      // resolves against their own host and 404s.
      final head = dvSeoHead(
        title: 'T',
        siteUrl: 'https://dartvel.dev',
        image: 'icons/Icon-512.png',
      );

      expect(head, contains('https://dartvel.dev/icons/Icon-512.png'));
      expect(head, isNot(contains('content="icons/Icon-512.png"')));
    });

    test('an image already absolute is left alone', () {
      final head = dvSeoHead(
        title: 'T',
        siteUrl: 'https://dartvel.dev',
        image: 'https://cdn.example.com/card.png',
      );

      expect(head, contains('https://cdn.example.com/card.png'));
      expect(head, isNot(contains('dartvel.dev/https')));
    });

    test('a canonical URL is emitted when the site is known', () {
      expect(dvSeoHead(title: 'T', siteUrl: 'https://dartvel.dev'),
          contains('rel="canonical" href="https://dartvel.dev"'));
      expect(dvSeoHead(title: 'T'), isNot(contains('canonical')));
    });

    test('values are escaped, not interpolated raw', () {
      // A title comes from configuration a user wrote. One with a quote in it
      // closes the attribute and everything after it becomes markup.
      final head = dvSeoHead(
        title: 'Dartvel: "batteries" & more',
        description: "It's <good>",
      );

      expect(head, isNot(contains('content="Dartvel: "batteries"')));
      expect(head, contains('&quot;'));
      expect(head, contains('&amp;'));
      expect(head, isNot(contains('<good>')));
    });
  });

  group('putting them in the page', () {
    const page = '<html><head>\n<title>dartvel_site</title>\n'
        '<meta name="description" content="A new Dartvel project">\n'
        '</head><body></body></html>';

    test('the generated title replaces the scaffolded one', () {
      final out = dvSeoApply(page, dvSeoHead(title: 'Dartvel'));

      expect(out, contains('<title>Dartvel</title>'));
      expect(out, isNot(contains('dartvel_site')));
      expect('<title>'.allMatches(out).length, 1);
    });

    test('the scaffolded description does not survive beside the new one', () {
      // Two description tags is not additive: which one a crawler reads is
      // undefined, and the placeholder is the one that reads as neglect.
      final out = dvSeoApply(
        page,
        dvSeoHead(title: 'Dartvel', description: 'Flutter, full stack.'),
      );

      expect(out, isNot(contains('A new Dartvel project')));
      expect('name="description"'.allMatches(out).length, 1);
    });

    test('applying twice is the same as applying once', () {
      // A rebuild runs over the previous build's output when nothing cleaned
      // it, and tags that accumulate are worse than tags that are wrong.
      final head = dvSeoHead(title: 'Dartvel', description: 'D');
      final once = dvSeoApply(page, head);

      expect(dvSeoApply(once, head), once);
    });

    test('a page with no head is returned unchanged rather than corrupted', () {
      expect(dvSeoApply('<body>x</body>', dvSeoHead(title: 'T')),
          '<body>x</body>');
    });
  });

  // The scaffold writes `defaultTitle` and `defaultDescription` under `seo:`,
  // and the build reads `title` and `description`. Nothing errored -- the
  // config a new project ships with was simply ignored, and the page kept the
  // package name. Both spellings are read, so an existing project keeps
  // working and a new one can use the shorter names.
  group('the keys a project actually writes', () {
    test('the scaffold spelling is honoured', () {
      expect(
        dvSeoTitle(const <Object?, Object?>{'defaultTitle': 'Welcome'}, 'pkg'),
        'Welcome',
      );
      expect(
        dvSeoDescription(
            const <Object?, Object?>{'defaultDescription': 'A Dartvel app'}),
        'A Dartvel app',
      );
    });

    test('the explicit spelling wins when both are present', () {
      expect(
        dvSeoTitle(
          const <Object?, Object?>{'title': 'Real', 'defaultTitle': 'Old'},
          'pkg',
        ),
        'Real',
      );
    });

    test('with neither, it is the fallback rather than the package name', () {
      // The package name in a title bar is the thing this exists to stop.
      expect(dvSeoTitle(const <Object?, Object?>{}, 'Dartvel'), 'Dartvel');
      expect(dvSeoDescription(const <Object?, Object?>{}), isNull);
    });
  });
}
