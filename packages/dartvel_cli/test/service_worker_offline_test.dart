// What the worker does when a navigation cannot be completed.
//
// The offline page is a route of the application now, not a document the
// build wrote, so a navigation that fails is answered with a redirect to
// that route. Four ways that can go wrong are all silent: a redirect to
// itself when the offline page is the thing that could not be fetched, a
// `from` that does not survive the trip so "Try again" goes somewhere nobody
// asked for, a page that is already cached being replaced by the offline
// one, and a working network being answered from a cache.
//
// The worker is JavaScript and this is a Dart test, so the source is run
// under node with the handful of globals a service worker is handed, and the
// answers are read back out of it. Asserting that the emitted text contains
// `Response.redirect` would pass just as well on a worker that redirects to
// nowhere, which is the failure this exists to catch.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/pwa_service_worker.dart';
import 'package:test/test.dart';

/// The routes a project with these prerendered would give its worker.
const List<String> _routes = <String>['/', '/articles', '/offline'];

/// A page nobody has opened, so nothing about it is in the cache. This is
/// the ordinary case for a failed navigation: a link from somewhere else,
/// a person who has not been here before.
const String _uncached = '/pricing';

void main() {
  // A worker is only ever run by a browser; there is nothing to run it with
  // here, and the skip is said out loud rather than passing quietly.
  if (_node() == null) {
    test('the generated worker runs', () {},
        skip: 'node is not on PATH, so the generated worker cannot be run');
    return;
  }

  group('a navigation that cannot be completed', () {
    test('goes to the offline route, carrying where it was going', () async {
      final Map<String, Object?> answer = await _runWorker(_uncached);
      expect(answer['status'], 302);
      expect(answer['location'],
          'https://app.test/offline/?from=%2Fpricing');
    });

    test('names the path, and not the query behind it', () async {
      // The path is the person's own place in the site and is safe to send
      // back. A query is the server's answer to it, and can carry a token in
      // a redirect the person did not write.
      final Map<String, Object?> answer =
          await _runWorker('/search?q=hello%20world');
      expect(answer['location'], contains('from=%2Fsearch'));
      expect(answer['location'], isNot(contains('world')));
    });

    test('does not offer a page the build wrote by hand', () async {
      // A redirect, not a document: a cached copy of a hand-written page is
      // the thing this removed, and once it is in the cache it is served
      // from disk for as long as the cache lives. So the answer to a failed
      // navigation now carries no markup at all.
      final Map<String, Object?> answer = await _runWorker(_uncached);
      expect(answer['status'], 302);
      expect(answer['body'], isNot(contains('<')));
    });

    test('serves a page that is already cached, rather than the offline one',
        () async {
      // Offline is not the answer to everything: a page read once is still
      // worth showing, and it is the only version of it anybody has.
      final Map<String, Object?> answer = await _runWorker('/articles');
      expect(answer['status'], 200);
      expect(answer['body'], contains('served: https://app.test/articles'));
      expect(answer['location'], isNull);
    });
  });

  group('the offline page itself', () {
    test('is precached, or it cannot be served when it is needed', () async {
      // The one page that has to be in the cache before there is a reason to
      // want it: fetching it on demand is exactly what fails.
      final List<Object?> cached = await _precached();
      expect(cached, contains('https://app.test/offline/'));
    });

    test('is never redirected to itself', () async {
      // A failure while the offline page is being fetched would otherwise
      // send the person to the page they are already on, and the browser
      // would follow it as often as it cared to.
      //
      // Asked for without the trailing slash, and with a project that
      // prerendered nothing else: that is the one request that misses the
      // cache first and reaches the redirect, which is where the guard is.
      for (final String path in <String>['/offline', '/offline/']) {
        final Map<String, Object?> answer = await _runWorker(path,
            routes: const <String>['/']);
        expect(answer['status'], 200, reason: path);
        expect(answer['location'], isNull, reason: path);
        expect(answer['body'], contains('served: https://app.test/offline/'),
            reason: path);
      }
    });
  });

  group('nothing changed for a working network', () {
    test('a navigation that succeeds is passed straight through', () async {
      final Map<String, Object?> answer =
          await _runWorker('/articles', networkUp: true);
      expect(answer['status'], 200);
      expect(answer['body'], contains('served: https://app.test/articles'));
      expect(answer['location'], isNull);
    });
  });
}

/// The worker this project would ship, having prerendered [routes].
String _worker({List<String> routes = _routes}) =>
    dvServiceWorker(buildId: 'b', precache: dvPrecacheRoutes(routes));

