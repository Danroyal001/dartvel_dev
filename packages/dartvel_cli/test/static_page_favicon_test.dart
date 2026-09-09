// The favicon a statically generated page wears.
//
// `@DVModel(favicon:)` was read in exactly one place: the web server's page
// resolver. `dartvel build web` writes the same pages ahead of time and
// never looked at the value, so a site built statically served the shell's
// icon on every product, article and profile while the declaration sat in
// the model doing nothing. The specification asks for a route-specific
// favicon in the SSG output by name, and there was not one.
//
// `dartvel.seo.favicon` had it worse: it reached the web server and nothing
// else, so a project could set an application-wide page icon and get it on
// none of its static pages.
import 'package:dartvel_cli/src/build/static_generation.dart';
import 'package:dartvel_cli/src/build/static_seo.dart';
import 'package:test/test.dart';

const String shell =
    '<html><head><title>App</title><link rel="icon" href="favicon.png">'
    '</head><body><div id="app"></div></body></html>';

/// The shape the model generator writes into `model_pages.g.dart`.
const String generated = '''
const List<DVModelPageSpec> dartvelModelPages = <DVModelPageSpec>[
  DVModelPageSpec(
    model: 'Product',
    route: '/products/:slug',
    param: 'slug',
    table: 'products',
    keyField: 'slug',
    titleField: 'name',
    contentFields: <String>['body'],
    imageField: 'cover',
    publishedField: null,
    schemaType: 'Product',
    favicon: '/icons/product.png',
  ),
  DVModelPageSpec(
    model: 'Article',
    route: '/articles/:slug',
    param: 'slug',
    table: 'articles',
    keyField: 'slug',
    titleField: 'title',
    contentFields: <String>['body'],
    imageField: null,
    publishedField: null,
    schemaType: null,
    favicon: null,
  ),
];
''';

void main() {
  group('a static page carries the icon it was given', () {
    test('the link points at it', () {
      final String page = dvStaticPage(
        shell: shell,
        route: '/products/pro-kit',
        title: 'Pro Kit',
        favicon: '/icons/favicon-0123456789abcdef.png',
      );

      expect(page, contains('rel="icon"'));
      expect(page, contains('/icons/favicon-0123456789abcdef.png'));
    });

    test('and the shell\'s icon is replaced, not joined', () {
      // Two icon links leave the browser to pick, and which one it picks is
      // not something this build gets to decide.
      final String page = dvStaticPage(
        shell: shell,
        route: '/products/pro-kit',
        title: 'Pro Kit',
        favicon: '/icons/favicon-0123456789abcdef.png',
      );

      expect(page, isNot(contains('href="favicon.png"')));
      expect(RegExp('rel="icon"').allMatches(page).length, 1);
    });

    test('a page given none keeps the shell\'s', () {
      final String page = dvStaticPage(
        shell: shell,
        route: '/about',
        title: 'About',
      );

      expect(page, contains('href="favicon.png"'));
    });
  });

  group('reading what the models declared', () {
    test('a declared favicon comes back under the model\'s route', () {
      expect(
        dvModelPageFavicons(generated),
        containsPair('/products/:slug', '/icons/product.png'),
      );
    });

    test('a model that declared none is not in the map at all', () {
      // Absent rather than null, so a caller falling back to the
      // application's value does not have to tell "declared nothing" from
      // "declared and it parsed to null".
      expect(dvModelPageFavicons(generated).containsKey('/articles/:slug'),
          isFalse);
    });

    test('no manifest, no entries', () {
      expect(dvModelPageFavicons(''), isEmpty);
    });

    test('a spec with no favicon key does not take the next model\'s', () {
      // What an older generator wrote. Reaching forward past the end of one
      // spec hands a product page the article's icon, which looks exactly
      // like the feature working.
      const String older = '''
const List<DVModelPageSpec> dartvelModelPages = <DVModelPageSpec>[
  DVModelPageSpec(
    model: 'Product',
    route: '/products/:slug',
    keyField: 'slug',
  ),
  DVModelPageSpec(
    model: 'Article',
    route: '/articles/:slug',
    keyField: 'slug',
    favicon: '/icons/article.png',
  ),
];
''';

      final Map<String, String> favicons = dvModelPageFavicons(older);

      expect(favicons.containsKey('/products/:slug'), isFalse);
      expect(favicons['/articles/:slug'], '/icons/article.png');
    });
  });

  group('the fallback chain a written page walks', () {
    // Model, then application. The specification names a module level
    // between them, and there is no third lookup for it: a module's models
    // are generated from the module's own project, so a favicon a module
    // declared is already sitting in the spec by the time this reads it.
    final Map<String, String> favicons = dvModelPageFavicons(generated);

    test('the model\'s own beats the application\'s', () {
      expect(
        dvPageFavicon('/products/pro-kit', favicons, application: '/app.png'),
        '/icons/product.png',
      );
    });

    test('a model that declared none falls through to the application\'s', () {
      expect(
        dvPageFavicon('/articles/hello', favicons, application: '/app.png'),
        '/app.png',
      );
    });

    test('a page belonging to no model still gets the application\'s', () {
      // /about is not a model page and is still a page on this site. It
      // wearing a different icon from its neighbours is the sort of thing
      // nobody files and everybody sees.
      expect(
        dvPageFavicon('/about', favicons, application: '/app.png'),
        '/app.png',
      );
    });

    test('nothing declared anywhere leaves the shell its own', () {
      expect(dvPageFavicon('/about', favicons), isNull);
      expect(dvPageFavicon('/articles/hello', favicons), isNull);
    });
  });

  group('matching a written page back to its model', () {
    test('a generated path finds the template that serves it', () {
      expect(
        dvTemplateFor('/products/pro-kit', const <String>[
          '/about',
          '/products/:slug',
          '/articles/:slug',
        ]),
        '/products/:slug',
      );
    });

    test('a path with the wrong depth belongs to neither', () {
      // /products/pro-kit/reviews is not the product page, and handing it
      // the product icon would be a wrong answer that looks like a right
      // one.
      expect(
        dvTemplateFor('/products/pro-kit/reviews',
            const <String>['/products/:slug']),
        isNull,
      );
    });

    test('a page no template serves has no model', () {
      expect(dvTemplateFor('/about', const <String>['/products/:slug']),
          isNull);
    });
  });
}
