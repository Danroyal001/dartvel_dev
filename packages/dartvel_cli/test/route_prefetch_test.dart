// Each prerendered page names its own JavaScript and images in its head, and
// the build writes down, per route, what a link to it can fetch early.
//
// The page's JavaScript is not one file. Every page is a deferred import, so
// dart2js splits it into parts that `loadLibrary()` fetches once main.dart.js
// has booted -- which, on a page opened directly, is a whole round trip after
// the HTML arrived with nothing to say about them. A preload in the head
// starts those downloads alongside main.dart.js instead of after it.
//
// Which parts belong to which page is written by dart2js into main.dart.js
// itself, as a table from each deferred import to its part files. That table
// is the only authority: guessing from file names or sizes would preload the
// wrong file and pay for it twice.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/route_prefetch.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The shape dart2js writes, taken from the site's own build.
const String mainJs = 'var init={deferredLibraryParts:{p0:[0],p1:[0,1],p2:[2],'
    'p3:[]},deferredPartUris:["main.dart.js_1.part.js",'
    '"main.dart.js_2.part.js","main.dart.js_3.part.js"],'
    'deferredPartHashes:["a","b","c"]};';

/// The generated router, trimmed to the lines that say which import is which
/// page.
const String router = '''
import 'package:site/pages/cloud.dart' deferred as p0;
import 'package:site/pages/docs.dart' deferred as p1;
import 'package:site/pages/features.dart' deferred as p2;
import 'package:site/pages/index.dart' deferred as p3;

class CloudPageGeneratedPage extends DartvelPage {
  static Future<void>? _libraryFuture;
  static Future<void> loadLibrary() {
    _resetRegistration;
    return _libraryFuture ??= p0.loadLibrary();
  }
}

class DocsPageGeneratedPage extends DartvelPage {
  static Future<void>? _libraryFuture;
  static Future<void> loadLibrary() {
    _resetRegistration;
    return _libraryFuture ??= p1.loadLibrary();
  }
}

class IndexPageGeneratedPage extends DartvelPage {
  static Future<void>? _libraryFuture;
  static Future<void> loadLibrary() {
    _resetRegistration;
    return _libraryFuture ??= p3.loadLibrary();
  }
}

GoRouter createDartvelRouter() {
  DVRoutePreloaders.register(
    '/cloud',
    CloudPageGeneratedPage.loadLibrary,
  );
  DVRoutePreloaders.register(
    '/docs',
    DocsPageGeneratedPage.loadLibrary,
  );
  DVRoutePreloaders.register(
    '/',
    IndexPageGeneratedPage.loadLibrary,
  );
  DVRoutePreloaders.register(
    '/custom',
    myOwnLoader,
  );
}
''';

const String shell = '<!doctype html><html><head><base href="/">'
    '<title>Site</title></head><body></body></html>';

