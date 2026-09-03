// The service worker, which is what makes a PWA a PWA.
//
// Dartvel wrote a manifest and linked it, and shipped Flutter's own service
// worker unmodified -- which caches the app shell and nothing Dartvel knows
// about. So a Dartvel site had no offline page, no cached routes, and no
// control over what a stale worker serves after a deploy.
//
// The rules under test are the ones that make a service worker actively
// harmful when they are wrong. A worker that caches index.html forever serves
// last week's bundle references and the app fails to boot, with no way for the
// user to fix it except clearing site data.
import 'dart:convert';

import 'package:dartvel_cli/src/build/pwa_service_worker.dart';
import 'package:test/test.dart';

/// The precache list the worker will actually use.
///
/// Parsed out rather than grepped for, so the assertions are about what is
/// precached and not about how the array happens to be quoted.
List<String> precacheOf(String worker) {
  final RegExpMatch match =
      RegExp(r'const PRECACHE = (\[[^\]]*\]);').firstMatch(worker)!;
  return (jsonDecode(match.group(1)!) as List<Object?>).cast<String>();
}

void main() {
  group('what it precaches', () {
    test('the routes the build produced', () {
      final String worker = dvServiceWorker(
        buildId: 'abc123',
        precache: const <String>['/', '/docs', '/features'],
      );

      expect(precacheOf(worker), containsAll(<String>['/', '/docs', '/features']));
    });

    test('the cache name carries the build id', () {
      // Without it a deploy reuses the previous cache and serves the old
      // bundle. With it the new worker opens a new cache and the old one is
      // deleted on activate.
      expect(dvServiceWorker(buildId: 'abc123', precache: const <String>['/']),
          contains('abc123'));
    });

    test('a different build is a different cache', () {
      final String first =
          dvServiceWorker(buildId: 'one', precache: const <String>['/']);
      final String second =
          dvServiceWorker(buildId: 'two', precache: const <String>['/']);
      expect(first, isNot(second));
    });

    test('old caches are deleted on activate', () {
      // Otherwise every deploy leaves its cache behind and the origin's
      // storage quota fills until the browser evicts all of it at once.
      final String worker =
          dvServiceWorker(buildId: 'abc', precache: const <String>['/']);
      expect(worker, contains('activate'));
      expect(worker, contains('caches.delete'));
    });
  });

  group('what it must not do', () {
    test('it never caches a non-GET request', () {
      // A cached POST is a form submission served from disk. The Cache API
      // throws on one, so a worker that tries also breaks the request.
      final String worker =
          dvServiceWorker(buildId: 'abc', precache: const <String>['/']);
      expect(worker, contains("method !== 'GET'"));
    });

    test('it never caches a partial or error response', () {
      // Caching a 206 or a 404 pins it: the page then serves that error from
      // disk on every later visit.
      final String worker =
          dvServiceWorker(buildId: 'abc', precache: const <String>['/']);
      expect(worker, contains('response.ok'));
    });

    test('it goes to the network first for navigations', () {
      // Cache-first on a document is the failure that bricks a PWA: the
      // worker serves an index.html naming bundles that no longer exist and
      // the app cannot boot, with no user-visible way out.
      final String worker =
          dvServiceWorker(buildId: 'abc', precache: const <String>['/']);
      expect(worker, contains("request.mode === 'navigate'"));
    });

    test('a cross-origin request is left alone', () {
      // Fonts, analytics, an API on another host. Caching an opaque response
      // stores something the worker cannot inspect and cannot invalidate.
      final String worker =
          dvServiceWorker(buildId: 'abc', precache: const <String>['/']);
      expect(worker, contains('self.location.origin'));
    });
  });

  group('offline', () {
    test('a navigation that fails falls back to the offline page', () {
      final String worker = dvServiceWorker(
        buildId: 'abc',
        precache: const <String>['/'],
        offlinePath: '/offline.html',
      );
      expect(worker, contains('/offline.html'));
    });

    test('the offline page is precached, or it cannot be served offline', () {
      // The one asset that must be in the cache before it is needed. Fetching
      // it on demand is exactly what fails when there is no network.
      final String worker = dvServiceWorker(
        buildId: 'abc',
        precache: const <String>['/'],
        offlinePath: '/offline.html',
      );
      expect(precacheOf(worker), contains('/offline.html'));
    });
  });

  group('updating', () {
    test('it can be told to take over at once', () {
      // Without skipWaiting a new worker sits idle until every tab is closed,
      // so a fix ships and nobody receives it for days.
      final String worker =
          dvServiceWorker(buildId: 'abc', precache: const <String>['/']);
      expect(worker, contains('skipWaiting'));
      expect(worker, contains('clients.claim'));
    });
  });

  group('the offline page', () {
    test('it stands alone', () {
      // It is shown when the network is gone, so it cannot reference a
      // stylesheet, a font or a script it would have to fetch.
      final String page = dvOfflinePage(title: 'Dartvel');
      expect(page, isNot(contains('<link rel="stylesheet"')));
      expect(page, isNot(contains('<script src=')));
      expect(page, contains('<style'));
    });

    test('it names the site', () {
      expect(dvOfflinePage(title: 'Dartvel'), contains('Dartvel'));
    });

    test('it carries a viewport, like every other page', () {
      expect(dvOfflinePage(title: 'Dartvel'), contains('width=device-width'));
    });

    test('it follows the reader colour scheme', () {
      expect(dvOfflinePage(title: 'Dartvel'), contains('prefers-color-scheme'));
    });
  });

  test('one replay at a time: a sync event and the replay message arriving together send once', () {
    // Found in Chrome on CI: both arrived when the network came back, both
    // read the outbox before either had deleted from it, and the server got
    // every request twice. The browser suite holds the behaviour; this holds
    // the guard in the source it generates.
    final String worker = dvServiceWorker(buildId: 'b', precache: const <String>[], backgroundSync: true);
    expect(worker, contains('if (replaying) return replaying;'));
    expect(worker, contains("replaying = replayOnce().finally(() => { replaying = null; });"));
  });
}
