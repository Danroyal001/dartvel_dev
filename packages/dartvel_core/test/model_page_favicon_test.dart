// A model page's favicon, which nothing ever set.
//
// DVPageData has the field and the head writer emits it. The resolver filled
// the title, the description, the image and the structured data and left the
// favicon null, so every model page showed the shell's -- a product page, an
// article, a profile, all wearing the application's icon with nothing saying
// they could wear their own.
//
// The specification's fallbacks are configured model favicon, then module,
// then application. A module's models are generated from the module's own
// project, so the favicon its spec carries is already the module's: the
// three levels are the spec's own value and then the application's.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVModelPageSpec spec({String? favicon}) => DVModelPageSpec(
      model: 'Product',
      route: '/products/:slug',
      param: 'slug',
      table: 'products',
      keyField: 'slug',
      titleField: 'name',
      contentFields: const <String>['body'],
      favicon: favicon,
    );

const Map<String, Object?> row = <String, Object?>{
  'slug': 'a-thing',
  'name': 'A thing',
  'body': 'Something about it.',
};

void main() {
  group('which favicon a page gets', () {
    test('the one the model declared', () {
      final DVPageData data =
          dvModelPageData(spec(favicon: '/icons/product.png'), row);

      expect(data.favicon, '/icons/product.png');
    });

    test('the application\'s when the model declared none', () {
      final DVPageData data = dvModelPageData(
        spec(),
        row,
        applicationFavicon: '/icons/app.png',
      );

      expect(data.favicon, '/icons/app.png');
    });

    test('the model wins over the application', () {
      final DVPageData data = dvModelPageData(
        spec(favicon: '/icons/product.png'),
        row,
        applicationFavicon: '/icons/app.png',
      );

      expect(data.favicon, '/icons/product.png');
    });

    test('null when neither said anything, so the shell keeps its own', () {
      // Not the featured image. An unresized photograph served as a 32-pixel
      // icon is several hundred kilobytes on every page, which is worse than
      // the shell favicon it replaced.
      final DVPageData data = dvModelPageData(spec(), row);

      expect(data.favicon, isNull);
    });
  });

  group('it reaches the head', () {
    test('a page with one writes the link', () {
      final String html = dvApplyPageExtras(
        '<html><head></head><body></body></html>',
        dvModelPageData(spec(favicon: '/icons/product.png'), row),
      );

      expect(html, contains('/icons/product.png'));
      expect(html, contains('rel="icon"'));
    });

    test('a page without one writes no link at all', () {
      final String html = dvApplyPageExtras(
        '<html><head></head><body></body></html>',
        dvModelPageData(spec(), row),
      );

      expect(html, isNot(contains('rel="icon"')));
    });
  });

  group('through the resolver', () {
    test('the application fallback reaches a rendered row', () async {
      final DVPageDataResolver resolve = dvModelPageResolver(
        <DVModelPageSpec>[spec()],
        (String sql, List<Object?> params) async => <Map<String, Object?>>[row],
        applicationFavicon: '/icons/app.png',
      );

      final DVPageData? data = await resolve(
        const DVPageRequest(
          path: '/products/a-thing',
          pattern: '/products/:slug',
          params: <String, String>{'slug': 'a-thing'},
        ),
      );

      expect(data?.favicon, '/icons/app.png');
    });
  });
}
