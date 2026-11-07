// Reading the semantics tree of several routes at once.
//
// The read used to open one route, wait for its tree to stop growing, write
// it, and only then open the next. Most of that time is waiting -- for the app
// to boot, for a deferred page to arrive, for the tree to hold still -- so a
// site of two hundred routes spent most of an hour with an idle machine. The
// read now keeps several pages open in one browser, and what it writes must be
// exactly what the one-at-a-time read wrote.
import 'dart:io';

import 'package:dartvel_cli/src/build/capture_completeness.dart' show DVCaptureRun;
import 'package:dartvel_cli/src/build/route_prefetch.dart' show dvCapturedImagesPathFor;
import 'package:dartvel_cli/src/build/semantics_capture.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A stand-in for a built app: each route draws a semantics tree naming its
/// own path, after a delay, the way a Flutter page draws once its code is in.
const String _app = '''<!DOCTYPE html><html><head><title>app</title></head><body>
<script>
setTimeout(() => {
  const host = document.createElement('flt-semantics-host');
  const heading = document.createElement('h1');
  heading.textContent = 'Page ' + location.pathname;
  host.append(heading);
  const link = document.createElement('a');
  link.setAttribute('href', '/next' + location.pathname);
  link.textContent = 'Next after ' + location.pathname;
  host.append(link);
  document.body.append(host);
}, 1500);
</script></body></html>''';

void main() {
  _bootOnceTests();
  group('how many pages the read keeps open', () {
    test('follows the machine, leaving a quarter of its cores for everything else', () {
      expect(dvCaptureConcurrency(processors: 8), 6);
      expect(dvCaptureConcurrency(processors: 4), 3);
    });

    test('is never more than eight, however large the machine', () {
      expect(dvCaptureConcurrency(processors: 64), 8);
    });

    test('is one on a single core', () {
      expect(dvCaptureConcurrency(processors: 1), 1);
      expect(dvCaptureConcurrency(processors: 2), 1);
    });

    test('takes the number it is given', () {
      expect(dvCaptureConcurrency(processors: 8, requested: '2'), 2);
      expect(dvCaptureConcurrency(processors: 2, requested: '12'), 12);
    });

    test('refuses a number that is not a count of pages', () {
      expect(() => dvCaptureConcurrency(processors: 8, requested: '0'),
          throwsFormatException);
      expect(() => dvCaptureConcurrency(processors: 8, requested: 'many'),
          throwsFormatException);
    });
  });

  group('several routes at once', () {
    late Directory root;
    late Directory web;
    final List<String> routes = <String>[
      '/', '/a', '/b', '/c', '/d', '/e', '/f', '/g',
    ];

    setUp(() {
      root = Directory.systemTemp.createTempSync('dv_capture_parallel_');
      web = Directory(p.join(root.path, 'build', 'web'))
        ..createSync(recursive: true);
      File(p.join(web.path, 'index.html')).writeAsStringSync(_app);
    });
    tearDown(() => root.deleteSync(recursive: true));

    Map<String, String> trees() => <String, String>{
          for (final String route in routes)
            route: File(dvSemanticsPathFor(root.path, route)).readAsStringSync(),
        };

    test('write what the one-at-a-time read writes, in less time', () async {
      final Stopwatch serialTime = Stopwatch()..start();
      final DVCaptureRun serial = await dvCaptureSemantics(
          projectRoot: root.path, webRoot: web.path, routes: routes,
          concurrency: 1);
      serialTime.stop();
      expect(serial.browserAvailable, isTrue, reason: 'this test needs Chrome');
      expect(serial.captured, routes.length);
      final Map<String, String> one = trees();
      for (final String route in routes) {
        expect(one[route], contains('Page $route'));
      }

      final Stopwatch parallelTime = Stopwatch()..start();
      final DVCaptureRun parallel = await dvCaptureSemantics(
          projectRoot: root.path, webRoot: web.path, routes: routes,
          concurrency: 4);
      parallelTime.stop();
      expect(parallel.captured, routes.length);
      expect(trees(), one, reason: 'each route keeps its own tree');
      // Eight routes that each take over a second and a half to draw: one at
      // a time is at least twelve seconds, four at a time about a quarter.
      expect(parallelTime.elapsedMilliseconds,
          lessThan(serialTime.elapsedMilliseconds * 0.6),
          reason: 'serial ${serialTime.elapsedMilliseconds} ms, '
              'parallel ${parallelTime.elapsedMilliseconds} ms');
    }, timeout: const Timeout(Duration(minutes: 4)));
  });
}

