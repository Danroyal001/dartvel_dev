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

import 'package:crypto/crypto.dart' show sha256;
import 'package:dartvel_core/dartvel.dart' show dvOfflineRoute;

/// The service worker's build id: when this build was made.
///
/// `SOURCE_DATE_EPOCH` (whole seconds since 1970, the reproducible-builds.org
/// convention) replaces the clock, so two builds of the same sources are byte
/// for byte the same, the server binary that embeds the worker included.
/// Without it the id is the current time and every build opens a new cache.
/// A value that is not a whole, non-negative number of seconds is ignored.
String dvServiceWorkerBuildId({
  Map<String, String>? environment,
  DateTime Function()? now,
}) {
  final String? epoch =
      (environment ?? Platform.environment)['SOURCE_DATE_EPOCH']?.trim();
  if (epoch != null && RegExp(r'^\d+$').hasMatch(epoch)) {
    return DateTime.fromMillisecondsSinceEpoch(
      int.parse(epoch) * 1000,
      isUtc: true,
    ).toIso8601String();
  }
  return (now ?? DateTime.now)().toUtc().toIso8601String();
}

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
  bool push = false,
  String? adminPath,
  String? apiBasePath,
  String? engineRevision,
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
      .replaceAll('__BUILD_JSON__', jsonEncode(buildId))
      .replaceAll('__BUILD_ID__', buildId)
      .replaceAll('__ENGINE__', engineRevision == null ? 'null' : jsonEncode(engineRevision))
      .replaceAll('__PRECACHE__', jsonEncode(assets))
      .replaceAll('__OFFLINE__', offline == null ? 'null' : jsonEncode(offline))
      // Stripped rather than switched off at runtime, so a worker with sync
      // disabled carries no outbox code at all and nothing can register the
      // tag by accident.
      .replaceAll('__OUTBOX__', backgroundSync ? _outbox : '')
      .replaceAll('__PUSH__', push ? _pushHandlers : '')
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


/// Web Push in the worker: showing what the server sent, and what a click on
/// it does. Present only when the project declares `dartvel.push.web`, so a
/// site that never sends a push ships no notification code.
const String _pushHandlers = r'''
// Web Push (RFC 8030). The payload is the JSON WebPushProvider encrypts:
// {title, body, data}. A push that shows nothing counts against the site, so
// every path below ends in a notification unless a window can show it.
self.addEventListener('push', (event) => {
  let payload = {};
  if (event.data) {
    try {
      payload = event.data.json();
    } catch (_) {
      payload = { title: '', body: event.data.text() };
    }
  }
  if (!payload || typeof payload !== 'object') payload = {};

  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) client.postMessage({ type: 'dartvel-push', payload });
    // A visible window draws the message itself; Chrome allows a push to show
    // nothing only then.
    if (windows.some((client) => client.visibilityState === 'visible')) return;
    await self.registration.showNotification(payload.title || '', {
      body: payload.body || '',
      data: payload.data || {},
      icon: typeof payload.icon === 'string' ? payload.icon : undefined,
      tag: typeof payload.tag === 'string' ? payload.tag : undefined,
    });
  })());
});

// Only a page of this origin: the url is data a server wrote, and a click is
// not the place to leave the site.
function sameOriginTarget(raw) {
  try {
    const target = new URL(typeof raw === 'string' ? raw : '/', self.location.origin);
    return target.origin === self.location.origin ? target : new URL('/', self.location.origin);
  } catch (_) {
    return new URL('/', self.location.origin);
  }
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const target = sameOriginTarget(data.url);
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    if (windows.length > 0) {
      const client = windows[0];
      await client.focus();
      client.postMessage({
        type: 'dartvel-push-open',
        title: event.notification.title,
        body: event.notification.body,
        url: target.pathname + target.search,
        data,
      });
      return;
    }
    await self.clients.openWindow(target.href);
  })());
});
''';

