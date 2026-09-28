// dartvel.dev runs as a web-server binary with Studio, and the one person
// granted Studio.access needs somewhere to sign in. So the site serves the
// sign-in page and no other account page: no /sign-up, because nobody but
// the owner has a reason to hold an account here, and no profile, security,
// sessions or delete pages that would sit in the sitemap for visitors who
// cannot reach them.
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> paths(List<RouteBase> routes) => <String>[
      for (final RouteBase route in routes) ...<String>[
        if (route is GoRoute) route.path,
        ...paths(route.routes),
      ],
    ];

void main() {
  test('the site serves the sign-in page and no other account page', () {
    final List<String> served = paths(dartvelRoutes());
    expect(served, contains('/login'));
    for (final String path in <String>[
      '/sign-up',
      'sign-up',
      '/account/profile',
      '/account/security',
      '/account/sessions',
      '/account/delete',
    ]) {
      expect(served, isNot(contains(path)));
    }
    expect(served, contains('/cloud'));
  });
}
