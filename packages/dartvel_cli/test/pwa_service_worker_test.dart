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
//
// What the worker does with a navigation it cannot complete is run for real,
// under node, in service_worker_offline_test.dart; what is here is the shape
// of its answer.
import 'dart:convert';
import 'dart:io';

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

/// Node, to run the worker in, or null where there is none.
String? _node() {
  final ProcessResult which = Process.runSync(
      Platform.isWindows ? 'where' : 'which', <String>['node']);
  return which.exitCode == 0 ? '${which.stdout}'.trim().split('\n').first : null;
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

    test('it never keeps a response the server said not to store', () async {
      // Studio's code is served from the site root to a session with the
      // Studio grant, marked no-store. A worker that kept it would hand it
      // to the next person on that browser with no grant asked; a document
      // or an answer marked private or no-store is the same.
      final String? node = _node();
      if (node == null) {
        markTestSkipped('no node to run the worker in');
        return;
      }
      final String worker =
          dvServiceWorker(buildId: 'abc', precache: const <String>['/']);
      final Directory dir = Directory.systemTemp.createTempSync('dv_sw_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File harness = File('${dir.path}/harness.mjs')
        ..writeAsStringSync('''
const handlers = {};
const puts = [];
globalThis.self = {
  location: { origin: 'https://shop.example' },
  addEventListener: (name, fn) => { handlers[name] = fn; },
  skipWaiting: () => Promise.resolve(),
  clients: { claim: () => Promise.resolve() },
};
globalThis.caches = {
  open: async () => ({ put: async (req) => { puts.push(new URL(req.url).pathname); }, addAll: async () => {} }),
  match: async () => undefined,
  keys: async () => [],
};
const answers = {
  '/main.dart.js_7.part.js': 'no-store',
  '/secret.js': 'private, max-age=60',
  '/main.dart.js': 'public, max-age=60',
  '/logo.png': null,
};
globalThis.fetch = async (req) => {
  const path = new URL(req.url).pathname;
  const headers = new Headers();
  if (answers[path]) headers.set('cache-control', answers[path]);
  return new Response('x', { status: 200, headers });
};
$worker
for (const path of Object.keys(answers)) {
  const request = new Request('https://shop.example' + path);
  let responded;
  handlers.fetch({ request, respondWith: (p) => { responded = p; }, waitUntil: () => {} });
  await responded;
}
await new Promise((r) => setTimeout(r, 20));
console.log(JSON.stringify(puts.sort()));
''');
      final ProcessResult run = await Process.run(node, <String>[harness.path]);
      expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
      expect(jsonDecode('${run.stdout}'.trim()),
          <String>['/logo.png', '/main.dart.js']);
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
    // What the worker does with a navigation it cannot complete is run for
    // real, under node, in service_worker_offline_test.dart. What is left here
    // is the shape of the worker's answer: which route it is sent to, and
    // that nothing it serves is a document the build wrote.
    test('a navigation that fails is sent to the offline route', () {
      final String worker =
          dvServiceWorker(buildId: 'abc', precache: const <String>['/']);
      expect(worker, contains('const OFFLINE = "/offline/"'));
      expect(worker, contains('Response.redirect'));
    });

    test('the offline page is precached, or it cannot be served offline', () {
      // The one page that must be in the cache before it is needed. Fetching
      // it on demand is exactly what fails when there is no network.
      final String worker =
          dvServiceWorker(buildId: 'abc', precache: const <String>['/']);
      expect(precacheOf(worker), contains('/offline/'));
    });

    test('a project whose router has no offline route gets no answer', () {
      // Rather than a page that claims to be one: an address nothing serves
      // is a 404 the person can see, which is true, and a document the build
      // made up about a site that has no such page is not.
      final String worker = dvServiceWorker(
        buildId: 'abc',
        precache: const <String>['/'],
        offlineRoute: null,
      );
      expect(worker, contains('const OFFLINE = null'));
      expect(precacheOf(worker), isNot(contains('/offline/')));
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

  group('what it leaves to the browser', () {
    // A site worker registered at / controls Studio too. It cached Studio's
    // API answers cache-first, so a record edited in Studio showed its old
    // value until the next deploy, and a /__studio/api request answered
    // with the site shell while signed out was served from the cache after
    // signing in. Studio and the API are not assets.
    String worker() => dvServiceWorker(
          buildId: 'b',
          precache: const <String>['/'],
          adminPath: '/__studio',
          apiBasePath: '/api',
        );

    test('every request under the Studio mount, before anything else', () {
      final String w = worker();
      final int guard = w.indexOf('const ADMIN = "/__studio";');
      final int check = w.indexOf('if (ADMIN && (url.pathname === ADMIN || url.pathname.startsWith(ADMIN + "/"))) return;');
      expect(guard, greaterThan(-1));
      expect(check, greaterThan(-1));
      expect(check, lessThan(w.indexOf('event.respondWith')),
          reason: 'a Studio request, even a POST, never reaches the outbox or the cache');
    });

    test('GETs to the API, which are answers and not assets', () {
      final String w = worker();
      final int check = w.indexOf('if (API && request.method === "GET" && (url.pathname === API || url.pathname.startsWith(API + "/"))) return;');
      expect(check, greaterThan(-1));
      expect(check, lessThan(w.indexOf('caches.match(request).then((cached) => cached ||')));
    });

    test('nothing, when there is no mount and no API', () {
      final String w = dvServiceWorker(buildId: 'b', precache: const <String>[]);
      expect(w, contains('const ADMIN = null;'));
      expect(w, contains('const API = null;'));
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
