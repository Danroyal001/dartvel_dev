// A route's capture is reused when nothing it could have read has changed.
//
// It used to be reused only when the whole web output was the same, and an
// edit to one line of one page (sigmadev.digital's about page) changed
// main.dart.js, six of its parts and one wasm module out of 370 -- not
// main.dart.wasm -- yet every one of 225 routes was read again: eleven
// minutes. The app's code files are now tracked per route: a route depends
// on every other file of the web output, and on the code files its browser
// tab actually fetched, from the tab's boot to the end of the route's read
// (so including what earlier routes in the same tab ran).
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/capture_completeness.dart' show DVCaptureRun;
import 'package:dartvel_cli/src/build/capture_deps.dart';
import 'package:dartvel_cli/src/build/semantics_capture.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test("names the app's code files, and nothing else", () {
    for (final String code in <String>[
      'main.dart.js', 'main.dart.js_12.part.js', 'main.dart.wasm', 'main.dart.mjs', 'main.dart_module23.wasm',
    ]) {
      expect(dvIsAppCodeFile(code), isTrue, reason: code);
    }
    for (final String other in <String>[
      'flutter_bootstrap.js', 'index.html', 'canvaskit/skwasm.wasm', 'canvaskit/skwasm.js', 'main.dart.support.js',
      'assets/AssetManifest.bin', 'assets/main.dart.wasm', 'dartvel/main.dart.js', 'main.dart.js.map',
    ]) {
      expect(dvIsAppCodeFile(other), isFalse, reason: other);
    }
    expect(dvAppCodePathOf('http://127.0.0.1:4100/main.dart_module7.wasm?v=3', 'http://127.0.0.1:4100'), 'main.dart_module7.wasm');
    expect(dvAppCodePathOf('http://127.0.0.1:4100/about', 'http://127.0.0.1:4100'), isNull);
    expect(dvAppCodePathOf('https://cdn.example/main.dart.js', 'http://127.0.0.1:4100'), isNull);
  });

  group('against a web output', () {
    late Directory web;
    setUp(() {
      web = Directory.systemTemp.createTempSync('capture_deps');
      for (final (String name, String body) in <(String, String)>[
        ('index.html', 'shell'), ('main.dart.wasm', 'main'), ('main.dart.mjs', 'mjs'),
        ('main.dart_module1.wasm', 'one'), ('main.dart_module2.wasm', 'two'), ('main.dart.js', 'js'),
        ('assets/FontManifest.json', '[]'),
      ]) {
        File(p.join(web.path, name))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(body);
      }
    });
    tearDown(() => web.deleteSync(recursive: true));

    test('the rest of the output keys every route; a code file only the routes that fetched it', () {
      final String before = dvCaptureStaticHash(web);
      File(p.join(web.path, 'main.dart_module2.wasm')).writeAsStringSync('two, edited');
      File(p.join(web.path, 'main.dart.js')).writeAsStringSync('js, edited');
      expect(dvCaptureStaticHash(web), before, reason: 'code files are tracked per route');
      File(p.join(web.path, 'assets/FontManifest.json')).writeAsStringSync('[{}]');
      expect(dvCaptureStaticHash(web), isNot(before), reason: 'anything else can change any page');
    });

    test('a route holds while every code file it fetched is as it was', () {
      final Map<String, String> recorded = dvAppCodeHashes(web, <String>['main.dart.wasm', 'main.dart.mjs', 'main.dart_module1.wasm']);
      expect(dvCaptureDepsHold(recorded, web), isTrue);
      File(p.join(web.path, 'main.dart_module2.wasm')).writeAsStringSync('two, edited');
      expect(dvCaptureDepsHold(recorded, web), isTrue, reason: 'it never fetched module 2');
      File(p.join(web.path, 'main.dart_module1.wasm')).writeAsStringSync('one, edited');
      expect(dvCaptureDepsHold(recorded, web), isFalse);
    });

    test('a code file it fetched that is gone, or a record that names nothing, does not hold', () {
      final Map<String, String> recorded = dvAppCodeHashes(web, <String>['main.dart.wasm', 'main.dart_module1.wasm']);
      File(p.join(web.path, 'main.dart_module1.wasm')).deleteSync();
      expect(dvCaptureDepsHold(recorded, web), isFalse);
      // A read that saw no code at all was not a read of the app: never reused.
      expect(dvCaptureDepsHold(const <String, String>{}, web), isFalse);
      expect(dvCaptureDepsHold(jsonDecode('{"../index.html": "x"}').cast<String, String>(), web), isFalse);
    });
  });

  test('the read records, per route, the code files its tab fetched since the tab booted', () async {
    final Directory root = Directory.systemTemp.createTempSync('capture_deps_read');
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory web = Directory(p.join(root.path, 'build', 'web'))..createSync(recursive: true);
    File(p.join(web.path, 'main.dart.wasm')).writeAsStringSync('main');
    File(p.join(web.path, 'main.dart_module1.wasm')).writeAsStringSync('a');
    File(p.join(web.path, 'main.dart_module2.wasm')).writeAsStringSync('b');
    // Each route fetches the main module and its own; /b also its neighbour's.
    File(p.join(web.path, 'index.html')).writeAsStringSync('''<!DOCTYPE html><html><head><title>app</title></head><body><script>
const own = {'/a': ['main.dart_module1.wasm'], '/b': ['main.dart_module2.wasm', 'main.dart_module1.wasm']}[location.pathname] || [];
Promise.all(['main.dart.wasm', ...own].map((f) => fetch('/' + f).then((r) => r.text()))).then(() => requestAnimationFrame(() => {
  const host = document.createElement('flt-semantics-host');
  const heading = document.createElement('h1');
  heading.textContent = 'Page ' + location.pathname;
  host.append(heading);
  document.body.append(host);
}));
</script></body></html>''');
    final DVCaptureRun run = await dvCaptureSemantics(
        projectRoot: root.path, webRoot: web.path, routes: const <String>['/a', '/b'], concurrency: 2, inApp: false);
    expect(run.browserAvailable, isTrue, reason: 'this test needs Chrome');
    expect(run.captured, 2);
    expect(run.appCode['/a'], <String>{'main.dart.wasm', 'main.dart_module1.wasm'});
    expect(run.appCode['/b'], <String>{'main.dart.wasm', 'main.dart_module1.wasm', 'main.dart_module2.wasm'});
  });
}
