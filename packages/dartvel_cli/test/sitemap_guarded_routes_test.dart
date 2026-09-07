// A sitemap is a list of URLs handed to strangers.
//
// NEW_SPEC.md says "Sensitive, private, and authenticated routes are excluded
// by default". They were not: the sitemap was built by scraping every
// `path:` literal out of the generated router with a regular expression,
// which cannot see the `redirect:` guard block sitting three lines below the
// path it just matched. So /admin, /billing and every route behind a folder
// guard were published to crawlers.
//
// The guard is still enforced when somebody follows the link, so this is
// disclosure rather than access -- but the URL of an internal tool is worth
// having, and a sitemap is the one file written specifically to be read by
// people who were not invited.
import 'dart:io';

import 'package:dartvel_cli/src/build/static_seo.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> _routerFor(Directory root) async {
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'sitemap_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'Sitemap App',
    seoTitle: 'Sitemap App',
    seoDesc: 'Sitemap App',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'fade',
    durationMs: 200,
    curve: 'easeInOut',
    normalizeTrailing: true,
    notFoundRedirect: '',
    plugins: const <String>[],
    webPrerender: false,
    ota: false,
    dv: YamlMap.wrap(<String, Object?>{}),
  );
  return File(
    p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'),
  ).readAsStringSync();
}

void main() {
  group('the generator says which routes it guards', () {
    test('a page declaring a policy is listed, an open page is not', () async {
      final Directory root = await Directory.systemTemp.createTemp(
        'dartvel_sitemap_policy_',
      );
      try {
        Directory(
          p.join(root.path, 'lib', 'dartvel_client'),
        ).createSync(recursive: true);
        Directory(
          p.join(root.path, 'lib', 'pages'),
        ).createSync(recursive: true);

        File(p.join(root.path, 'lib', 'pages', 'admin.dart'))
            .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage(policy: DVPolicies.viewAdmin)
Widget adminPage(BuildContext context) => const SizedBox.shrink();
''');
        File(p.join(root.path, 'lib', 'pages', 'about.dart'))
            .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage()
Widget aboutPage(BuildContext context) => const SizedBox.shrink();
''');

        final String router = await _routerFor(root);

        expect(router, contains('dartvelGuardedRoutes'));
        expect(dvGuardedRoutes(router), contains('/admin'));
        expect(dvGuardedRoutes(router), isNot(contains('/about')));
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('a page under a guarded directory is listed too', () async {
      // The directory convention is the older of the two guards and the one
      // most applications actually use, so a check that only understood
      // @DVPage(policy:) would still publish every private route.
      final Directory root = await Directory.systemTemp.createTemp(
        'dartvel_sitemap_dir_',
      );
      try {
        Directory(
          p.join(root.path, 'lib', 'dartvel_client'),
        ).createSync(recursive: true);
        Directory(
          p.join(root.path, 'lib', 'pages', 'account'),
        ).createSync(recursive: true);

        File(p.join(root.path, 'lib', 'pages', 'account', '_guard.dart'))
            .writeAsStringSync('''
Future<String?> guard(Object? context, Object? state) async => null;
''');
        File(p.join(root.path, 'lib', 'pages', 'account', 'billing.dart'))
            .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage()
Widget billingPage(BuildContext context) => const SizedBox.shrink();
''');
        File(p.join(root.path, 'lib', 'pages', 'index.dart'))
            .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage()
Widget homePage(BuildContext context) => const SizedBox.shrink();
''');

        final String router = await _routerFor(root);

        expect(dvGuardedRoutes(router), contains('/account/billing'));
        expect(dvGuardedRoutes(router), isNot(contains('/')));
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  });

  group('the sitemap leaves guarded routes out', () {
    test('a guarded route is not published', () {
      final String xml = dvSitemap(
        routes: <String>['/', '/about', '/admin'],
        siteUrl: 'https://example.test',
        guarded: <String>{'/admin'},
      );

      expect(xml, contains('https://example.test/about'));
      expect(xml, isNot(contains('/admin')));
    });

    test('a guarded federated route is not published either', () {
      // A module mounted under the parent's domain is listed under the
      // parent, so the same omission has to apply on that path or mounting a
      // module becomes the way around the rule.
      final String xml = dvSitemap(
        routes: <String>['/'],
        federated: <String>['/shop/orders'],
        siteUrl: 'https://example.test',
        guarded: <String>{'/shop/orders'},
      );

      expect(xml, isNot(contains('/shop/orders')));
    });

    test('with nothing guarded the sitemap is unchanged', () {
      expect(
        dvSitemap(routes: <String>['/', '/about'], siteUrl: 'https://e.test'),
        contains('https://e.test/about'),
      );
    });
  });

  group('reading the list back out of a generated router', () {
    test('an empty list parses as empty rather than as one empty route', () {
      expect(
        dvGuardedRoutes('const List<String> dartvelGuardedRoutes = '
            '<String>[];'),
        isEmpty,
      );
    });

    test('a router with no list at all is not an error', () {
      // An application generated before this existed, or one with no pages.
      expect(dvGuardedRoutes('void main() {}'), isEmpty);
    });
  });
}
