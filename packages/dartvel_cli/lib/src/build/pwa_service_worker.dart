/// The service worker.
///
/// Dartvel wrote a manifest and linked it, and shipped Flutter's own service
/// worker unmodified -- which caches the app shell and nothing Dartvel knows
/// about. So a Dartvel site had no offline page, no cached routes, and no
/// control over what a stale worker serves after a deploy.
///
/// The page a failed navigation lands on is not here. It used to be: two
/// documents of markup and inline CSS written by the build, styled in
/// Dartvel's brand, and served from the cache for as long as the cache lived.
/// It is a route of the application now -- `DVOfflinePage` in
/// `dartvel_flutter`, declared by the generator and prerendered by the build
/// -- so the worker redirects to it and carries the path that was being
/// opened.
library dartvel_cli.build.pwa_service_worker;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show dvOfflineRoute;

/// The worker source for a build.
///
/// [buildId] is part of the cache name, so a deploy opens a new cache and
/// deletes the old one. Without that a deploy reuses the previous cache and
/// serves the old bundle.
///
/// [offlineRoute] is where a navigation that could not be completed is sent.
/// It is a route of the application rather than a document this build wrote,
/// which is why the answer is a redirect and not a page: the offline page
/// has a theme, a heading a crawler can read and a "Try again" that goes
/// where the person was going. [offlineRoute] is null for a project whose
/// router says nothing is at that path, and then a failed navigation gets no
/// answer at all rather than a wrong one.
String dvServiceWorker({
  required String buildId,
  required List<String> precache,
  String? offlineRoute = dvOfflineRoute,
  bool backgroundSync = true,
  String? adminPath,
  String? apiBasePath,
}) {
  // The URL the page is served from, rather than the route: a static host
  // answers it as a directory index and a server answers it as the route, and
  // both are this one address. The trailing slash is what a person sees
  // after a host has redirected them, and what the cache has to hold.
  final String? offline = offlineRoute == null ? null : '$offlineRoute/';
  final List<String> assets = <String>[
    ...precache,
    // Precached rather than fetched on demand, because fetching it on demand
    // is exactly what fails when there is no network.
    if (offline != null && !precache.contains(offline)) offline,
  ];

  return _template
      .replaceAll('__ADMIN__', _pathOrNull(adminPath))
      .replaceAll('__API__', _pathOrNull(apiBasePath))
      .replaceAll('__BUILD_ID__', buildId)
      .replaceAll('__PRECACHE__', jsonEncode(assets))
      .replaceAll('__OFFLINE__', offline == null ? 'null' : jsonEncode(offline))
      // Stripped rather than switched off at runtime, so a worker with sync
      // disabled carries no outbox code at all and nothing can register the
      // tag by accident.
      .replaceAll('__OUTBOX__', backgroundSync ? _outbox : '')
      .replaceAll('__QUEUE_ON_FAILURE__',
          backgroundSync ? _queueOnFailure : _noQueue);
}

/// A path as a JS string literal, without a trailing slash, or `null`.
String _pathOrNull(String? path) {
  if (path == null) return 'null';
  String value = path.trim();
  while (value.length > 1 && value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value.isEmpty || value == '/' ? 'null' : jsonEncode(value);
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

const String _template = r'''
// GENERATED by dartvel build web -- do not edit.
const CACHE = 'dartvel-__BUILD_ID__';
const PRECACHE = __PRECACHE__;
// The app's own offline route, as the URL it is served from. Studio's mount
// and the API base path. Studio is its own application with its own session,
// and an API answer is data, not an asset: neither belongs in a cache that
// only a deploy empties.
const ADMIN = __ADMIN__;
const API = __API__;
const OFFLINE = __OFFLINE__;

// A path with nothing behind it, so the trailing slash that says "directory
// index" cannot make two spellings of one page.
function bare(path) {
  const trimmed = path.replace(/\/+$/, '');
  return trimmed === '' ? '/' : trimmed;
}

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
// Where a navigation that could not be completed goes.
//
// A redirect, not a document: the offline page is a route of this
// application, drawn by the same widgets as every other page, and a redirect
// is what lets the app render it. It carries the path the person was opening
// as `from`, so the page's "Try again" goes back to where they were rather
// than to the home page, and that path is encoded rather than pasted -- a
// `from` is read by the app and written by whoever crafted the link.
//
// Never the offline page itself: a failure while that page is being fetched
// would send the person to the page they are already on, and the browser
// would follow it as often as it cared to. Answered from the cache instead,
// which is the one version of it that exists offline.
function offline(url) {
  if (!OFFLINE) return undefined;
  if (bare(url.pathname) === bare(OFFLINE)) return caches.match(OFFLINE);
  const target = new URL(OFFLINE + '?from=' + encodeURIComponent(url.pathname), self.location.origin);
  return Response.redirect(target.href, 302);
}

self.addEventListener('fetch', (event) => {
  const request = event.request;

  // Fonts, analytics, an API on another host. An opaque response is something
  // the worker can neither inspect nor invalidate.
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  if (ADMIN && (url.pathname === ADMIN || url.pathname.startsWith(ADMIN + "/"))) return;

__QUEUE_ON_FAILURE__

  // A GET to the API is an answer that changes; the browser fetches it.
  if (API && request.method === "GET" && (url.pathname === API || url.pathname.startsWith(API + "/"))) return;

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
        .catch(() => caches.match(request).then((cached) => cached || offline(url)))
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

