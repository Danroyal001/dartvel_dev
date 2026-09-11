/// The service worker and the offline page.
///
/// Dartvel wrote a manifest and linked it, and shipped Flutter's own service
/// worker unmodified -- which caches the app shell and nothing Dartvel knows
/// about. So a Dartvel site had no offline page, no cached routes, and no
/// control over what a stale worker serves after a deploy.
library dartvel_cli.build.pwa_service_worker;

import 'dart:convert';
import 'dart:io';

/// The worker source for a build.
///
/// [buildId] is part of the cache name, so a deploy opens a new cache and
/// deletes the old one. Without that a deploy reuses the previous cache and
/// serves the old bundle.
String dvServiceWorker({
  required String buildId,
  required List<String> precache,
  String? offlinePath,
  bool backgroundSync = true,
}) {
  final List<String> assets = <String>[
    ...precache,
    // Precached rather than fetched on demand, because fetching it on demand
    // is exactly what fails when there is no network.
    if (offlinePath != null && !precache.contains(offlinePath)) offlinePath,
  ];

  return _template
      .replaceAll('__BUILD_ID__', buildId)
      .replaceAll('__PRECACHE__', jsonEncode(assets))
      .replaceAll('__OFFLINE__',
          offlinePath == null ? 'null' : jsonEncode(offlinePath))
      // Stripped rather than switched off at runtime, so a worker with sync
      // disabled carries no outbox code at all and nothing can register the
      // tag by accident.
      .replaceAll('__OUTBOX__', backgroundSync ? _outbox : '')
      .replaceAll('__QUEUE_ON_FAILURE__',
          backgroundSync ? _queueOnFailure : _noQueue);
}

/// What a non-GET does when the network refuses it.
const String _queueOnFailure = r'''
  // Not a GET: nothing to cache, but something to keep. A backend function
  // call made while the network is gone is queued and replayed on sync,
  // instead of failing and leaving the user to retry by hand or not.
  if (request.method !== 'GET') {
    event.respondWith(fetch(request.clone()).catch((error) => queueForSync(request).then(() =>
      new Response(JSON.stringify({ queued: true }), {
        status: 202,
        headers: { 'Content-Type': 'application/json', 'X-Dartvel-Queued': '1' },
      })
    )));
    return;
  }
''';

const String _noQueue = r'''
  // A cached POST is a form submission served from disk, and the Cache API
  // throws on one anyway.
  if (request.method !== 'GET') return;
''';

/// The outbox: same-origin requests that are not GETs and could not be sent,
/// kept in IndexedDB because a worker is killed between events and an
/// in-memory queue would lose every request the moment the browser reclaimed
/// it. Replayed in order on `sync`, stopping at the first failure: out of
/// order, an update replays before the create it depends on, and continuing
/// past a failure drops that request while sending the ones after it.
const String _outbox = r'''
const OUTBOX = 'dartvel-outbox';

function openOutbox() {
  return new Promise((resolve, reject) => {
    const open = indexedDB.open(OUTBOX, 1);
    open.onupgradeneeded = () => open.result.createObjectStore('requests', { autoIncrement: true });
    open.onsuccess = () => resolve(open.result);
    open.onerror = () => reject(open.error);
  });
}

function withStore(mode, fn) {
  return openOutbox().then((db) => new Promise((resolve, reject) => {
    const tx = db.transaction('requests', mode);
    const result = fn(tx.objectStore('requests'));
    tx.oncomplete = () => resolve(result);
    tx.onerror = () => reject(tx.error);
  }));
}

function queueForSync(request) {
  const url = new URL(request.url);
  // The same two rules the caching path applies, for the same reasons: a GET
  // is safe to retry through the cache, and a request to another origin is
  // one the worker cannot inspect or vouch for.
  if (request.method === 'GET' || url.origin !== self.location.origin) {
    return Promise.reject(new Error('not queueable'));
  }
  return request.clone().arrayBuffer().then((body) => withStore('readwrite', (store) => {
    store.add({
      url: request.url,
      method: request.method,
      headers: Array.from(request.headers.entries()),
      body: body,
      queuedAt: Date.now(),
    });
  })).then(() => {
    if (self.registration && self.registration.sync) {
      return self.registration.sync.register(OUTBOX).catch(() => undefined);
    }
  });
}

// One replay at a time. A sync event and the client's replay message can
// arrive together when the network returns, and two replays reading the
// outbox before either has deleted from it send every request twice.
let replaying = null;

function replayOutbox() {
  if (replaying) return replaying;
  replaying = replayOnce().finally(() => { replaying = null; });
  return replaying;
}

function replayOnce() {
  return withStore('readonly', (store) => {
    const entries = [];
    const keys = [];
    return new Promise((resolve) => {
      const cursor = store.openCursor();
      cursor.onsuccess = () => {
        const c = cursor.result;
        if (!c) return resolve({ entries, keys });
        entries.push(c.value); keys.push(c.key); c.continue();
      };
      cursor.onerror = () => resolve({ entries, keys });
    });
  }).then((p) => p).then(async ({ entries, keys }) => {
    let index = 0;
    for (const entry of entries) {
      const response = await fetch(entry.url, {
        method: entry.method,
        headers: entry.headers,
        body: entry.body.byteLength ? entry.body : undefined,
      }).catch(() => undefined);
      // Stop at the first failure and leave it, and everything after it, for
      // the next sync. Sending the later ones would reorder them.
      if (!response || !response.ok) return;
      const key = keys[index++];
      await withStore('readwrite', (store) => store.delete(key));
    }
  });
}

self.addEventListener('sync', (event) => {
  if (event.tag === OUTBOX) event.waitUntil(replayOutbox());
});

// A browser without the Background Sync API never fires the event, so the
// outbox is also replayed when the worker wakes for anything else and the
// network is back.
self.addEventListener('message', (event) => {
  if (event.data === 'dartvel:replay-outbox') event.waitUntil(replayOutbox());
});
''';

