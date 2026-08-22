// Where a hook child process looks for the pub cache.
//
// Windows CI proved this the hard way. Once the native build stopped hanging,
// it got as far as ffigen and died:
//
//   Could not find the pub cache. No `LOCALAPPDATA` environment variable
//   exists. Consider setting the `PUB_CACHE` variable manually.
//
// The Rust half had already succeeded. The failure was a child process
// inheriting an environment with neither PUB_CACHE nor LOCALAPPDATA in it.
import '../hook/build.dart';

import 'package:test/test.dart';

void main() {
  group('the environment a hook child receives', () {
    test('adds nothing when PUB_CACHE is already set', () {
      // Inheriting is correct here, and returning a map would mean rebuilding
      // an environment we have no reason to touch.
      expect(
        hookChildEnvironment(const <String, String>{
          'PUB_CACHE': r'C:\cache',
          'PATH': 'x',
        }),
        isNull,
      );
    });

    test('adds nothing when Windows has LOCALAPPDATA', () {
      // Dart derives the cache from it, so there is nothing to fix.
      expect(
        hookChildEnvironment(const <String, String>{
          'LOCALAPPDATA': r'C:\Users\runner\AppData\Local',
        }),
        isNull,
      );
    });

    test('derives PUB_CACHE from USERPROFILE when LOCALAPPDATA is missing', () {
      // The exact CI failure: a Windows child with neither variable.
      final env = hookChildEnvironment(const <String, String>{
        'USERPROFILE': r'C:\Users\runner',
      });
      expect(env, isNotNull);
      expect(env!['PUB_CACHE'], r'C:\Users\runner\AppData\Local\Pub\Cache');
    });

    test('derives PUB_CACHE from HOME on posix', () {
      final env = hookChildEnvironment(const <String, String>{
        'HOME': '/home/dev',
      });
      expect(env!['PUB_CACHE'], '/home/dev/.pub-cache');
    });

    test('keeps everything else the parent had', () {
      // A derived variable must add to the environment, never replace it: a
      // child that loses PATH cannot run at all.
      final env = hookChildEnvironment(const <String, String>{
        'HOME': '/home/dev',
        'PATH': '/usr/bin',
        'RUSTUP_HOME': '/rust',
      });
      expect(env!['PATH'], '/usr/bin');
      expect(env['RUSTUP_HOME'], '/rust');
    });

    test('adds nothing when there is no home to derive from', () {
      // Guessing a path that does not exist would replace a clear error with
      // a confusing one.
      expect(hookChildEnvironment(const <String, String>{'PATH': '/usr/bin'}),
          isNull);
    });
  });
}