const String _template = r'''
// GENERATED by dartvel build web -- do not edit.
const BUILD = __BUILD_JSON__;
const CACHE = 'dartvel-__BUILD_ID__';
// Files whose URL names their version (Google's renderer and fallback fonts):
// kept across releases, because the same URL is the same bytes forever.
const RUNTIME = 'dartvel-runtime';
// Which build each open page is running, kept where a restarted worker finds it.
const META = 'dartvel-meta';
const PRECACHE = __PRECACHE__;
// The app's own offline route, as the URL it is served from. Studio's mount
// and the API base path. Studio is its own application with its own session,
// and an API answer is data, not an asset: neither belongs in a cache that
// only a deploy empties.
const ADMIN = __ADMIN__;
const API = __API__;
const OFFLINE = __OFFLINE__;
// The engine whose renderer this build loads, when it comes from gstatic.
const ENGINE = __ENGINE__;
// The files a page asks for with ?v=<build>: what tells the worker which
// build a page is running.
const BOOT = ['flutter_bootstrap.js', 'main.dart.js', 'main.dart.mjs', 'main.dart.wasm'];
const SCOPE = new URL((self.registration && self.registration.scope) || (self.location.origin + '/'));
// Every file of this build by content hash, written by the build next to the
// worker; a release copies the unchanged ones from the cache it replaces.
const ASSETS = 'dartvel_sw_assets.json';
const ASSETS_KEY = SCOPE.href + '__dartvel-sw/assets';
const CLIENTS_KEY = SCOPE.href + '__dartvel-sw/clients';

// A path with nothing behind it, so the trailing slash that says "directory
// index" cannot make two spellings of one page.
function bare(path) {
  const trimmed = path.replace(/\/+$/, '');
  return trimmed === '' ? '/' : trimmed;
}

// The URL relative to the worker's scope, or null outside it.
function relative(url) {
  const href = url.href.split('#')[0];
  return href.startsWith(SCOPE.href) ? href.slice(SCOPE.href.length) : null;
}

function bootName(url) {
  const rel = relative(url);
  if (rel === null) return null;
  const path = rel.split('?')[0];
  return BOOT.includes(path) ? path : null;
}

// What a request is kept under: a boot file without its ?v=, so one entry
// serves every page of this build; anything else as it is.
function cacheKey(url) {
  if (!bootName(url)) return url.href;
  const key = new URL(url.href);
  key.searchParams.delete('v');
  return key.href;
}

// Google's CDN, where the URL carries the version: the renderer under its
// engine revision, the fallback fonts under theirs.
function versionedElsewhere(url) {
  return (url.hostname === 'www.gstatic.com' && url.pathname.startsWith('/flutter-canvaskit/')) ||
    (url.hostname === 'fonts.gstatic.com' && url.pathname.startsWith('/s/'));
}

// Whether an asset may be kept. Only a complete, successful one: caching a
// 206 or a 404 pins it, and the page then serves that error from disk on
// every later visit. And never one the server said not to keep -- Studio's
// code, which the server hands only to a session with the Studio grant, or
// anything marked private -- or the next person on this browser is served it
// with nothing asked.
function storable(response) {
  return response.ok && response.status === 200 && response.type !== 'opaque' &&
    !/no-store|private/i.test(response.headers.get('cache-control') || '');
}

const clientBuilds = new Map();
let clientsRead = null;
function readClients() {
  if (!clientsRead) {
    clientsRead = caches.open(META)
      .then((cache) => cache.match(CLIENTS_KEY))
      .then((response) => (response ? response.json() : {}))
      .then((saved) => {
        for (const id of Object.keys(saved)) if (!clientBuilds.has(id)) clientBuilds.set(id, saved[id]);
      })
      .catch(() => undefined);
  }
  return clientsRead;
}
function writeClients() {
  // Every page load is a new client; the oldest are long closed.
  while (clientBuilds.size > 100) clientBuilds.delete(clientBuilds.keys().next().value);
  const body = JSON.stringify(Object.fromEntries(clientBuilds));
  return caches.open(META)
    .then((cache) => cache.put(CLIENTS_KEY, new Response(body, { headers: { 'content-type': 'application/json' } })))
    .catch(() => undefined);
}

self.addEventListener('install', (event) => {
  event.waitUntil(install().then(() =>
    // Takes over at once. Without it a new worker sits idle until every tab
    // is closed, so a fix ships and nobody receives it for days.
    self.skipWaiting()
  ));
});

async function install() {
  const cache = await caches.open(CACHE);
  const assets = await fetch(new Request(new URL(ASSETS + '?v=' + encodeURIComponent(BUILD), SCOPE).href, { cache: 'no-cache' }))
    .then((response) => (response.ok ? response.json() : {}))
    .catch(() => ({}));
  await cache.put(ASSETS_KEY, new Response(JSON.stringify(assets), { headers: { 'content-type': 'application/json' } }));
  await reuse(cache, assets);
  // One file at a time and none of them fatal. With cache.addAll one 404 or
  // one dropped connection failed the whole install, and the worker it was
  // replacing went on serving the previous build -- to everybody, until
  // each of them cleared site data.
  await Promise.all(PRECACHE.map(async (path) => {
    const url = new URL(path, self.location.origin).href;
    if (await cache.match(url)) return;
    // A boot file is asked for at ?v=<build>, the URL the page itself used a
    // moment ago, so the HTTP cache answers rather than the network: as plain
    // main.dart.js it was another cache key and downloaded twice.
    const asked = new URL(url);
    if (bootName(asked)) asked.searchParams.set('v', BUILD);
    try {
      // no-cache: revalidated, so a copy the HTTP cache kept from the last
      // build is never filed under this one.
      const response = await fetch(new Request(asked.href, { cache: 'no-cache' }));
      if (response.ok && response.status === 200) await cache.put(url, response);
    } catch (_) {
      // Fetched when first asked for instead.
    }
  }));
}

// The files a release did not change, copied from the cache it replaces
// instead of downloaded again: the renderer, the fonts, the pictures, every
// part nobody touched.
async function reuse(cache, assets) {
  const names = (await caches.keys()).filter((name) =>
    name.startsWith('dartvel-') && name !== CACHE && name !== RUNTIME && name !== META);
  for (const name of names) {
    const old = await caches.open(name);
    const before = await old.match(ASSETS_KEY).then((r) => (r ? r.json() : null)).catch(() => null);
    if (!before) continue;
    for (const request of await old.keys()) {
      const rel = relative(new URL(request.url));
      if (rel === null || rel.includes('?')) continue;
      const hash = assets[rel];
      if (!hash || before[rel] !== hash) continue;
      if (await cache.match(request.url)) continue;
      const response = await old.match(request.url);
      if (response) await cache.put(request.url, response);
    }
  }
}

self.addEventListener('activate', (event) => {
  event.waitUntil(activate().then(() => self.clients.claim()));
});

async function activate() {
  await readClients();
  const open = new Set((await self.clients.matchAll({ type: 'window', includeUncontrolled: true })
    .catch(() => [])).map((client) => client.id));
  for (const id of [...clientBuilds.keys()]) if (!open.has(id)) clientBuilds.delete(id);
  await writeClients();
  // A build some open page still runs keeps its cache: that page's code asks
  // for its own parts, and another build's would not load into it.
  const live = new Set([...clientBuilds.values()].map((build) => 'dartvel-' + build));
  const names = await caches.keys();
  // Every other build's cache, and Flutter's own worker's: each would
  // otherwise stay until the origin quota fills and the browser evicts all of
  // it at once.
  await Promise.all(names.filter((name) =>
    (name.startsWith('dartvel-') && name !== CACHE && name !== RUNTIME && name !== META && !live.has(name)) ||
    name.startsWith('flutter-')
  ).map((name) => caches.delete(name)));
  if (ENGINE) {
    const runtime = await caches.open(RUNTIME);
    for (const request of await runtime.keys()) {
      const match = /\/flutter-canvaskit\/([^/]+)\//.exec(new URL(request.url).pathname);
      if (match && match[1] !== ENGINE) await runtime.delete(request);
    }
  }
}

__OUTBOX__
__PUSH__
// The page reporting what it downloaded before this worker controlled it:
// the first visit, which nothing intercepted. Each one is kept, read from the
// browser's own HTTP cache rather than the network, so the second visit is
// served from here. Only from a page of this build -- a page loaded before a
// deploy holds the previous build's files.
self.addEventListener('message', (event) => {
  const data = event.data;
  if (!data || data.type !== 'dartvel:warm' || data.build !== BUILD || !Array.isArray(data.urls)) return;
  const work = (async () => {
    const cache = await caches.open(CACHE);
    const runtime = await caches.open(RUNTIME);
    for (const raw of data.urls.slice(0, 2000)) {
      let url;
      try { url = new URL(raw); } catch (_) { continue; }
      const own = url.origin === self.location.origin;
      if (!own && !versionedElsewhere(url)) continue;
      if (own && ((ADMIN && (url.pathname === ADMIN || url.pathname.startsWith(ADMIN + '/'))) ||
          (API && (url.pathname === API || url.pathname.startsWith(API + '/'))))) continue;
      const target = own ? cache : runtime;
      const key = own ? cacheKey(url) : url.href;
      if (await target.match(key)) continue;
      try {
        const response = await fetch(url.href, { cache: 'force-cache', mode: own ? 'same-origin' : 'cors' });
        if (storable(response)) await target.put(key, response);
      } catch (_) {
        // Fetched when first asked for instead.
      }
    }
  })();
  if (event.waitUntil) event.waitUntil(work);
});

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

// One download per file however many requests ask for it at once: the
// engine fetches the same font for two families, and both would otherwise
// miss the cache together.
const inFlight = new Map();
function fill(cache, request, key) {
  let pending = inFlight.get(key);
  if (!pending) {
    pending = fetch(request).then((response) => {
      if (storable(response)) cache.put(key, response.clone()).catch(() => undefined);
      return response;
    });
    pending.then(() => inFlight.delete(key), () => inFlight.delete(key));
    inFlight.set(key, pending);
  }
  return pending.then((response) => response.clone());
}

// This build's copy, else the network, kept on the way through.
function fromBuild(request, key) {
  return caches.open(CACHE).then((cache) =>
    cache.match(key).then((cached) => cached || fill(cache, request, key)));
}

// Google's renderer and fonts, kept by their versioned URL.
function fromRuntime(request) {
  return caches.open(RUNTIME).then((cache) =>
    cache.match(request.url).then((cached) => cached || fill(cache, request, request.url)));
}

// A request from a page: answered from the files of the build that page is
// running. A page tells the worker its build by asking for its boot files
// with ?v=<build>; everything else it asks for afterwards comes from the same
// build. A page of a newer build than this worker's -- the HTML came from the
// network, after a deploy this worker predates -- is answered from the
// network, never from this cache, and the worker asks to be replaced. That
// pairing, fresh HTML with the cached main.dart.js and parts of the build
// before, is what kept a released app running its previous build.
async function answer(event, request, url) {
  await readClients();
  const client = event.clientId || event.resultingClientId || '';
  const asked = bootName(url) ? url.searchParams.get('v') : null;
  if (asked && client && clientBuilds.get(client) !== asked) {
    clientBuilds.set(client, asked);
    writeClients();
  }
  const build = asked || (client && clientBuilds.get(client)) || BUILD;
  const key = cacheKey(url);
  if (build === BUILD) return fromBuild(request, key);
  const theirs = 'dartvel-' + build;
  if (await caches.has(theirs)) {
    // An open tab of an earlier build, after a release: its own files.
    const hit = await caches.open(theirs).then((cache) => cache.match(key));
    if (hit) return hit;
    return fetch(request);
  }
  if (self.registration && self.registration.update) self.registration.update().catch(() => undefined);
  return fetch(request).catch(() => fromBuild(request, key));
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (ADMIN && (url.pathname === ADMIN || url.pathname.startsWith(ADMIN + "/"))) return;

  // Analytics, an API on another host: a response the worker can neither
  // inspect nor invalidate. Google's renderer and fonts are the exception,
  // because their URL is their version.
  if (url.origin !== self.location.origin) {
    if (request.method === 'GET' && versionedElsewhere(url)) event.respondWith(fromRuntime(request));
    return;
  }

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
          // Any document that loaded, whatever it says about caching: a
          // server renders every page no-store, and this copy is only what
          // is shown offline. Studio's pages never reach here.
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

  // Everything else is a file of some build: cache first, filled on a miss.
  event.respondWith(answer(event, request, url));
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
  // The wasm app's page modules, for the same reason: a Chromium visitor
  // runs main.dart.wasm and never fetches a part.
  final RegExp module = RegExp(r'^main\.dart_module(\d+)\.wasm$');
  final List<(int, String)> modules = <(int, String)>[];
  for (final FileSystemEntity entity in web.listSync()) {
    if (entity is! File) continue;
    final String name = entity.uri.pathSegments.last;
    final RegExpMatch? m = module.firstMatch(name);
    if (m != null) modules.add((int.parse(m.group(1)!), name));
  }
  modules.sort(((int, String) a, (int, String) b) => a.$1.compareTo(b.$1));
  return <String>[
    for (final (int, String) f in found) '/${f.$2}',
    for (final (int, String) f in modules) '/${f.$2}',
  ];
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


/// Marks the registration script in `flutter_bootstrap.js`, so a second build
/// finds it instead of appending another.
const String dvServiceWorkerRegistrationMarker =
    '/* dartvel: service worker registration */';

/// [bootstrap] (Flutter's `flutter_bootstrap.js`) that also registers the
/// worker the build wrote.
///
/// Flutter's own bootstrap registers `flutter_service_worker.js` on a first
/// visit only in releases before 3.47; from there it updates a registration
/// that already exists and never makes one (the unconditional path is the
/// deprecated `serviceWorkerUrl` setting). So a Dartvel site relied on the
/// loader for a registration the loader no longer makes, and its worker -- the
/// offline page, the replayed writes, push -- was written, shipped and never
/// installed.
///
/// It registers the URL the loader would, `?v=` and all, so the two do not
/// take turns replacing each other's script; and it waits for `load`, so the
/// registration never competes with the app's first frame.
///
/// With [build], once the worker is active the page also tells it what the
/// page downloaded (`performance` resource entries) and which build it is:
/// the first visit happened before any worker controlled the page, so none
/// of it passed through one, and the worker keeps it from the HTTP cache for
/// the next visit. Said again fifteen seconds on, for what loaded late.
String dvBootstrapRegisteringServiceWorker(String bootstrap, {String? build}) {
  if (bootstrap.contains(dvServiceWorkerRegistrationMarker)) return bootstrap;
  final String? version =
      RegExp(r'serviceWorkerVersion:\s*"([^"]+)"').firstMatch(bootstrap)?.group(1);
  final String url = version == null
      ? 'flutter_service_worker.js'
      : 'flutter_service_worker.js?v=$version';
  final String separator = bootstrap.endsWith('\n') ? '' : '\n';
  final String warm = build == null
      ? ''
      : 'const w=()=>navigator.serviceWorker.ready.then((r)=>{if(r.active)'
          'r.active.postMessage({type:"dartvel:warm",build:${jsonEncode(build)},'
          'urls:performance.getEntriesByType("resource").map((e)=>e.name)});})'
          '.catch(()=>{});w();setTimeout(w,15000);';
  // After the load event AND the app's first frame (or thirty seconds after
  // load, for a page whose app never draws): the worker's install downloads
  // the page parts, and on a slow connection that download would otherwise
  // share the line with the renderer the first frame is waiting for.
  return '$bootstrap$separator$dvServiceWorkerRegistrationMarker\n'
      '(()=>{if(!("serviceWorker"in navigator))return;'
      'let f=false,l=false,d=false;'
      'const go=()=>{if(d||!f||!l)return;d=true;'
      'navigator.serviceWorker.register(new URL("$url",document.baseURI).href)'
      '.catch(()=>{});$warm};'
      'addEventListener("flutter-first-frame",()=>{f=true;go();},{once:true});'
      'addEventListener("load",()=>{l=true;setTimeout(()=>{f=true;go();},30000);go();});'
      '})();\n';
}

/// What a page needs before its first frame, as the URLs a worker precaches:
/// the loader, the app's code (dart2js or wasm, whichever this build wrote),
/// the manifests the engine reads first, and every font FontManifest.json
/// lists -- the engine waits for all of them before it draws.
///
/// The renderer is not here: which CanvasKit or skwasm file a browser loads
/// is decided in the browser, and two of them would be megabytes for nothing.
/// The page reports the one it used (the warm message) and the worker keeps
/// that.
List<String> dvServiceWorkerBootFiles(Directory web) {
  final List<String> out = <String>[
    for (final String name in const <String>[
      'flutter_bootstrap.js',
      'flutter.js',
      'main.dart.js',
      'main.dart.mjs',
      'main.dart.wasm',
      'manifest.json',
      'assets/FontManifest.json',
      'assets/AssetManifest.bin.json',
      'assets/AssetManifest.bin',
    ])
      if (File('${web.path}/$name').existsSync()) '/$name',
  ];
  final File fonts = File('${web.path}/assets/FontManifest.json');
  if (fonts.existsSync()) {
    try {
      final Object? manifest = jsonDecode(fonts.readAsStringSync());
      if (manifest is List) {
        for (final Object? family in manifest) {
          final Object? list = family is Map ? family['fonts'] : null;
          if (list is! List) continue;
          for (final Object? font in list) {
            final Object? asset = font is Map ? font['asset'] : null;
            final String url = '/assets/$asset';
            if (asset is String && !out.contains(url)) out.add(url);
          }
        }
      }
    } on FormatException {
      // A manifest the engine cannot read either: nothing to precache.
    }
  }
  return out;
}

/// Every file of the build in [web] by a hash of its bytes, keyed by its path
/// under the web root: what `dartvel_sw_assets.json` holds, so a new worker
/// copies what a release did not change from the cache it replaces instead
/// of downloading it again.
///
/// Pages are left out (they are fetched network-first), and so are the
/// worker itself, symbols and source maps.
Map<String, String> dvServiceWorkerAssets(Directory web) {
  final Map<String, String> out = <String, String>{};
  if (!web.existsSync()) return out;
  final String root = web.absolute.path;
  for (final FileSystemEntity entity in web.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final String rel = entity.absolute.path
        .substring(root.length + 1)
        .replaceAll(r'\', '/');
    final String name = rel.split('/').last;
    if (name.endsWith('.html') ||
        name.endsWith('.htm') ||
        name.endsWith('.symbols') ||
        name.endsWith('.map') ||
        name == 'flutter_service_worker.js' ||
        name == dvServiceWorkerAssetsFile ||
        name.startsWith('.')) {
      continue;
    }
    out[rel] = sha256.convert(entity.readAsBytesSync()).toString().substring(0, 16);
  }
  return out;
}

/// How many of [routes] a worker precaches on the first visit:
/// `dartvel.pwa.precacheRoutes`, a number, or `true`/`'all'` for every one;
/// 25 when nothing is declared. The home page is always first.
///
/// Precaching every route is a download the reader pays for on their first
/// visit, for pages they may never open -- 1.5 MB for sigmadev.digital's 221
/// -- while a page they do open is kept as they open it.
List<String> dvPrecacheRouteBudget(List<String> routes, Object? declared) {
  final List<String> ordered = <String>[
    if (routes.contains('/')) '/',
    for (final String route in routes)
      if (route != '/') route,
  ];
  if (declared == true || declared == 'all') return ordered;
  final int budget = declared is num && declared >= 0 ? declared.toInt() : 25;
  return ordered.take(budget < 1 ? 1 : budget).toList();
}

/// The file [dvServiceWorkerAssets] is written to, beside the worker.
const String dvServiceWorkerAssetsFile = 'dartvel_sw_assets.json';

/// [html] asking for `flutter_bootstrap.js?v=<build>`.
///
/// The page is the one file always fetched fresh (network first, and
/// `no-cache` from every Dartvel server), so the build it names is the build
/// the server is on now. The worker reads it from the `?v=` to tell which
/// build the page is running.
///
/// A preload of the app's code (`main.dart.js`, `.mjs`, `.wasm`) is
/// versioned the same way, or it and the loader's request would be two
/// downloads of the largest file on the page. Deferred parts are not: the
/// compiled app asks for them by their plain name.
String dvVersionIndexHtml(String html, String build) => html.replaceAllMapped(
      RegExp(r'''((?:src|href)=["'](?:\./)?)(flutter_bootstrap\.js|main\.dart\.(?:js|mjs|wasm))(?:\?v=[^"']*)?(["'])'''),
      (Match m) => '${m[1]}${m[2]}?v=${Uri.encodeQueryComponent(build)}${m[3]}',
    );

/// [bootstrap] (`flutter_bootstrap.js`) asking for the app's code at
/// `?v=<build>`: `mainJsPath` for dart2js, `mainWasmPath` and
/// `jsSupportRuntimePath` for dart2wasm, in every build `_flutter.buildConfig`
/// lists. Which renderer and which build the loader picks is untouched.
///
/// A bootstrap with no `_flutter.buildConfig` the build can read is
/// returned as it is.
String dvVersionBootstrap(String bootstrap, String build) {
  final RegExpMatch? config =
      RegExp(r'_flutter\.buildConfig\s*=\s*(\{[^\n]*\})\s*;').firstMatch(bootstrap);
  if (config == null) return bootstrap;
  final Object? json;
  try {
    json = jsonDecode(config.group(1)!);
  } on FormatException {
    return bootstrap;
  }
  if (json is! Map || json['builds'] is! List) return bootstrap;
  final String version = Uri.encodeQueryComponent(build);
  String versioned(String path) => '${path.split('?').first}?v=$version';
  for (final Object? entry in json['builds'] as List<Object?>) {
    if (entry is! Map || entry.isEmpty) continue;
    if (entry['compileTarget'] == 'dart2js') {
      entry['mainJsPath'] = versioned('${entry['mainJsPath'] ?? 'main.dart.js'}');
    }
    for (final String key in const <String>['mainWasmPath', 'jsSupportRuntimePath']) {
      if (entry[key] is String) entry[key] = versioned(entry[key]! as String);
    }
  }
  return bootstrap.replaceRange(
      config.start, config.end, '_flutter.buildConfig = ${jsonEncode(json)};');
}