/// One navigation through the worker, with the network down unless a test
/// says otherwise: a build that answers a working network from the cache is
/// the failure this is checking has not arrived.
Future<Map<String, Object?>> _runWorker(
  String path, {
  List<String>? routes,
  bool networkUp = false,
}) =>
    _fire(_worker(routes: routes ?? _routes), <String, Object?>{
      'path': path,
      'networkUp': networkUp,
    });

Future<List<Object?>> _precached() async {
  final Map<String, Object?> answer = await _fire(
      _worker(), <String, Object?>{'precache': true});
  return answer['cached']! as List<Object?>;
}

/// Runs the worker source under node with a worker's globals, and returns
/// what it answered.
Future<Map<String, Object?>> _fire(
  String worker,
  Map<String, Object?> scenario,
) async {
  final Directory dir = Directory.systemTemp.createTempSync('dartvel-worker');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File script = File('${dir.path}/worker.mjs')
    ..writeAsStringSync('$_shim\n$worker\n$_driver\n'
        '__run(${jsonEncode(scenario)}).then((answer) => {'
        ' console.log(JSON.stringify(answer)); });');

  final ProcessResult result =
      Process.runSync(_node()!, <String>[script.path]);
  if (result.exitCode != 0) {
    fail('the generated worker did not run:\n${result.stderr}');
  }
  return (jsonDecode(result.stdout as String) as Map<Object?, Object?>)
      .cast<String, Object?>();
}

String? _node() {
  for (final String candidate in const <String>['node', 'nodejs']) {
    if (Process.runSync(candidate, const <String>['--version']).exitCode == 0) {
      return candidate;
    }
  }
  return null;
}

/// The globals a service worker is handed, and nothing else.
///
/// A cache keyed by the absolute URL, because that is what the Cache API
/// matches on: a page precached as the string `/offline/` and looked up as
/// `https://app.test/offline/` are one entry, and a harness that keyed them
/// differently would pass a worker that never finds its own page.
const String _shim = r'''
const listeners = {};
const stores = new Map();
let networkUp = true;

function keyOf(request) {
  const url = typeof request === 'string' ? request : request.url;
  return new URL(url, self.location.origin).href;
}

function cacheFor(name) {
  if (!stores.has(name)) stores.set(name, new Map());
  const store = stores.get(name);
  const cache = {
    add: async (url) => { store.set(keyOf(url), await globalThis.fetch(url)); },
    put: async (request, response) => { store.set(keyOf(request), response); },
    match: async (request) => store.get(keyOf(request)),
    delete: async (request) => store.delete(keyOf(request)),
  };
  cache.addAll = async (urls) => { for (const url of urls) await cache.add(url); };
  return cache;
}

globalThis.self = {
  location: { origin: 'https://app.test' },
  addEventListener: (type, handler) => { listeners[type] = handler; },
  skipWaiting: () => Promise.resolve(),
  clients: { claim: () => Promise.resolve() },
};

globalThis.caches = {
  open: async (name) => cacheFor(name),
  keys: async () => [...stores.keys()],
  delete: async (name) => stores.delete(name),
  match: async (request) => {
    for (const store of stores.values()) {
      const hit = store.get(keyOf(request));
      if (hit) return hit;
    }
    return undefined;
  },
};

// The network the worker is given, not the one it has: a test says which
// requests are refused, and the worker never learns which.
globalThis.fetch = (request) => {
  const url = keyOf(request);
  if (!networkUp) return Promise.reject(new TypeError('Failed to fetch'));
  return Promise.resolve(new Response('served: ' + url, { status: 200 }));
};
''';

/// Runs one event through the worker and reads the answer back.
const String _driver = r'''
function request(url, mode) {
  const target = new URL(url, self.location.origin);
  return { url: target.href, method: 'GET', mode, headers: [], clone() { return this; } };
}

async function fire(type, event) {
  const handler = listeners[type];
  if (!handler) return undefined;
  let answered;
  const waited = [];
  handler(Object.assign({}, event, {
    waitUntil: (promise) => waited.push(promise),
    respondWith: (promise) => { answered = promise; },
  }));
  await Promise.all(waited);
  return answered === undefined ? undefined : await answered;
}

globalThis.__run = async (scenario) => {
  await fire('install', {});
  const cached = [...stores.values()].flatMap((store) => [...store.keys()]);
  if (scenario.precache) return { cached };

  networkUp = scenario.networkUp;
  const response =
      await fire('fetch', { request: request(scenario.path, 'navigate') });
  if (!response) return { status: null, location: null, body: null };
  return {
    status: response.status,
    location: response.headers.get('location'),
    body: await response.text(),
  };
};
''';
