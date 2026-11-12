// Every site with a sitemap gets a readable /sitemap page (queue 6d10).
//
// They used to be documents the build wrote by hand at build time, which put
// two pages outside the router: no @DVPage, no theme, no capture, and -- for
// the offline page -- no way to be a page at all, since it is shown exactly
// when the network is gone. As routes they go through the one render path,
// like every other page.
//
// What is pinned here is the generator's half: that the routes are declared,
// that they are not declared over an application page, and that they are in
// the manifest and the typed targets, so a build can see them and a person
// can name one.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';


Future<Directory> _generate(Map<String, String> pages, {Map<String, Object?> dv = const <String, Object?>{}}) async {
  final Directory root = await Directory.systemTemp.createTemp('dartvel_sitemap_route_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  pages.forEach((String name, String source) {
    File(p.join(root.path, 'lib', 'pages', name))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(source);
  });
  await ClientGenerator.generate(
    root: root.path, pagesDir: 'lib/pages', pkgName: 'shop_app', buildId: 'test-build',
    backendHost: '127.0.0.1', backendPort: 3000, devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test', apiBasePath: '/api', envFiles: const <String>[],
    seoSiteName: 'Shop', seoTitle: 'Shop', seoDesc: 'Things we sell.', seoImage: '', seoTwitter: '',
    defaultTransition: 'fade', durationMs: 200, curve: 'easeInOut', normalizeTrailing: true,
    notFoundRedirect: '', plugins: const <String>[], ota: false, dv: YamlMap.wrap(dv),
  );
  return root;
}

String _page(String name, String annotation) => '''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

$annotation
Widget ${name}Page(BuildContext context) => const SizedBox.shrink();
''';

String _router(Directory root) => File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart')).readAsStringSync();

const Map<String, Object?> _withSiteUrl = <String, Object?>{
  'seo': <String, Object?>{'siteUrl': 'https://shop.example'},
};

void main() {
  test('a site with a sitemap serves /sitemap, built from the same site name and description', () async {
    final String router = _router(await _generate(<String, String>{'index.dart': _page('home', '@DVPage()')}, dv: _withSiteUrl));
    final int at = router.indexOf("path: '/sitemap'");
    expect(at, isNot(-1));
    final String block = router.substring(at, router.indexOf('),', router.indexOf('DVSitemapPage(', at)) + 2);
    expect(block, contains('DVSitemapPage('));
    expect(block, contains("siteUrl: 'https://shop.example'"));
    expect(block, contains('_defaultSeo.siteName'));
  });

  test('without a siteUrl there is no sitemap.xml, so no /sitemap page', () async {
    final String router = _router(await _generate(<String, String>{'index.dart': _page('home', '@DVPage()')}));
    expect(router, isNot(contains("path: '/sitemap'")));
  });

  test('an application page at /sitemap wins', () async {
    final String router = _router(await _generate(<String, String>{
      'index.dart': _page('home', '@DVPage()'),
      'sitemap.dart': _page('sitemap', "@DVPage(title: 'Our map')"),
    }, dv: _withSiteUrl));
    expect(router, isNot(contains('DVSitemapPage(')));
  });
}