/// A stand-in for an app with the capture hook: a fresh load boots for three
/// seconds, a move inside the running app draws in a fifth of one. Each route
/// fetches a shared image and its own, once per boot unless `go` forgets them,
/// the way Flutter's image cache does. `/redirect` lands elsewhere when moved
/// to inside the app.
String _hookedApp({bool hook = true}) => '''<!DOCTYPE html><html><head><title>app</title></head><body>
<script>
const decoded = new Set();
let booted = false;
async function render() {
  const old = document.querySelector('flt-semantics-host');
  if (old) old.remove();
  const path = location.pathname;
  await new Promise((done) => setTimeout(done, booted ? 200 : 3000));
  booted = true;
  for (const name of ['shared', path === '/' ? 'home' : path.slice(1)]) {
    if (!decoded.has(name)) { decoded.add(name); await fetch('/img/' + name + '.png'); }
  }
  const host = document.createElement('flt-semantics-host');
  const heading = document.createElement('h1');
  heading.textContent = 'Page ' + path;
  host.append(heading);
  document.body.append(host);
}
${hook ? '''if (navigator.webdriver) {
  globalThis.__dartvelCapture = {
    go(path) {
      decoded.clear();
      history.pushState({}, '', path === '/redirect' ? '/elsewhere' : path);
      render();
    },
    location() { return location.pathname; },
  };
}''' : ''}
render();
</script></body></html>''';

void _bootOnceTests() {
  group('one boot per tab', () {
    late Directory root;
    late Directory web;
    final List<String> routes = <String>['/', '/a', '/b', '/redirect', '/c', '/d'];

    setUp(() {
      root = Directory.systemTemp.createTempSync('dv_capture_boot_once_');
      web = Directory(p.join(root.path, 'build', 'web'))..createSync(recursive: true);
      Directory(p.join(web.path, 'img')).createSync();
      for (final String name in <String>['shared', 'home', 'a', 'b', 'redirect', 'c', 'd']) {
        File(p.join(web.path, 'img', '$name.png')).writeAsBytesSync(<int>[137, 80, 78, 71]);
      }
    });
    tearDown(() => root.deleteSync(recursive: true));

    Map<String, String> outputs() => <String, String>{
          for (final String route in routes) ...<String, String>{
            '$route tree': File(dvSemanticsPathFor(root.path, route)).readAsStringSync(),
            '$route images': File(dvCapturedImagesPathFor(root.path, route)).readAsStringSync(),
          },
        };

    test('moving inside the running app writes what fresh loads write, in '
        'less time', () async {
      File(p.join(web.path, 'index.html')).writeAsStringSync(_hookedApp());
      final Stopwatch freshTime = Stopwatch()..start();
      final DVCaptureRun fresh = await dvCaptureSemantics(
          projectRoot: root.path, webRoot: web.path, routes: routes,
          concurrency: 1, inApp: false);
      freshTime.stop();
      expect(fresh.browserAvailable, isTrue, reason: 'this test needs Chrome');
      expect(fresh.captured, routes.length);
      final Map<String, String> loaded = outputs();
      expect(loaded['/redirect tree'], contains('Page /redirect'));
      expect(loaded['/b images'], allOf(contains('img/shared.png'), contains('img/b.png')));

      final Stopwatch inAppTime = Stopwatch()..start();
      final DVCaptureRun inApp = await dvCaptureSemantics(
          projectRoot: root.path, webRoot: web.path, routes: routes,
          concurrency: 1);
      inAppTime.stop();
      expect(inApp.captured, routes.length);
      // The images included: a route moved to inside the app still asks for
      // the shared image an earlier route had already decoded. And the route
      // that redirects inside the app is read with a fresh load.
      expect(outputs(), loaded);
      expect(inAppTime.elapsedMilliseconds, lessThan(freshTime.elapsedMilliseconds * 0.7),
          reason: 'fresh ${freshTime.elapsedMilliseconds} ms, '
              'in the app ${inAppTime.elapsedMilliseconds} ms');
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('an app without the hook is read with fresh loads, the same way',
        () async {
      File(p.join(web.path, 'index.html')).writeAsStringSync(_hookedApp(hook: false));
      await dvCaptureSemantics(
          projectRoot: root.path, webRoot: web.path, routes: routes,
          concurrency: 2, inApp: false);
      final Map<String, String> loaded = outputs();
      await dvCaptureSemantics(
          projectRoot: root.path, webRoot: web.path, routes: routes,
          concurrency: 2);
      expect(outputs(), loaded);
    }, timeout: const Timeout(Duration(minutes: 4)));
  });
}