void main() {
  group('the table dart2js wrote', () {
    test('gives each deferred import the part files it loads', () {
      final Map<String, List<String>> parts = dvDeferredParts(mainJs);
      expect(parts['p0'], <String>['main.dart.js_1.part.js']);
      expect(parts['p1'],
          <String>['main.dart.js_1.part.js', 'main.dart.js_2.part.js']);
      expect(parts['p2'], <String>['main.dart.js_3.part.js']);
      // An import with nothing of its own: all its code is in main.dart.js,
      // so there is nothing to fetch early and nothing to name.
      expect(parts['p3'], isEmpty);
    });

    test('reads quoted keys the same as bare ones', () {
      expect(
        dvDeferredParts('{deferredLibraryParts:{"p0":[0]},'
            'deferredPartUris:["main.dart.js_1.part.js"]}'),
        <String, List<String>>{
          'p0': <String>['main.dart.js_1.part.js'],
        },
      );
    });

    test('a build with no deferred code has no table and names nothing', () {
      expect(dvDeferredParts('var init={};main();'), isEmpty);
    });

    test('an index with no part behind it is dropped, not guessed at', () {
      // Silent if it went wrong the other way: a preload for a file that does
      // not exist costs a 404 on every page load and fails nothing.
      expect(
        dvDeferredParts('{deferredLibraryParts:{p0:[0,5]},'
            'deferredPartUris:["main.dart.js_1.part.js"]}')['p0'],
        <String>['main.dart.js_1.part.js'],
      );
    });
  });

  group('which import each route loads', () {
    test('comes from the page the router registered for it', () {
      expect(dvDeferredPrefixes(router), <String, String>{
        '/cloud': 'p0',
        '/docs': 'p1',
        '/': 'p3',
      });
    });

    test('a loader that is not a generated page is left out', () {
      // `/custom` is registered with a function of the application's own.
      // Nothing says which import it loads, so it gets no preload rather than
      // a wrong one.
      expect(dvDeferredPrefixes(router).containsKey('/custom'), isFalse);
    });
  });

  group('what the capture keeps', () {
    const String base = 'http://127.0.0.1:4000';

    test('an image Flutter fetched, relative to the site, preloaded as fetch',
        () {
      final DVCapturedImage? image = dvPageImage(
        url: '$base/assets/assets/hero.png',
        base: base,
        contentType: 'image/png',
        resourceType: 'fetch',
      );
      expect(image?.url, 'assets/assets/hero.png');
      // Flutter reads image bytes with fetch(). A preload has to be asked for
      // the same way or the browser downloads the file a second time.
      expect(image?.as, 'fetch');
    });

    test('an <img> from another site keeps its address, as image', () {
      final DVCapturedImage? image = dvPageImage(
        url: 'https://cdn.example.com/a.jpg',
        base: base,
        contentType: 'image/jpeg',
        resourceType: 'image',
      );
      expect(image?.url, 'https://cdn.example.com/a.jpg');
      expect(image?.as, 'image');
    });

    test('a content type with parameters is still an image', () {
      expect(
        dvPageImage(
          url: '$base/assets/assets/logo.svg',
          base: base,
          contentType: 'image/svg+xml; charset=utf-8',
          resourceType: 'xhr',
        )?.url,
        'assets/assets/logo.svg',
      );
    });

    test('the icons the browser asked for itself are not the page\'s', () {
      // The favicon and the manifest icons are requested by Chrome, not by
      // anything on the page, and every page would otherwise preload them.
      expect(
        dvPageImage(
          url: '$base/favicon.png',
          base: base,
          contentType: 'image/png',
          resourceType: 'other',
        ),
        isNull,
      );
    });

    test('what is not an image is not kept', () {
      for (final String type in <String>[
        'text/html',
        'application/javascript',
        'font/woff2',
      ]) {
        expect(
          dvPageImage(
            url: '$base/x',
            base: base,
            contentType: type,
            resourceType: 'fetch',
          ),
          isNull,
          reason: type,
        );
      }
      expect(
        dvPageImage(
          url: '$base/x',
          base: base,
          contentType: null,
          resourceType: 'fetch',
        ),
        isNull,
      );
    });

    test('an image inlined as data has nothing to fetch', () {
      expect(
        dvPageImage(
          url: 'data:image/png;base64,iVBORw0KGgo=',
          base: base,
          contentType: 'image/png',
          resourceType: 'image',
        ),
        isNull,
      );
    });
  });

  group('the head', () {
    const List<DVCapturedImage> images = <DVCapturedImage>[
      DVCapturedImage(url: 'assets/assets/hero.png', as: 'fetch'),
      DVCapturedImage(url: 'https://cdn.example.com/a.jpg', as: 'image'),
    ];

    test('names the page\'s parts and images inside <head>', () {
      final String html = dvApplyPreloadHead(
        shell,
        scripts: <String>['main.dart.js_2.part.js'],
        images: images,
      );
      expect(html,
          contains('<link rel="preload" href="main.dart.js_2.part.js" as="script">'));
      expect(
          html,
          contains('<link rel="preload" href="assets/assets/hero.png" '
              'as="fetch" crossorigin="anonymous">'));
      expect(
          html,
          contains('<link rel="preload" href="https://cdn.example.com/a.jpg" '
              'as="image">'));
      expect(html.indexOf('main.dart.js_2.part.js'),
          lessThan(html.indexOf('</head>')));
      expect(html.indexOf('main.dart.js_2.part.js'),
          greaterThan(html.indexOf('<head>')));
    });

    test('a second build replaces what the first one wrote', () {
      final String first = dvApplyPreloadHead(
        shell,
        scripts: <String>['main.dart.js_1.part.js'],
        images: const <DVCapturedImage>[],
      );
      final String second = dvApplyPreloadHead(
        first,
        scripts: <String>['main.dart.js_4.part.js'],
        images: const <DVCapturedImage>[],
      );
      expect(second, isNot(contains('main.dart.js_1.part.js')));
      expect(RegExp('rel="preload"').allMatches(second), hasLength(1));
    });

    test('nothing to name leaves the page as it was, and clears an old list',
        () {
      expect(
        dvApplyPreloadHead(shell,
            scripts: const <String>[], images: const <DVCapturedImage>[]),
        shell,
      );
      final String named = dvApplyPreloadHead(shell,
          scripts: <String>['main.dart.js_1.part.js'],
          images: const <DVCapturedImage>[]);
      expect(
        dvApplyPreloadHead(named,
            scripts: const <String>[], images: const <DVCapturedImage>[]),
        shell,
      );
    });

    test('an address cannot break out of its attribute', () {
      final String html = dvApplyPreloadHead(
        shell,
        scripts: const <String>[],
        images: const <DVCapturedImage>[
          DVCapturedImage(url: 'a.png"><script>x()</script>', as: 'image'),
        ],
      );
      expect(html, isNot(contains('<script>x()')));
      expect(html, contains('a.png&quot;&gt;'));
    });
  });

  group('writing a build', () {
    late Directory project;
    late Directory web;

    setUp(() {
      project = Directory.systemTemp.createTempSync('dv_prefetch_');
      web = Directory(p.join(project.path, 'build', 'web'))
        ..createSync(recursive: true);
      File(p.join(web.path, 'main.dart.js')).writeAsStringSync(mainJs);
      File(p.join(web.path, 'index.html')).writeAsStringSync(shell);
      File(p.join(web.path, 'docs', 'index.html'))
        ..createSync(recursive: true)
        ..writeAsStringSync(shell);
      File(dvCapturedImagesPathFor(project.path, '/docs'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(<Object?>[
          <String, Object?>{'url': 'assets/assets/hero.png', 'as': 'fetch'},
        ]));
    });

    tearDown(() => project.deleteSync(recursive: true));

    DVPrefetchSummary write() => dvWriteRoutePrefetch(
          projectRoot: project.path,
          webRoot: web.path,
          routerSource: router,
          // /cloud was never written as a page -- a build that skipped it,
          // or a route that failed to render -- and must not be created.
          routes: <String>['/', '/docs', '/cloud'],
        );

    test('each page names its own parts and images', () {
      write();
      final String docs =
          File(p.join(web.path, 'docs', 'index.html')).readAsStringSync();
      expect(docs, contains('href="main.dart.js_1.part.js" as="script"'));
      expect(docs, contains('href="main.dart.js_2.part.js" as="script"'));
      expect(docs, contains('href="assets/assets/hero.png" as="fetch"'));
      // Another page's part is not this page's business.
      expect(docs, isNot(contains('main.dart.js_3.part.js')));
    });

    test('the root is written too, from its own route', () {
      write();
      // `/` loads p3, which has no part: nothing to name, so no block.
      expect(File(p.join(web.path, 'index.html')).readAsStringSync(), shell);
    });

    test('a route with no page on disk is skipped, not created', () {
      write();
      expect(File(p.join(web.path, 'cloud', 'index.html')).existsSync(),
          isFalse);
    });

    test('the manifest says what a link to each route can fetch', () {
      final DVPrefetchSummary summary = write();
      final Map<String, Object?> manifest = jsonDecode(
        File(p.join(web.path, dvPrefetchManifestFile)).readAsStringSync(),
      ) as Map<String, Object?>;
      final Map<String, Object?> routes =
          manifest['routes']! as Map<String, Object?>;
      expect(routes['/docs'], <String, Object?>{
        'scripts': <String>['main.dart.js_1.part.js', 'main.dart.js_2.part.js'],
        'images': <Object?>[
          <String, Object?>{'url': 'assets/assets/hero.png', 'as': 'fetch'},
        ],
      });
      expect(summary.pages, 1);
      expect(summary.images, 1);
    });

    test('an image the page already names is not preloaded again', () {
      // The shell's own images -- the launch splash, an icon -- are asked for
      // by the document on every page, so the capture sees them on every
      // page. The browser finds them while it parses; a preload for one is a
      // duplicate hint, and listing it for links would prefetch on every
      // link an image the visitor already has.
      const String withSplash = '<!doctype html><html><head><base href="/">'
          '<style>#s{background:url("icons/bg.png")}</style></head><body>'
          '<img src="dartvel-splash.png" alt=""></body></html>';
      File(p.join(web.path, 'docs', 'index.html'))
          .writeAsStringSync(withSplash);
      File(dvCapturedImagesPathFor(project.path, '/docs')).writeAsStringSync(
        jsonEncode(<Object?>[
          <String, Object?>{'url': 'dartvel-splash.png', 'as': 'image'},
          <String, Object?>{'url': 'icons/bg.png', 'as': 'image'},
          <String, Object?>{'url': 'assets/assets/hero.png', 'as': 'fetch'},
        ]),
      );

      write();

      final String docs =
          File(p.join(web.path, 'docs', 'index.html')).readAsStringSync();
      expect(docs, contains('href="assets/assets/hero.png"'));
      expect(docs, isNot(contains('rel="preload" href="dartvel-splash.png"')));
      expect(docs, isNot(contains('rel="preload" href="icons/bg.png"')));
      final Map<String, Object?> routes = (jsonDecode(
        File(p.join(web.path, dvPrefetchManifestFile)).readAsStringSync(),
      ) as Map<String, Object?>)['routes']! as Map<String, Object?>;
      expect((routes['/docs']! as Map<String, Object?>)['images'], <Object?>[
        <String, Object?>{'url': 'assets/assets/hero.png', 'as': 'fetch'},
      ]);
    });

    test('without a main.dart.js the images are still named', () {
      File(p.join(web.path, 'main.dart.js')).deleteSync();
      write();
      final String docs =
          File(p.join(web.path, 'docs', 'index.html')).readAsStringSync();
      expect(docs, contains('assets/assets/hero.png'));
      expect(docs, isNot(contains('part.js')));
    });
  });
}
