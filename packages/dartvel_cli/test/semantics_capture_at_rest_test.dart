// Two builds of the same site must write the same pages.
//
// dartvel.dev's 3.47.2 and 3.47.4 builds both put "ALSO" (the heading of the
// last section of a comparison page) before the "Claims about ..." link of the
// section above it, on some pages and not others, and a second read of the
// same pages put them back. The order of a semantics tree is Flutter's
// traversal order, and Flutter sorts siblings by where they are on screen.
// Each section of the site rises into view (DVModifier.revealOnScroll): until
// it has, it sits a quarter of its own height lower, so the bottom of a tall
// section is drawn below the top of the short one after it. A read that
// finished before the sections had risen wrote that order down, and the
// read's own check could not see it: it waited for the tree to stop changing
// *length*, and a reordered tree is the same length.
//
// The image preloads in each page's head changed between builds as well:
// they were written in the order the responses happened to arrive.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/capture_completeness.dart' show DVCaptureRun;
import 'package:dartvel_cli/src/build/page_shots.dart' show DVTextSettle;
import 'package:dartvel_cli/src/build/route_prefetch.dart'
    show dvCapturedImagesPathFor;
import 'package:dartvel_cli/src/build/semantics_capture.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A page whose sections rise into place, the way revealOnScroll draws them,
/// and are simply there for a reader who asked for reduced motion. While they
/// rise the second section's heading is above the first section's link.
const String _risingApp = '''<!DOCTYPE html><html><head><title>app</title></head><body>
<script>
const atRest = matchMedia('(prefers-reduced-motion: reduce)').matches;
function draw(order) {
  const old = document.querySelector('flt-semantics-host');
  if (old) old.remove();
  const host = document.createElement('flt-semantics-host');
  for (const label of order) {
    const node = document.createElement('flt-semantics');
    node.textContent = label;
    host.append(node);
  }
  document.body.append(host);
}
requestAnimationFrame(() => {
  if (atRest) { draw(['Claims about Rails', 'ALSO']); return; }
  draw(['ALSO', 'Claims about Rails']);
  setTimeout(() => draw(['Claims about Rails', 'ALSO']), 15000);
});
</script></body></html>''';

/// A page that asks for two images at once; which answer arrives first is up
/// to the network.
const String _twoImagesApp = '''<!DOCTYPE html><html><head><title>app</title></head><body>
<script>
requestAnimationFrame(async () => {
  await Promise.all([fetch('/img/zebra.png'), fetch('/img/apple.png')]);
  const host = document.createElement('flt-semantics-host');
  const node = document.createElement('h1');
  node.textContent = 'Images';
  host.append(node);
  document.body.append(host);
});
</script></body></html>''';

/// A page whose text is still from the first frame while it holds the
/// capture: the consent banner waits for the stored answer to be read, which
/// under load can take longer than the text takes to look settled. Builds of
/// sigmadev.digital wrote the banner on some pages and not others.
const String _holdingApp = '''<!DOCTYPE html><html><head><title>app</title></head><body>
<flt-semantics-placeholder></flt-semantics-placeholder>
<script>
window.__dvCaptureHolds = 1;
function draw(labels) {
  const old = document.querySelector('flt-semantics-host');
  if (old) old.remove();
  const host = document.createElement('flt-semantics-host');
  for (const label of labels) {
    const node = document.createElement('flt-semantics');
    node.textContent = label;
    host.append(node);
  }
  document.body.append(host);
}
requestAnimationFrame(() => {
  draw(['About us']);
  setTimeout(() => {
    draw(['About us', 'Cookies and measurement']);
    window.__dvCaptureHolds = 0;
  }, 4000);
});
</script></body></html>''';

List<String> _labels(String tree) => <String>[
      for (final Object? node in jsonDecode(tree) as List<Object?>)
        (node! as Map<String, Object?>)['label']! as String,
    ];

void main() {
  group('the semantics read waits for the tree itself to hold still', () {
    test('a tree that changes order but not length has not settled', () {
      final DVTextSettle settle = DVTextSettle();
      const String rising = '[{"label":"ALSO"},{"label":"Claims"}]';
      const String atRest = '[{"label":"Claims"},{"label":"ALSO"}]';
      expect(
        <bool>[
          for (final String tree in <String>[rising, atRest, rising, atRest])
            settle.add(tree.length, 0, tree),
        ],
        everyElement(isFalse),
        reason: 'the same length four times is not the same tree',
      );
      expect(
        <bool>[
          for (final String tree in <String>[atRest, atRest]) settle.add(tree.length, 0, tree),
        ],
        <bool>[false, true],
        reason: 'three looks at the same tree is settled',
      );
    });
  });

  group('a route is read at rest', () {
    late Directory root;
    late Directory web;

    setUp(() {
      root = Directory.systemTemp.createTempSync('dv_capture_at_rest_');
      web = Directory(p.join(root.path, 'build', 'web'))..createSync(recursive: true);
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('with motion reduced, so nothing is read halfway into place', () async {
      File(p.join(web.path, 'index.html')).writeAsStringSync(_risingApp);
      final DVCaptureRun run = await dvCaptureSemantics(
          projectRoot: root.path, webRoot: web.path, routes: <String>['/vs/rails'],
          concurrency: 1);
      expect(run.browserAvailable, isTrue, reason: 'this test needs Chrome');
      expect(
        _labels(File(dvSemanticsPathFor(root.path, '/vs/rails')).readAsStringSync()),
        <String>['Claims about Rails', 'ALSO'],
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('only once the page has let go of the capture', () async {
      File(p.join(web.path, 'index.html')).writeAsStringSync(_holdingApp);
      final DVCaptureRun run = await dvCaptureSemantics(
          projectRoot: root.path, webRoot: web.path, routes: <String>['/about'],
          concurrency: 1);
      expect(run.browserAvailable, isTrue, reason: 'this test needs Chrome');
      expect(
        _labels(File(dvSemanticsPathFor(root.path, '/about')).readAsStringSync()),
        <String>['About us', 'Cookies and measurement'],
        reason: 'text that holds still is not a settled page while it says it is not done',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('and its images are written in an order the network cannot change',
        () async {
      File(p.join(web.path, 'index.html')).writeAsStringSync(_twoImagesApp);
      Directory(p.join(web.path, 'img')).createSync();
      // The first one asked for is the larger, so its answer tends to arrive
      // second.
      File(p.join(web.path, 'img', 'zebra.png'))
          .writeAsBytesSync(<int>[137, 80, 78, 71, ...List<int>.filled(4 << 20, 0)]);
      File(p.join(web.path, 'img', 'apple.png')).writeAsBytesSync(<int>[137, 80, 78, 71]);
      final List<String> written = <String>[];
      for (int read = 0; read < 3; read++) {
        final DVCaptureRun run = await dvCaptureSemantics(
            projectRoot: root.path, webRoot: web.path, routes: <String>['/'],
            concurrency: 1);
        expect(run.browserAvailable, isTrue, reason: 'this test needs Chrome');
        written.add(File(dvCapturedImagesPathFor(root.path, '/')).readAsStringSync());
      }
      expect(written.toSet(), hasLength(1), reason: 'three reads, one answer: $written');
      final List<Object?> images = jsonDecode(written.first) as List<Object?>;
      expect(
        <Object?>[for (final Object? image in images) (image! as Map<String, Object?>)['url']],
        <String>['img/apple.png', 'img/zebra.png'],
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
