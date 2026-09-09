// The two pages a site needs when the normal one cannot be shown.
//
// There was an offline page and no not-found page at all: a request for a
// route that does not exist got whatever the host happened to say, which on
// most static hosts is the host's own branding and on Apache was the
// generated rewrite quietly serving the application shell.
//
// Both live at extensionless paths -- /offline/ and /404/ -- because a URL a
// person can see should not carry a file extension, and these are URLs a
// person sees: one is what the browser shows when the network is gone and the
// other is what a mistyped link lands on.
import 'package:dartvel_cli/src/build/pwa_service_worker.dart';
import 'package:dartvel_cli/src/build/server_config.dart';
import 'package:test/test.dart';

/// Whether [html] can render with no network at all.
///
/// Both pages are served exactly when fetching something else failed, so a
/// stylesheet, a font or a script would be a blank page at the moment the
/// page matters most.
void expectSelfContained(String html) {
  expect(html, isNot(contains('<link rel="stylesheet"')));
  expect(html, isNot(contains('<script src=')));
  expect(html, isNot(contains('fonts.googleapis')));
  expect(html, isNot(contains('href="http')));
}

void main() {
  group('the not-found page', () {
    test('says what happened and names the site', () {
      final String html = dvNotFoundPage(title: 'Dartvel');
      expect(html, contains('Dartvel'));
      expect(html.toLowerCase(), contains('not found'));
    });

    test('offers the way back, since a wrong URL is a dead end without one',
        () {
      expect(dvNotFoundPage(title: 'Dartvel'), contains('href="/"'));
    });

    test('renders with no network', () {
      expectSelfContained(dvNotFoundPage(title: 'Dartvel'));
    });

    test('a title with markup in it cannot break out', () {
      final String html = dvNotFoundPage(title: '<script>alert(1)</script>');
      expect(html, isNot(contains('<script>alert(1)</script>')));
      expect(html, contains('&lt;script&gt;'));
    });
  });

  group('the offline page', () {
    test('renders with no network either', () {
      expectSelfContained(dvOfflinePage(title: 'Dartvel'));
    });
  });

  group('the worker', () {
    test('precaches the offline page at the path it is served from', () {
      final String worker = dvServiceWorker(
        buildId: 'b',
        precache: const <String>['/'],
        offlinePath: '/offline/',
      );
      expect(worker, contains('/offline/'));
      expect(worker, isNot(contains('/offline.html')));
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
