// dartvel.dev is a static site with no sign-in. The account pages the router
// generates by default would be served at /login and /sign-up, listed in
// sitemap.xml, and every form on them would fail against a backend that does
// not exist.
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> paths(List<RouteBase> routes) => <String>[
      for (final RouteBase route in routes) ...<String>[
        if (route is GoRoute) route.path,
        ...paths(route.routes),
      ],
    ];

void main() {
  test('the site serves no account pages', () {
    expect(dartvelAccountPages, isEmpty);
    final List<String> served = paths(dartvelRoutes());
    for (final String path in <String>['/login', 'login', '/sign-up', 'sign-up']) {
      expect(served, isNot(contains(path)));
    }
    expect(served, contains('/cloud'));
  });
}
