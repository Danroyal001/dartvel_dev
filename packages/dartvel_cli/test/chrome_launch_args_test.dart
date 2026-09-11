// The flags every headless Chrome this CLI starts has to carry.
//
// A container gives /dev/shm 64 megabytes by default -- Docker's default,
// which is every Codespace, every GitHub Actions container job and most CI.
// Chrome puts its shared memory there, runs out, and dies on startup without
// printing the DevTools address it is asked for, so the caller sees "Websocket
// url not found" and reports that no browser could be found. There is a
// browser; it cannot allocate.
//
// --disable-dev-shm-usage moves that to the ordinary temp directory and costs
// nothing anywhere else. Its absence is not a slow build, it is a build that
// fails: `dartvel build web` refuses when the semantics capture comes back
// empty, on the grounds that shipping four pages with no crawler-visible
// content is worse than stopping. That refusal is right, and it fired on a
// machine where the only thing wrong was a flag.
//
// The list is shared because it had already drifted: three launch sites, each
// with its own hand-written pair of arguments, so a fix to one reached none of
// the others.
import 'dart:io';

import 'package:dartvel_cli/src/build/chrome_launch.dart';
import 'package:test/test.dart';

void main() {
  test('shared memory does not come from /dev/shm', () {
    expect(dvChromeLaunchArgs, contains('--disable-dev-shm-usage'));
  });

  test('the sandbox flags every container needs are still there', () {
    expect(dvChromeLaunchArgs,
        containsAll(<String>['--no-sandbox', '--disable-setuid-sandbox']));
  });

  // The point of the shared list. Each of these launched Chrome with its own
  // pair of arguments, which is how the flag came to be missing from all
  // three at once.
  test('every launch site takes the shared list', () {
    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity
        in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String source = entity.readAsStringSync();
      if (!source.contains('puppeteer.launch')) continue;
      if (!source.contains('dvChromeLaunchArgs')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'these start Chrome with arguments of their own');
  });

  // The browser itself, not only its flags.
  //
  // The semantics capture called puppeteer.launch with no executablePath, so
  // on a machine with Chrome already installed it went looking for a copy of
  // its own -- and when it could not get one it reported "Websocket url not
  // found", which reads as a browser that crashed rather than one that was
  // never there. The build then refused, correctly, on a machine with a
  // working Chrome at /usr/bin/google-chrome.
  //
  // The resolver already existed one file away, used by the PWA verifier and
  // by nothing else. That is the same drift as the flags: written once,
  // reached by one of the three callers.
  group('the browser', () {
    test('an installed Chrome is found rather than downloaded', () {
      // Only meaningful where one is installed, which is the case this is
      // about; elsewhere the answer is legitimately null.
      final String? found = dvSystemChrome();
      for (final String candidate in const <String>[
        '/usr/bin/google-chrome',
        '/usr/bin/chromium',
      ]) {
        if (File(candidate).existsSync()) {
          expect(found, isNotNull,
              reason: '$candidate is installed and was not found');
          return;
        }
      }
      markTestSkipped('no system Chrome to find');
    });

    test('DARTVEL_CHROME wins, so a machine can name its own', () {
      // The environment is what CI and a developer with an unusual install
      // both reach for, and it has to beat the well-known paths rather than
      // being a fallback after them.
      expect(dvSystemChrome(environment: const <String, String>{
        'DARTVEL_CHROME': '/somewhere/else/chrome',
      }), '/somewhere/else/chrome');
    });

    test('an empty DARTVEL_CHROME is not a path', () {
      expect(
        dvSystemChrome(environment: const <String, String>{
          'DARTVEL_CHROME': '',
        }),
        isNot(''),
      );
    });

    test('every launch site resolves its browser through dvChromeExecutable', () {
      // It used to require dvSystemChrome here, and every launch site passed
      // it. That was not enough: on a machine with no system Chrome the call
      // returns null and puppeteer downloads a browser into the workspace's
      // own .dart_tool, once per project. dvChromeExecutable asks for the
      // system browser first and keeps any download in the one shared cache,
      // so it is what a launch site has to go through now.
      final List<String> offenders = <String>[];
      for (final FileSystemEntity entity
          in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // Code only. chrome_launch.dart names `puppeteer.launch` in a doc
        // comment explaining the bug it fixes, and defines the resolver rather
        // than calling it -- so a scan of the raw text reported the file that
        // holds the fix as the thing the fix is missing from.
        final String source = entity
            .readAsLinesSync()
            .where((String line) => !line.trimLeft().startsWith('//'))
            .join('\n');
        if (!source.contains('puppeteer.launch(')) continue;
        if (!source.contains('dvChromeExecutable()')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'these let puppeteer choose a browser itself, which it '
              'downloads into this workspace rather than the shared cache');
    });
  });
}
