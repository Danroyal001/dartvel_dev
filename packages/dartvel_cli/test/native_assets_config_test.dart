// The configuration a bundle build needs and cannot make for itself.
//
// A terminal build hands the project to the embedder, which runs
// `flutter build bundle`. For a project with build hooks -- which every
// Dartvel application has, because the Rust runtime is one -- that step reads
// the compiler configuration those hooks need, and looks for it at
// `<asset dir>/linux/x64/<mode>/CMakeCache.txt`. Nothing writes it there. The
// desktop build writes one, at `build/linux/x64/<mode>/CMakeCache.txt`.
//
// So a Dartvel application could not be built for a terminal at all, and the
// job that proves the terminal works has been rendering the embedder's own
// sample instead -- which proves the embedder and says nothing about Dartvel.
import 'dart:io';

import 'package:dartvel_cli/src/build/native_assets_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory workspace({bool desktopBuilt = true, String mode = 'debug'}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_na_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: shopfront\n');
  if (desktopBuilt) {
    File(p.join(root.path, 'build', 'linux', 'x64', mode, 'CMakeCache.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('CMAKE_C_COMPILER:FILEPATH=/usr/bin/cc\n');
  }
  return root;
}

void main() {
  test('the cache the bundle build looks for is put where it looks', () {
    final Directory root = workspace();

    final DVNativeAssetsConfig result =
        dvConfigureNativeAssets(root.path, mode: 'debug');

    expect(result.ready, isTrue);
    expect(
      File(p.join(root.path, 'build', 'flutter_assets', 'linux', 'x64', 'debug',
              'CMakeCache.txt'))
          .existsSync(),
      isTrue,
    );
  });

  test('with no desktop build there is nothing to point at, and it says so',
      () {
    // Not a silent success. The bundle build would then fail with Flutter's
    // own message about a path nobody has heard of, which is how this went
    // undiagnosed.
    final DVNativeAssetsConfig result =
        dvConfigureNativeAssets(workspace(desktopBuilt: false).path,
            mode: 'debug');

    expect(result.ready, isFalse);
    expect(result.reason, contains('CMakeCache.txt'));
    expect(result.reason, contains('desktop build'));
  });

  test('the mode is the one being built', () {
    // A release terminal build pointed at the debug cache would compile the
    // hooks with the wrong flags, which is a difference nobody would look
    // for in a rendering bug.
    final Directory root = workspace(mode: 'release');

    expect(dvConfigureNativeAssets(root.path, mode: 'release').ready, isTrue);
    expect(dvConfigureNativeAssets(root.path, mode: 'debug').ready, isFalse);
  });

  test('running it twice is running it once', () {
    // The build runs it every time, and a link that already points where it
    // should is not an error.
    final Directory root = workspace();

    expect(dvConfigureNativeAssets(root.path, mode: 'debug').ready, isTrue);
    expect(dvConfigureNativeAssets(root.path, mode: 'debug').ready, isTrue);
  });

  test('a cache that moved is followed, not left stale', () {
    // The desktop build was rerun and wrote a different cache. A link made
    // once and never checked would hand the hooks the old compiler
    // configuration.
    final Directory root = workspace();
    dvConfigureNativeAssets(root.path, mode: 'debug');

    File(p.join(root.path, 'build', 'linux', 'x64', 'debug', 'CMakeCache.txt'))
        .writeAsStringSync('CMAKE_C_COMPILER:FILEPATH=/usr/bin/clang\n');

    expect(dvConfigureNativeAssets(root.path, mode: 'debug').ready, isTrue);
    expect(
      File(p.join(root.path, 'build', 'flutter_assets', 'linux', 'x64', 'debug',
              'CMakeCache.txt'))
          .readAsStringSync(),
      contains('clang'),
    );
  });
}
