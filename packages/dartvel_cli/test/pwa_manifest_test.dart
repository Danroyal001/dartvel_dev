// The web app manifest, and whether a browser will offer to install it.
//
// `dartvel.pwa.enabled` has been read out of pubspec.yaml and emitted as a
// generated constant since the client generator was written, and nothing has
// ever consumed it -- a knob that reads like a feature. This is the part of
// the feature that decides whether it works.
//
// Installability fails silently. A manifest with a typo, a missing icon size
// or a display mode the specification does not allow is served with a 200,
// parsed without complaint, and simply never produces an install prompt.
// There is no error anywhere to find.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:dartvel_cli/src/build/pwa_manifest.dart';
import 'package:test/test.dart';

void main() {
  group('building the manifest', () {
    test('a name and short name both appear', () {
      final manifest = dvPwaManifest(name: 'Dartvel Example', shortName: 'DV');

      expect(manifest['name'], 'Dartvel Example');
      expect(manifest['short_name'], 'DV');
    });

    test('a missing short name falls back to the name', () {
      // short_name is what a launcher shows under the icon. Omitting it is
      // legal and gives the truncated full name, which is worse than a
      // sensible default.
      final manifest = dvPwaManifest(name: 'Dartvel Example');

      expect(manifest['short_name'], 'Dartvel Example');
    });

    test('the defaults are the installable ones', () {
      final manifest = dvPwaManifest(name: 'App');

      expect(manifest['start_url'], '.');
      expect(manifest['display'], 'standalone');
      expect(manifest['icons'], isA<List<Object?>>());
    });

    test('it serialises to JSON a browser can parse', () {
      final text = const JsonEncoder.withIndent('  ')
          .convert(dvPwaManifest(name: 'App'));

      expect(() => jsonDecode(text), returnsNormally);
      expect(jsonDecode(text), isA<Map<String, Object?>>());
    });
  });

  group('what makes it installable', () {
    test('the default manifest is installable', () {
      expect(dvPwaInstallability(dvPwaManifest(name: 'App')).installable,
          isTrue);
    });

    // Chrome requires an icon of at least 192 and one of at least 512, and
    // rejects the whole manifest for want of either. Nothing says so at build
    // time; the install prompt just never appears.
    test('both required icon sizes have to be present', () {
      final missing512 = dvPwaManifest(
        name: 'App',
        icons: const <DVPwaIcon>[DVPwaIcon(src: 'i.png', size: 192)],
      );

      final report = dvPwaInstallability(missing512);

      expect(report.installable, isFalse);
      expect(report.problems.join(' '), contains('512'));
    });

    test('one large icon satisfies both thresholds', () {
      // The criterion is "at least 192" and "at least 512", so a single
      // 512-pixel icon meets both. Requiring a distinct 192 would fail
      // manifests browsers install happily, and a gate that produces false
      // failures gets switched off.
      final report = dvPwaInstallability(dvPwaManifest(
        name: 'App',
        icons: const <DVPwaIcon>[DVPwaIcon(src: 'i.png', size: 512)],
      ));

      expect(report.installable, isTrue);
    });

    test('an icon below both thresholds satisfies neither', () {
      final report = dvPwaInstallability(dvPwaManifest(
        name: 'App',
        icons: const <DVPwaIcon>[DVPwaIcon(src: 'i.png', size: 64)],
      ));

      expect(report.installable, isFalse);
      expect(report.problems, hasLength(2));
    });

    test('a display mode outside the specification is rejected', () {
      // "fullscreen", "standalone", "minimal-ui" and "browser" are the whole
      // set. Anything else is ignored by the browser, which silently falls
      // back to browser mode -- an app that opens in a tab rather than a
      // window, with no error.
      final report = dvPwaInstallability(
          dvPwaManifest(name: 'App', display: 'stand-alone'));

      expect(report.installable, isFalse);
      expect(report.problems.join(' '), contains('display'));
    });

    test('browser display is legal but not installable', () {
      final report =
          dvPwaInstallability(dvPwaManifest(name: 'App', display: 'browser'));

      expect(report.installable, isFalse);
      expect(report.problems.join(' '), contains('browser'));
    });

    test('a manifest with no name is rejected', () {
      final report = dvPwaInstallability(<String, Object?>{
        'start_url': '.',
        'display': 'standalone',
        'icons': <Object?>[],
      });

      expect(report.installable, isFalse);
      expect(report.problems.join(' '), contains('name'));
    });

    test('every problem is reported, not only the first', () {
      // A build that fixes one and comes back for the next is a build run
      // four times.
      final report = dvPwaInstallability(<String, Object?>{
        'display': 'stand-alone',
        'icons': <Object?>[],
      });

      expect(report.problems.length, greaterThanOrEqualTo(3));
    });
  });

  group('linking it from the page', () {
    test('a page with no manifest link gets one', () {
      const html = '<html><head><title>x</title></head><body></body></html>';

      final linked = dvPwaLinkManifest(html);

      expect(linked, contains('<link rel="manifest" href="manifest.json">'));
      expect(linked.indexOf('rel="manifest"'), lessThan(linked.indexOf('</head>')));
    });

    test('a page that already links one is left alone', () {
      // Flutter's own web template ships a manifest link. Adding a second
      // gives two manifests, and which one wins is up to the browser.
      const html =
          '<html><head><link rel="manifest" href="manifest.json"></head></html>';

      expect(dvPwaLinkManifest(html), html);
    });

    test('a page with no head is returned unchanged rather than corrupted', () {
      const html = '<body>no head here</body>';

      expect(dvPwaLinkManifest(html), html);
    });
  });

  group('writing it into a built web app', () {
    late Directory web;

    setUp(() {
      web = Directory.systemTemp.createTempSync('dartvel-pwa-');
    });
    tearDown(() => web.deleteSync(recursive: true));

    test('it writes a manifest and reports no problems for a good one', () {
      File(p.join(web.path, 'index.html'))
          .writeAsStringSync('<html><head></head><body></body></html>');

      final result = dvPwaWrite(
        webBuildDir: web.path,
        manifest: dvPwaManifest(name: 'App'),
      );

      expect(result.wrote, isTrue);
      expect(result.problems, isEmpty);
      final written =
          jsonDecode(File(p.join(web.path, 'manifest.json')).readAsStringSync());
      expect((written as Map<String, Object?>)['name'], 'App');
    });

    test('it links the manifest from a page that lacks one', () {
      final index = File(p.join(web.path, 'index.html'))
        ..writeAsStringSync('<html><head></head><body></body></html>');

      final result =
          dvPwaWrite(webBuildDir: web.path, manifest: dvPwaManifest(name: 'A'));

      expect(result.linked, isTrue);
      expect(index.readAsStringSync(), contains('rel="manifest"'));
    });

    test('it leaves a page that already links one untouched', () {
      // Flutter's template ships the link. Writing a second is two manifests.
      const html =
          '<html><head><link rel="manifest" href="manifest.json"></head></html>';
      File(p.join(web.path, 'index.html')).writeAsStringSync(html);

      final result =
          dvPwaWrite(webBuildDir: web.path, manifest: dvPwaManifest(name: 'A'));

      expect(result.linked, isFalse);
      expect(File(p.join(web.path, 'index.html')).readAsStringSync(), html);
    });

    test('it overwrites the default manifest rather than leaving it', () {
      // Flutter generates one from the template carrying the package name.
      // Leaving it would ship "dartvel_example" to everyone who configured a
      // name.
      File(p.join(web.path, 'manifest.json'))
          .writeAsStringSync('{"name":"dartvel_example"}');

      dvPwaWrite(
          webBuildDir: web.path, manifest: dvPwaManifest(name: 'Real Name'));

      final written = jsonDecode(
          File(p.join(web.path, 'manifest.json')).readAsStringSync());
      expect((written as Map<String, Object?>)['name'], 'Real Name');
    });

    test('problems are reported, not thrown', () {
      // A manifest a browser will not install is still a web app that runs,
      // so this is a warning rather than a failed build.
      final result = dvPwaWrite(
        webBuildDir: web.path,
        manifest: dvPwaManifest(name: 'App', display: 'nonsense'),
      );

      expect(result.wrote, isTrue);
      expect(result.problems, isNotEmpty);
    });

    test('a missing build directory is reported rather than created', () {
      final result = dvPwaWrite(
        webBuildDir: p.join(web.path, 'nope'),
        manifest: dvPwaManifest(name: 'App'),
      );

      expect(result.wrote, isFalse);
      expect(result.problems, isNotEmpty);
    });
  });
}
