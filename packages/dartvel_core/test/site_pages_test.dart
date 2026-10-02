// The pages a server serves, as data a backend can read.
//
// A site search, an llms.txt or a "related pages" list all need the same
// thing: every page's title and text. A web-server build already has it, in
// the route manifest it renders pages from, and a backend function had no way
// to reach it, so the only option was to copy the site's text into a second
// place and let it drift.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

String page(String route, String title, String body) => jsonEncode(
      <String, Object?>{'route': route, 'title': title, 'description': '', 'html': body},
    );

/// Chrome every page carries: a header, a nav and a footer.
const String chrome = '<a href="/">Home</a>\n<a href="/docs">Docs</a>\n';
const String footer = '<a href="https://github.com/x">GitHub</a>\n'
    '<p>Licensed. Built with Dartvel.</p>';

String manifest() => '''
{
  "siteUrl": "https://example.com",
  "routes": {
    "/": {"title": "Example home", "text": [], "page": ${page('/', 'Example home', '$chrome<h1>Build apps</h1>\n<p>Welcome to the example.</p>\n$footer')}},
    "/docs/deploy": {"title": "Deploy an app", "text": [], "page": ${page('/docs/deploy', 'Deploy an app', '$chrome<h1>Deploying</h1>\n<p>Copy one file to a server.</p>\n<h2>Choose a host</h2>\n<p>Any Linux server &amp; a port.</p>\n<h2>Roll back</h2>\n<p>Point current at the previous release.</p>\n$footer')}},
    "/docs/cache": {"title": "Cache", "text": [], "page": ${page('/docs/cache', 'Cache', '$chrome<h1>Cache</h1>\n<p>Get, set, has and delete.</p>\n$footer')}},
    "/post/:id": {"title": "Post", "text": []},
    "/404": {"title": null, "text": []},
    "/shop": {"location": "https://shop.example.com/"}
  }
}
''';

void main() {
  test('every titled page, with its sections, and none of the chrome', () {
    final List<DVSitePage> pages = DVSitePages.parse(manifest());

    expect(pages.map((DVSitePage p) => p.path),
        <String>['/', '/docs/deploy', '/docs/cache']);

    final DVSitePage deploy = pages[1];
    expect(deploy.title, 'Deploy an app');
    expect(deploy.sections.map((DVSitePageSection s) => s.heading),
        <String>['Deploying', 'Choose a host', 'Roll back']);
    expect(deploy.sections[1].text, 'Any Linux server & a port.');

    // The header and footer are on every page, so they are nobody's content:
    // a search for "GitHub" would otherwise match every page equally.
    final String all = pages
        .expand((DVSitePage p) => p.sections)
        .map((DVSitePageSection s) => '${s.heading} ${s.text}')
        .join(' ');
    expect(all, isNot(contains('GitHub')));
    expect(all, isNot(contains('Home')));
    expect(all, contains('Welcome to the example.'));
  });

  test('a parameterised route, an untitled one and a mounted site are not pages',
      () {
    final List<String> paths =
        DVSitePages.parse(manifest()).map((DVSitePage p) => p.path).toList();

    // "/post/:id" is a shape, not a page anybody can be sent to.
    expect(paths, isNot(contains('/post/:id')));
    expect(paths, isNot(contains('/404')));
    expect(paths, isNot(contains('/shop')));
  });

  test('a manifest that is not one reads as no pages, not an error', () {
    expect(DVSitePages.parse(''), isEmpty);
    expect(DVSitePages.parse('{"routes": 3}'), isEmpty);
  });

  test('load reads the manifest of the site this server serves', () async {
    final Directory web = Directory.systemTemp.createTempSync('dv_site_pages');
    addTearDown(() => web.deleteSync(recursive: true));
    File('${web.path}/dartvel_routes.json').writeAsStringSync(manifest());

    DVSitePages.webRoot = web.path;
    addTearDown(() => DVSitePages.webRoot = null);

    expect((await DVSitePages.load()).map((DVSitePage p) => p.path),
        contains('/docs/cache'));
  });

  test('a server with no built site has no pages', () async {
    DVSitePages.webRoot = null;
    expect(await DVSitePages.load(), isEmpty);
  });
}
