// The two routes an app serves when the normal page cannot be shown.
//
// There was an offline page and no not-found page at all: a request for a
// route that does not exist got whatever the host happened to say, which on
// most static hosts is the host's own branding and on Apache was the
// generated rewrite quietly serving the application shell.
//
// They are routes now -- `/offline` and `/404`, declared by the generator and
// drawn by `dartvel_flutter` -- so what is left on this side of the build is
// what the build owes the rest of the world: a sitemap that does not
// advertise a page that only reports a problem, and a not-found document for
// the hosts that cannot be told to ask the application.
//
// Both at extensionless paths, because a URL a person can see should not
// carry a file extension, and these are URLs a person sees: one is what the
// browser shows when the network is gone and the other is what a mistyped
// link lands on.
import 'dart:io';

import 'package:dartvel_cli/src/build/server_config.dart';
import 'package:dartvel_cli/src/build/static_seo.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The addresses [xml] advertises, in order.
List<String> advertised(String xml) => RegExp(r'<loc>([^<]*)</loc>')
    .allMatches(xml)
    .map((RegExpMatch m) => m.group(1)!)
    .toList();

void main() {
  group('the sitemap', () {
    // A crawler is sent here to be told what a site is. Handing it two URLs
    // whose only content is that something went wrong spends a crawl on the
    // site and puts a page that says "not found" into a result list.
    test('never advertises a page that only reports a problem', () {
      final String xml = dvSitemap(
        routes: const <String>['/', '/404', '/offline'],
        siteUrl: 'https://app.test',
      );
      expect(advertised(xml), <String>['https://app.test']);
    });

    // The one thing that must not be swallowed: `/blog/404` is a page whose
    // slug happens to be 404, and a filter written as a substring would take
    // it out of the sitemap as well as out of the error handling.
    test('leaves a page whose own name is 404 alone', () {
      final String xml = dvSitemap(
        routes: const <String>['/', '/blog/404', '/404'],
        siteUrl: 'https://app.test',
      );
      expect(advertised(xml),
          <String>['https://app.test', 'https://app.test/blog/404']);
    });

    test('says so in no other way either', () {
      // Not listed as a URL, and not as a route with a priority and a change
      // frequency: the same page, spelled for a different reader.
      final String xml = dvSitemap(
        routes: const <String>['/offline'],
        siteUrl: 'https://app.test',
        defaults:
            const DVSitemapEntry(priority: 0.5, changeFrequency: 'weekly'),
      );
      expect(xml, isNot(contains('offline')));
    });
  });

  group('the not-found document a host serves', () {
    // GitHub Pages, Netlify and S3 website hosting each look for 404.html by
    // name and cannot be told otherwise, and a site with only
    // /404/index.html falls back to the host's own branding on the one page
    // where branding is the least useful thing it could show.
    late Directory web;
    late File rendered;

    setUp(() {
      web = Directory.systemTemp.createTempSync('dartvel-404');
      rendered = File(p.join(web.path, '404', 'index.html'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('<html lang="en"><body><h1>Page not found</h1>'
            '<a href="/">Go to the home page</a></body></html>');
    });
    tearDown(() => web.deleteSync(recursive: true));

    test('is the page the build rendered, not a document of its own', () {
      final File? document = dvHostNotFoundDocument(web);
      expect(document?.path, endsWith('404.html'));
      expect(document?.readAsStringSync(), equals(rendered.readAsStringSync()));
    });

    test('is rewritten on the next build, not left as it was', () {
      // build/web is not emptied between builds, so "written only when
      // absent" would keep serving the previous deploy's page for ever.
      expect(dvHostNotFoundDocument(web), isNotNull);
      rendered.writeAsStringSync('<html lang="en"><body>Second</body></html>');
      expect(dvHostNotFoundDocument(web)?.readAsStringSync(),
          contains('Second'));
      expect(File(p.join(web.path, '404.html')).existsSync(), isTrue);
    });

    test('is nothing at all when the build rendered no not-found page', () {
      // A build with no router has no page to point at, and a document
      // standing in for one is a page that lies about the site.
      web.deleteSync(recursive: true);
      web.createSync(recursive: true);
      expect(dvHostNotFoundDocument(web), isNull);
      expect(File(p.join(web.path, '404.html')).existsSync(), isFalse);
    });
  });

  group('the Apache configuration', () {
    // The rewrite sends unknown paths to the application shell, which is
    // right for a route the router knows and wrong for one nothing does. The
    // error document is what a host serves when the rewrite is not in play.
    test('names the not-found page at its extensionless path', () {
      expect(dvApacheConfig(), contains('ErrorDocument 404 /404/index.html'));
    });
  });
}
