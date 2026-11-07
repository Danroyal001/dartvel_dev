// What the service worker does across a release.
//
// The Authenticator app shipped a release and its users kept running the
// previous build: sign-in failed until each of them found a hard reload. Two
// ways a worker produces exactly that, both silent:
//
// * the new worker's install fails -- one precached URL answers 404 or the
//   network drops it, `cache.addAll` rejects, and the old worker keeps
//   serving its cache-first copy of the old build for as long as it lives;
// * the first visit after a deploy pairs fresh HTML with the old worker's
//   cached main.dart.js, flutter_bootstrap.js and deferred parts, because
//   Flutter names them the same in every build.
//
// And a slow phone pays for every byte a worker throws away: a release that
// changed one page must not download the 1.5 MB renderer and every font
// again.
//
// The worker is run under node with the globals a browser hands it, as in
// service_worker_offline_test.dart, and every assertion is about what it
// answered and what it fetched -- never about the words in its source.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/pwa_service_worker.dart';
import 'package:test/test.dart';

void main() {
  if (_node() == null) {
    test('the generated worker runs', () {},
        skip: 'node is not on PATH, so the generated worker cannot be run');
    return;
  }

  group('a page of another build', () {
    test('is never handed this build\'s files, and the worker updates itself', () async {
      // The HTML came from the network and is build B; this worker is A.
      final Map<String, Object?> out = await _scenario(<String, Object?>{
        'steps': <Object?>[
          <String, Object?>{'do': 'install', 'build': 'A'},
          <String, Object?>{'do': 'activate', 'build': 'A'},
          <String, Object?>{'do': 'network', 'build': 'B'},
          <String, Object?>{'do': 'fetch', 'build': 'A', 'path': '/flutter_bootstrap.js?v=B', 'client': 'tab'},
          <String, Object?>{'do': 'fetch', 'build': 'A', 'path': '/main.dart.js?v=B', 'client': 'tab'},
          <String, Object?>{'do': 'fetch', 'build': 'A', 'path': '/main.dart.js_1.part.js', 'client': 'tab'},
        ],
      });
      expect(out['answers'], <String>[
        'B:/flutter_bootstrap.js',
        'B:/main.dart.js',
        'B:/main.dart.js_1.part.js',
      ]);
      expect(out['updates'], greaterThan(0));
    });

    test('of this build is served from the cache with no network at all', () async {
      final Map<String, Object?> out = await _scenario(<String, Object?>{
        'steps': <Object?>[
          <String, Object?>{'do': 'install', 'build': 'A'},
          <String, Object?>{'do': 'activate', 'build': 'A'},
          <String, Object?>{'do': 'offline'},
          <String, Object?>{'do': 'fetch', 'build': 'A', 'path': '/flutter_bootstrap.js?v=A', 'client': 'tab'},
          <String, Object?>{'do': 'fetch', 'build': 'A', 'path': '/main.dart.js?v=A', 'client': 'tab'},
          <String, Object?>{'do': 'fetch', 'build': 'A', 'path': '/main.dart.js_1.part.js', 'client': 'tab'},
        ],
      });
      expect(out['answers'], <String>[
        'A:/flutter_bootstrap.js',
        'A:/main.dart.js',
        'A:/main.dart.js_1.part.js',
      ]);
    });
  });

  group('installing', () {
    test('a file that cannot be fetched does not stop the install', () async {
      // With cache.addAll, one 404 and the new worker never installed: the
      // old one served the old build until someone cleared site data.
      final Map<String, Object?> out = await _scenario(<String, Object?>{
        'precache': <String>['/', '/main.dart.js', '/gone.js'],
        'missing': <String>['/gone.js'],
        'steps': <Object?>[
          <String, Object?>{'do': 'install', 'build': 'A'},
        ],
      });
      expect(out['installed'], isTrue);
      expect(out['skipWaiting'], isTrue);
      expect(out['cached'], contains('https://app.test/main.dart.js'));
      expect(out['cached'], isNot(contains('https://app.test/gone.js')));
    });

    test('a release fetches only what changed', () async {
      // canvaskit.wasm and the font are the same bytes in both builds; only
      // main.dart.js changed. The renderer came into the cache at run time
      // (it is not precached), and still survives the release.
      final Map<String, Object?> out = await _scenario(<String, Object?>{
        'precache': <String>['/main.dart.js', '/assets/f.0123456789abcdef.woff2'],
        'assets': <String, Object?>{
          'A': <String, String>{
            'main.dart.js': 'h1',
            'canvaskit/canvaskit.wasm': 'ck',
            'assets/f.0123456789abcdef.woff2': 'font',
          },
          'B': <String, String>{
            'main.dart.js': 'h2',
            'canvaskit/canvaskit.wasm': 'ck',
            'assets/f.0123456789abcdef.woff2': 'font',
          },
        },
        'steps': <Object?>[
          <String, Object?>{'do': 'install', 'build': 'A'},
          <String, Object?>{'do': 'activate', 'build': 'A'},
          <String, Object?>{'do': 'fetch', 'build': 'A', 'path': '/canvaskit/canvaskit.wasm', 'client': 'tab'},
          <String, Object?>{'do': 'closeAll'},
          <String, Object?>{'do': 'network', 'build': 'B'},
          <String, Object?>{'do': 'resetFetches'},
          <String, Object?>{'do': 'install', 'build': 'B'},
          <String, Object?>{'do': 'activate', 'build': 'B'},
          <String, Object?>{'do': 'offline'},
          <String, Object?>{'do': 'fetch', 'build': 'B', 'path': '/canvaskit/canvaskit.wasm', 'client': 'next'},
          <String, Object?>{'do': 'fetch', 'build': 'B', 'path': '/main.dart.js', 'client': 'next'},
        ],
      });
      final List<Object?> fetched = out['fetched']! as List<Object?>;
      expect(fetched, contains('/main.dart.js'));
      expect(fetched, isNot(contains('/canvaskit/canvaskit.wasm')));
      expect(fetched, isNot(contains('/assets/f.0123456789abcdef.woff2')));
      expect(out['answers'], <String>[
        'A:/canvaskit/canvaskit.wasm', // build A, filling its cache
        'A:/canvaskit/canvaskit.wasm', // build B, offline: the same bytes, never fetched
        'B:/main.dart.js',
      ]);
      // Build A's cache is gone once nothing of it is open.
      expect(out['caches'], isNot(contains('dartvel-A')));
    });
  });

  group('an open tab of the previous build', () {
    test('keeps being served its own files after a release', () async {
      // A tab running build A opens a page it has not opened before, after B
      // took over. B's part would not load into A's main.dart.js.
      final Map<String, Object?> out = await _scenario(<String, Object?>{
        'steps': <Object?>[
          <String, Object?>{'do': 'install', 'build': 'A'},
          <String, Object?>{'do': 'activate', 'build': 'A'},
          <String, Object?>{'do': 'fetch', 'build': 'A', 'path': '/flutter_bootstrap.js?v=A', 'client': 'old-tab'},
          <String, Object?>{'do': 'network', 'build': 'B'},
          <String, Object?>{'do': 'install', 'build': 'B'},
          <String, Object?>{'do': 'activate', 'build': 'B'},
          <String, Object?>{'do': 'fetch', 'build': 'B', 'path': '/main.dart.js_1.part.js', 'client': 'old-tab'},
          <String, Object?>{'do': 'fetch', 'build': 'B', 'path': '/main.dart.js_1.part.js', 'client': 'new-tab'},
        ],
      });
      expect(out['answers'], <String>[
        'A:/flutter_bootstrap.js',
        'A:/main.dart.js_1.part.js', // the old tab, after B took over
        'B:/main.dart.js_1.part.js', // a tab opened after the release
      ]);
      expect(out['caches'], contains('dartvel-A'));
    });
  });

  group('the renderer and fonts from Google\'s CDN', () {
    test('are kept by their versioned URL, across releases and offline', () async {
      const String canvaskit =
          'https://www.gstatic.com/flutter-canvaskit/abc123/chromium/canvaskit.wasm';
      const String noto = 'https://fonts.gstatic.com/s/notocoloremoji/v32/x.0.woff2';
      final Map<String, Object?> out = await _scenario(<String, Object?>{
        'steps': <Object?>[
          <String, Object?>{'do': 'install', 'build': 'A'},
          <String, Object?>{'do': 'activate', 'build': 'A'},
          <String, Object?>{'do': 'fetch', 'build': 'A', 'path': canvaskit, 'client': 'tab'},
          <String, Object?>{'do': 'fetch', 'build': 'A', 'path': noto, 'client': 'tab'},
          <String, Object?>{'do': 'closeAll'},
          <String, Object?>{'do': 'network', 'build': 'B'},
          <String, Object?>{'do': 'install', 'build': 'B'},
          <String, Object?>{'do': 'activate', 'build': 'B'},
          <String, Object?>{'do': 'offline'},
          <String, Object?>{'do': 'fetch', 'build': 'B', 'path': canvaskit, 'client': 'tab2'},
          <String, Object?>{'do': 'fetch', 'build': 'B', 'path': noto, 'client': 'tab2'},
        ],
      });
      final List<Object?> answers = out['answers']! as List<Object?>;
      expect(answers.sublist(2), <String>['A:$canvaskit', 'A:$noto']);
    });

    test('another cross-origin request is left to the browser', () async {
      final Map<String, Object?> out = await _scenario(<String, Object?>{
        'steps': <Object?>[
          <String, Object?>{'do': 'install', 'build': 'A'},
          <String, Object?>{'do': 'fetch', 'build': 'A', 'path': 'https://analytics.example/x.js', 'client': 'tab'},
        ],
      });
      expect(out['answers'], <String?>[null]);
    });
  });

  group('what the first visit already downloaded', () {
    test('is kept when the page reports it, from the browser\'s own cache', () async {
      // The first visit happens before any worker controls the page, so none
      // of it passed through one. The page lists what it loaded; the worker
      // keeps it, asking the HTTP cache rather than the network.
      final Map<String, Object?> out = await _scenario(<String, Object?>{
        'steps': <Object?>[
          <String, Object?>{'do': 'install', 'build': 'A'},
          <String, Object?>{'do': 'activate', 'build': 'A'},
          <String, Object?>{
            'do': 'warm',
            'build': 'A',
            'from': 'A',
            'urls': <String>[
              'https://app.test/canvaskit/canvaskit.wasm',
              'https://app.test/pictures/home-390.png',
              'https://app.test/api/me',
              'https://elsewhere.example/a.js',
            ],
          },
          <String, Object?>{'do': 'offline'},
          <String, Object?>{'do': 'fetch', 'build': 'A', 'path': '/pictures/home-390.png', 'client': 'tab'},
        ],
      });
      expect(out['answers'], <String>['A:/pictures/home-390.png']);
      expect(out['forceCache'], containsAll(<String>['/canvaskit/canvaskit.wasm', '/pictures/home-390.png']));
      expect(out['cached'], isNot(contains('https://app.test/api/me')));
    });

    test('is ignored when the page is of another build', () async {
      final Map<String, Object?> out = await _scenario(<String, Object?>{
        'steps': <Object?>[
          <String, Object?>{'do': 'install', 'build': 'A'},
          <String, Object?>{'do': 'activate', 'build': 'A'},
          <String, Object?>{
            'do': 'warm',
            'build': 'A',
            'from': 'Z',
            'urls': <String>['https://app.test/pictures/home-390.png'],
          },
        ],
      });
      expect(out['cached'], isNot(contains('https://app.test/pictures/home-390.png')));
    });
  });

  group('what the build tells the worker', () {
    late Directory web;
    setUp(() {
      web = Directory.systemTemp.createTempSync('dv_sw_files_');
      void write(String path, String body) => File('${web.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(body);
      write('index.html', '<html></html>');
      write('flutter_bootstrap.js', 'boot');
      write('flutter.js', 'loader');
      write('main.dart.js', 'app');
      write('main.dart.js_1.part.js', 'part');
      write('main.dart.js.symbols', 'symbols');
      write('flutter_service_worker.js', 'worker');
      write('manifest.json', '{}');
      write('canvaskit/canvaskit.wasm', 'ck');
      write('assets/FontManifest.json',
          '[{"family":"Inter","fonts":[{"asset":"dartvel/fonts/Inter.0123456789abcdef.woff2"}]}]');
      write('assets/dartvel/fonts/Inter.0123456789abcdef.woff2', 'font');
      write('assets/AssetManifest.bin.json', '""');
      write('about/index.html', '<html></html>');
    });
    tearDown(() => web.deleteSync(recursive: true));

    test('the boot set: loader, app, manifests and every font the page loads', () {
      expect(dvServiceWorkerBootFiles(web), unorderedEquals(<String>[
        '/flutter_bootstrap.js',
        '/flutter.js',
        '/main.dart.js',
        '/manifest.json',
        '/assets/FontManifest.json',
        '/assets/AssetManifest.bin.json',
        '/assets/dartvel/fonts/Inter.0123456789abcdef.woff2',
      ]));
    });

    test('every file by content hash, except pages, symbols and the worker', () {
      final Map<String, String> assets = dvServiceWorkerAssets(web);
      expect(assets.keys, unorderedEquals(<String>[
        'flutter_bootstrap.js',
        'flutter.js',
        'main.dart.js',
        'main.dart.js_1.part.js',
        'manifest.json',
        'canvaskit/canvaskit.wasm',
        'assets/FontManifest.json',
        'assets/dartvel/fonts/Inter.0123456789abcdef.woff2',
        'assets/AssetManifest.bin.json',
      ]));
      expect(assets['main.dart.js'], matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(assets['main.dart.js'], isNot(assets['flutter.js']));
      File('${web.path}/main.dart.js').writeAsStringSync('app, changed');
      expect(dvServiceWorkerAssets(web)['main.dart.js'], isNot(assets['main.dart.js']));
      expect(dvServiceWorkerAssets(web)['flutter.js'], assets['flutter.js']);
    });
  });

  group('the boot files carry the build', () {
    test('index.html asks for flutter_bootstrap.js at this build', () {
      expect(
          dvVersionIndexHtml('<script src="flutter_bootstrap.js" async></script>', 'b7'),
          '<script src="flutter_bootstrap.js?v=b7" async></script>');
      // Rebuilt over its own output: one version, the new one.
      expect(
          dvVersionIndexHtml('<script src="flutter_bootstrap.js?v=b6" async></script>', 'b7'),
          '<script src="flutter_bootstrap.js?v=b7" async></script>');
    });

    test('the bootstrap asks for the app at this build, dart2js and wasm alike', () {
      const String bootstrap = '_flutter.buildConfig = {"engineRevision":"e","builds":['
          '{"compileTarget":"dart2wasm","renderer":"skwasm","mainWasmPath":"main.dart.wasm",'
          '"jsSupportRuntimePath":"main.dart.mjs"},'
          '{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"}]};\n'
          '_flutter.loader.load();';
      final String out = dvVersionBootstrap(bootstrap, 'b7');
      final RegExpMatch config =
          RegExp(r'_flutter\.buildConfig = (\{.*\});').firstMatch(out)!;
      final Map<String, Object?> json =
          jsonDecode(config.group(1)!) as Map<String, Object?>;
      final List<Object?> builds = json['builds']! as List<Object?>;
      expect(builds[0], containsPair('mainWasmPath', 'main.dart.wasm?v=b7'));
      expect(builds[0], containsPair('jsSupportRuntimePath', 'main.dart.mjs?v=b7'));
      expect(builds[1], containsPair('mainJsPath', 'main.dart.js?v=b7'));
      expect(builds[1], containsPair('renderer', 'canvaskit'));
      expect(dvVersionBootstrap(out, 'b8'), contains('"main.dart.js?v=b8"'));
      expect(out, endsWith('_flutter.loader.load();'));
    });

    test('a bootstrap that names no build is left alone', () {
      // A custom bootstrap that sets mainJsPath in its own code: nothing the
      // build can rewrite safely, so the page asks without a version and the
      // worker treats it as this build.
      const String custom = '_flutter.loader.load({mainJsPath: "app.js"});';
      expect(dvVersionBootstrap(custom, 'b7'), custom);
    });
  });
}

/// One scenario run through the worker, under node.
///
/// Each worker build is a separate copy of the source with its own build
/// id, sharing one browser: the same caches, network and clients, as a
/// release does.
Future<Map<String, Object?>> _scenario(Map<String, Object?> scenario) async {
  final List<String> precache = (scenario['precache'] as List<Object?>?)?.cast<String>() ??
      const <String>['/', '/flutter_bootstrap.js', '/main.dart.js', '/main.dart.js_1.part.js'];
  final Set<String> builds = <String>{
    for (final Object? step in scenario['steps']! as List<Object?>)
      if (step is Map && step['build'] is String && (step['do'] == 'install' || step['do'] == 'fetch'))
        step['build']! as String,
  };
  final Map<String, String> workers = <String, String>{
    for (final String build in builds)
      build: dvServiceWorker(
          buildId: build, precache: precache, offlineRoute: null, apiBasePath: '/api'),
  };
  final Directory dir = Directory.systemTemp.createTempSync('dv_sw_release_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final StringBuffer source = StringBuffer(_shim);
  workers.forEach((String build, String worker) {
    // Each build's worker in a scope of its own, registering its handlers
    // into its own table.
    source.writeln('workers[${jsonEncode(build)}] = (() => {'
        ' const self = makeSelf(${jsonEncode(build)});'
        ' $worker\n return self; })();');
  });
  source.writeln('run(${jsonEncode(scenario)}).then((out) => console.log(JSON.stringify(out)));');
  final File script = File('${dir.path}/run.mjs')..writeAsStringSync(source.toString());
  final ProcessResult result = Process.runSync(_node()!, <String>[script.path]);
  if (result.exitCode != 0) fail('the worker did not run:\n${result.stderr}\n${result.stdout}');
  return (jsonDecode('${result.stdout}'.trim().split('\n').last) as Map<Object?, Object?>)
      .cast<String, Object?>();
}

String? _node() {
  for (final String candidate in const <String>['node', 'nodejs']) {
    try {
      if (Process.runSync(candidate, const <String>['--version']).exitCode == 0) return candidate;
    } on ProcessException {
      continue;
    }
  }
  return null;
}

/// A browser, as far as a service worker can see one: Cache Storage keyed by
/// URL, a network that answers "<build>:<path>" for whichever build the
/// server is on, clients, and a registration that counts update() calls.
const String _shim = r'''
const ORIGIN = 'https://app.test';
const workers = {};
const stores = new Map();
const state = {
  server: 'A', online: true, missing: new Set(), fetched: [], forceCache: [],
  updates: 0, installed: false, skipWaiting: false, clients: new Set(), assets: {},
};

function keyOf(request) {
  const url = typeof request === 'string' ? request : request.url;
  return new URL(url, ORIGIN).href;
}

function cacheFor(name) {
  if (!stores.has(name)) stores.set(name, new Map());
  const store = stores.get(name);
  return {
    put: async (request, response) => { store.set(keyOf(request), response.clone()); },
    match: async (request) => { const r = store.get(keyOf(request)); return r ? r.clone() : undefined; },
    delete: async (request) => store.delete(keyOf(request)),
    keys: async () => [...store.keys()].map((url) => new Request(url)),
    add: async (request) => { const r = await globalThis.fetch(request); if (!r.ok) throw new TypeError('bad'); store.set(keyOf(request), r); },
    addAll: async (requests) => { for (const r of requests) await cacheFor(name).add(r); },
  };
}

globalThis.caches = {
  open: async (name) => cacheFor(name),
  has: async (name) => stores.has(name),
  keys: async () => [...stores.keys()],
  delete: async (name) => stores.delete(name),
  match: async (request, options) => {
    for (const [name, store] of stores) {
      if (options && options.cacheName && options.cacheName !== name) continue;
      const hit = store.get(keyOf(request));
      if (hit) return hit.clone();
    }
    return undefined;
  },
};

globalThis.fetch = async (input, init) => {
  const request = input instanceof Request ? input : new Request(new URL(input, ORIGIN).href, init);
  const url = new URL(request.url);
  const mode = (init && init.cache) || request.cache;
  if (mode === 'force-cache') state.forceCache.push(url.origin === ORIGIN ? url.pathname : url.href);
  else state.fetched.push(url.origin === ORIGIN ? url.pathname : url.href);
  if (!state.online) throw new TypeError('Failed to fetch');
  const path = url.origin === ORIGIN ? url.pathname : url.href;
  if (state.missing.has(path)) return new Response('missing', { status: 404 });
  if (url.pathname.endsWith('dartvel_sw_assets.json')) {
    const v = url.searchParams.get('v') || state.server;
    return new Response(JSON.stringify(state.assets[v] || {}), { status: 200, headers: { 'content-type': 'application/json' } });
  }
  return new Response(state.server + ':' + path, {
    status: 200,
    headers: url.origin === ORIGIN ? {} : { 'access-control-allow-origin': '*' },
  });
};

function makeSelf(build) {
  const listeners = {};
  return {
    location: { origin: ORIGIN, href: ORIGIN + '/flutter_service_worker.js' },
    registration: {
      scope: ORIGIN + '/',
      update: () => { state.updates++; return Promise.resolve(); },
    },
    addEventListener: (type, handler) => { listeners[type] = handler; },
    skipWaiting: () => { state.skipWaiting = true; return Promise.resolve(); },
    clients: {
      claim: () => Promise.resolve(),
      matchAll: async () => [...state.clients].map((id) => ({ id, type: 'window' })),
    },
    listeners,
  };
}

async function fire(build, type, event) {
  const handler = workers[build].listeners[type];
  if (!handler) return undefined;
  let answered;
  const waited = [];
  handler(Object.assign({
    waitUntil: (p) => waited.push(p),
    respondWith: (p) => { answered = p; },
  }, event));
  await Promise.all(waited);
  return answered === undefined ? undefined : await answered;
}

async function run(scenario) {
  for (const p of scenario.missing || []) state.missing.add(p);
  state.assets = scenario.assets || {};
  const answers = [];
  for (const step of scenario.steps) {
    switch (step.do) {
      case 'install':
        await fire(step.build, 'install', {});
        state.installed = true;
        break;
      case 'activate':
        await fire(step.build, 'activate', {});
        break;
      case 'network': state.server = step.build; state.online = true; break;
      case 'offline': state.online = false; break;
      case 'resetFetches': state.fetched = []; break;
      case 'closeAll': state.clients.clear(); break;
      case 'warm': {
        await fire(step.build, 'message', { data: { type: 'dartvel:warm', build: step.from, urls: step.urls } });
        break;
      }
      case 'fetch': {
        state.clients.add(step.client);
        const request = new Request(new URL(step.path, ORIGIN).href);
        const response = await fire(step.build, 'fetch', { request, clientId: step.client });
        answers.push(response ? await response.text() : null);
        break;
      }
    }
  }
  await new Promise((r) => setTimeout(r, 20));
  const cached = [...stores.values()].flatMap((store) => [...store.keys()]);
  return {
    answers, cached, caches: [...stores.keys()], fetched: state.fetched,
    forceCache: state.forceCache, updates: state.updates,
    installed: state.installed, skipWaiting: state.skipWaiting,
  };
}
''';
