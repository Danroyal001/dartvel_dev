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
}
