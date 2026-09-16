// A route group adds nothing to a path, so an index page inside one is the
// index of the folder the group sits in.
//
// `lib/pages/(tabs)/index.page.dart` was routed at `/index`: the check for a
// root index ran before the group was stripped, and the nested-index rule
// only matched `something/index`. A tabs layout naming `DVRoutes.index` then
// refused every other page in the folder as belonging to no tab, because none
// of them extends `/index` -- which is how the example's shop, with its home
// page as the first tab, could not be generated at all.
import 'package:dartvel_cli/src/generators/route_utils.dart';
import 'package:test/test.dart';

void main() {
  group('an index page inside a route group', () {
    test('at the root is /', () {
      expect(RouteUtils.routeFor('lib/pages/(tabs)/index.page.dart', 'lib/pages'), '/');
      expect(RouteUtils.routeFor('lib/pages/(tabs)/index.dart', 'lib/pages'), '/');
    });

    test('in nested groups is still /', () {
      expect(
        RouteUtils.routeFor('lib/pages/(app)/(tabs)/index.page.dart', 'lib/pages'),
        '/',
      );
    });

    test('under a folder is the folder', () {
      expect(
        RouteUtils.routeFor('lib/pages/shop/(tabs)/index.page.dart', 'lib/pages'),
        '/shop',
      );
    });

    test('leaves the pages beside it where they were', () {
      expect(RouteUtils.routeFor('lib/pages/(tabs)/saved.dart', 'lib/pages'), '/saved');
      expect(
        RouteUtils.routeFor('lib/pages/(tabs)/orders/[id].page.dart', 'lib/pages'),
        '/orders/:id',
      );
      expect(RouteUtils.routeFor('lib/pages/index.page.dart', 'lib/pages'), '/');
      expect(RouteUtils.routeFor('lib/pages/blog/index.dart', 'lib/pages'), '/blog');
    });

    test('a page that is merely named like an index is not one', () {
      expect(RouteUtils.routeFor('lib/pages/(tabs)/reindex.dart', 'lib/pages'), '/reindex');
    });
  });
}
