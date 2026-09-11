// One Chrome per machine, not one per project.
//
// No launch site ever lacked an executable: all three passed dvSystemChrome().
// On a machine with no system Chrome that is null, and puppeteer then fetches
// its own copy into `<workspace-root>/.dart_tool/puppeteer/local-chrome` -- a
// different root for the site, the CLI and every user project, so the same
// 380 MB browser was downloaded once per package. On the machine this was
// written on, that is what filled the disk: one run of this package's suite
// re-downloaded a copy that had been deleted an hour before, and the next
// write failed with "No space left on device".
//
// Moving the download to the shared user cache was not enough on its own. The
// site resolved puppeteer 3.26 and pinned Chrome 152; this package resolved
// 3.25 and pinned Chrome 150. Each fetched its own build into the shared
// cache, so it was one copy per puppeteer release rather than one per machine.
// A build already in the cache is reused now, whichever one it is.
import 'dart:io';

import 'package:dartvel_cli/src/build/chrome_launch.dart';
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart' show puppeteer;
import 'package:test/test.dart';

void main() {
  group('choosing a browser', () {
    test('a system Chrome is used and nothing is fetched', () async {
      final List<String> fetched = <String>[];
      final String exe = await dvChromeExecutable(
        findSystem: () => '/usr/bin/google-chrome',
        cachedVersion: (_) => '152.0.7977.42',
        download: (String cache, String? version) async {
          fetched.add(cache);
          return 'unused';
        },
      );

      expect(exe, '/usr/bin/google-chrome');
      expect(fetched, isEmpty);
    });

    test('without one, the pinned build is fetched into the shared cache',
        () async {
      final List<(String, String?)> fetched = <(String, String?)>[];
      final String exe = await dvChromeExecutable(
        findSystem: () => null,
        cachedVersion: (_) => null,
        download: (String cache, String? version) async {
          fetched.add((cache, version));
          return '$cache/chrome';
        },
      );

      // A null version is puppeteer's own pinned build.
      expect(fetched, <(String, String?)>[(puppeteer.userCachePath, null)]);
      expect(exe, '${puppeteer.userCachePath}/chrome');
      expect(fetched.single.$1, isNot(contains('.dart_tool')));
    });

    test('a build already in the shared cache is reused, not re-fetched',
        () async {
      String? asked;
      await dvChromeExecutable(
        findSystem: () => null,
        cachedVersion: (_) => '152.0.7977.42',
        download: (String cache, String? version) async {
          asked = version;
          return '$cache/$version/chrome';
        },
      );

      // Named, so downloadChrome finds the folder and returns at once
      // instead of fetching whatever this package's puppeteer pins.
      expect(asked, '152.0.7977.42');
    });
  });

  group('the newest build in the cache', () {
    late Directory cache;
    setUp(() => cache = Directory.systemTemp.createTempSync('dv-chrome-'));
    tearDown(() => cache.deleteSync(recursive: true));

    test('is the highest version, compared as numbers', () {
      for (final String v in <String>['150.0.7871.24', '152.0.7977.42', '99.0.1.1']) {
        Directory(p.join(cache.path, v)).createSync();
      }
      // As strings '99...' sorts above '152...'.
      expect(dvNewestCachedChrome(cache.path), '152.0.7977.42');
    });

    test('ignores a download still in progress, and anything not a version',
        () {
      Directory(p.join(cache.path, '150.0.7871.24')).createSync();
      Directory(p.join(cache.path, '153.0.1.1.downloading')).createSync();
      Directory(p.join(cache.path, 'junk')).createSync();
      expect(dvNewestCachedChrome(cache.path), '150.0.7871.24');
    });

    test('is nothing when the cache is empty or absent', () {
      expect(dvNewestCachedChrome(cache.path), isNull);
      expect(dvNewestCachedChrome(p.join(cache.path, 'missing')), isNull);
    });
  });
}