/// A CSS colour taken from project configuration, or the neutral default.
///
/// Both error pages carried #2f6bff, which is the colour of dartvel.dev. Every
/// application built with Dartvel shipped its error pages in the framework's
/// brand rather than its own -- on the two pages a visitor sees when something
/// has gone wrong, which is exactly when a page should look like the site it
/// belongs to.
///
/// Sanitised rather than interpolated. The value lands inside a `<style>`
/// block, so anything that is not a colour is a way to write CSS into every
/// error page a project ships, and a pubspec is not a place anybody reads
/// looking for that.
///
/// Black is the default because it is what the PWA manifest already defaults
/// its theme colour to; a project that declares nothing gets the same answer
/// from both.
String dvAccentColour(String? declared) {
  if (declared == null) return '#000000';
  final String value = declared.trim();
  return RegExp(r'^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(value)
      ? value
      : '#000000';
}

/// The page shown when a navigation fails and nothing is cached.
///
/// Self-contained: it is served when the network is gone, so it cannot
/// reference a stylesheet, a font or a script it would have to fetch.
String dvOfflinePage({required String title, String? accent}) {
  final String safe = const HtmlEscape().convert(title);
  final String brand = dvAccentColour(accent);
  return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Offline — $safe</title>
<style>
body{margin:0;min-height:100vh;display:flex;align-items:center;
justify-content:center;
font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
color:#0b1020;background:#fff}
main{max-width:28rem;padding:2rem;text-align:center}
h1{font-size:1.5rem;margin:0 0 .5rem}
p{margin:0 0 1.5rem;color:#5a6478}
button{font:inherit;padding:.7rem 1.4rem;border:0;border-radius:8px;
background:$brand;color:#fff;cursor:pointer}
@media (prefers-color-scheme:dark){
body{color:#f2f5fa;background:#0a0d13}
p{color:#9aa7bd}}
</style>
</head>
<body>
<main>
<h1>You are offline</h1>
<p>$safe could not be reached. This page is being served from your device.</p>
<button onclick="location.reload()">Try again</button>
</main>
</body>
</html>
''';
}

const String _template = r'''
// GENERATED by dartvel build web -- do not edit.
const CACHE = 'dartvel-__BUILD_ID__';
const PRECACHE = __PRECACHE__;
const OFFLINE = __OFFLINE__;

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(PRECACHE)).then(() =>
      // Takes over at once. Without it a new worker sits idle until every tab
      // is closed, so a fix ships and nobody receives it for days.
      self.skipWaiting()
    )
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) => Promise.all(
      // Every deploy would otherwise leave its cache behind until the origin
      // quota fills and the browser evicts all of it at once.
      names.filter((name) => name !== CACHE).map((name) => caches.delete(name))
    )).then(() => self.clients.claim())
  );
});

__OUTBOX__
self.addEventListener('fetch', (event) => {
  const request = event.request;

  // Fonts, analytics, an API on another host. An opaque response is something
  // the worker can neither inspect nor invalidate.
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

__QUEUE_ON_FAILURE__

  // Network first for documents. Cache-first on a navigation is the failure
  // that bricks a PWA: the worker serves an index.html naming bundles that no
  // longer exist, the app cannot boot, and the only way out is clearing site
  // data.
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then((response) => {
          if (response.ok) {
            const copy = response.clone();
            caches.open(CACHE).then((cache) => cache.put(request, copy));
          }
          return response;
        })
        .catch(() => caches.match(request).then(
          (cached) => cached || (OFFLINE ? caches.match(OFFLINE) : undefined)
        ))
    );
    return;
  }

  // Everything else is a hashed asset: cache first, and fill the cache on a
  // miss.
  event.respondWith(
    caches.match(request).then((cached) => cached || fetch(request).then((response) => {
      // Only a complete, successful response. Caching a 206 or a 404 pins it,
      // and the page then serves that error from disk on every later visit.
      if (response.ok && response.status === 200) {
        const copy = response.clone();
        caches.open(CACHE).then((cache) => cache.put(request, copy));
      }
      return response;
    }))
  );
});
''';

/// The routes a worker should precache, from the routes the build prerenders.
///
/// Taken from the route list rather than from scanning `build/web`, which is
/// how this was decided before: the worker was written ahead of the route
/// pages, so a clean build found nothing on disk and precached the root
/// alone. It looked correct only because a second build ran over the first
/// and the directories were still there from last time -- so CI, which always
/// builds clean, always shipped the broken artifact, and a developer, who
/// always builds twice, never saw it.
///
/// A template is not a page. Precaching the literal `/posts/:id` caches
/// whatever that address answers -- a 404 on any real server -- and then
/// serves it as the offline answer for every post.
/// Every deferred part dart2js wrote into [web], as the URLs a worker
/// precaches, in the order dart2js numbered them.
///
/// Precached because a page's code is in one of these, and a page nobody has
/// opened yet has never had its part fetched. The worker caches what passes
/// through it, which covered every page while they were all in main.dart.js;
/// once each is a part of its own, opening an unvisited page offline is a
/// load error unless the part was cached up front.
List<String> dvDeferredPartFiles(Directory web) {
  if (!web.existsSync()) return const <String>[];
  final RegExp part = RegExp(r'^main\.dart\.js_(\d+)\.part\.js$');
  final List<(int, String)> found = <(int, String)>[];
  for (final FileSystemEntity entity in web.listSync()) {
    if (entity is! File) continue;
    final String name = entity.uri.pathSegments.last;
    final RegExpMatch? m = part.firstMatch(name);
    if (m != null) found.add((int.parse(m.group(1)!), name));
  }
  // Numerically: _10 sorts before _2 as a string.
  found.sort(((int, String) a, (int, String) b) => a.$1.compareTo(b.$1));
  return <String>[for (final (int, String) f in found) '/${f.$2}'];
}

List<String> dvPrecacheRoutes(Iterable<String> routes) {
  final Set<String> precache = <String>{'/'};
  for (final String route in routes) {
    if (route.isEmpty) continue;
    // ':' is the parameterised segment; '*' is the catch-all.
    if (route.contains(':') || route.contains('*')) continue;
    precache.add(route.startsWith('/') ? route : '/$route');
  }
  return precache.toList();
}

/// The page a host serves when the path is not a page.
///
/// There was an offline page and no not-found page at all, so a request for a
/// route that does not exist got whatever the host happened to say: the host's
/// own branding on most static hosts, and on Apache the generated rewrite
/// quietly serving the application shell — which renders the router's
/// not-found route, and is right only when the visitor reached the site with
/// scripting on.
///
/// Self-contained for the same reason the offline page is: it is served at the
/// moment something else could not be, so a stylesheet, a font or a script
/// would be a blank page exactly when the page matters.
///
/// The link home is the whole point. A wrong URL with nothing on it is a dead
/// end, and the visitor's only move is the back button.
String dvNotFoundPage({
  required String title,
  String home = '/',
  String? accent,
}) {
  final String brand = dvAccentColour(accent);
  final HtmlEscape escape = const HtmlEscape();
  final String safe = escape.convert(title);
  // Attribute mode for the URL. The default escape turns every "/" into
  // &#47;, which browsers accept and nobody should have to read -- and the
  // link home is the one thing on this page somebody might inspect.
  final String safeHome =
      const HtmlEscape(HtmlEscapeMode.attribute).convert(home);
  return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Not found — $safe</title>
<style>
body{margin:0;min-height:100vh;display:flex;align-items:center;
justify-content:center;
font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
color:#0b1020;background:#fff}
main{max-width:28rem;padding:2rem;text-align:center}
h1{font-size:1.5rem;margin:0 0 .5rem}
p{margin:0 0 1.5rem;color:#5a6478}
a{display:inline-block;font:inherit;padding:.7rem 1.4rem;border-radius:8px;
background:$brand;color:#fff;text-decoration:none}
@media (prefers-color-scheme:dark){
body{color:#f2f5fa;background:#0a0d13}
p{color:#9aa7bd}}
</style>
</head>
<body>
<main>
<h1>Page not found</h1>
<p>That page is not part of $safe. It may have moved, or the link may be
wrong.</p>
<a href="$safeHome">Go to the home page</a>
</main>
</body>
</html>
''';
}
