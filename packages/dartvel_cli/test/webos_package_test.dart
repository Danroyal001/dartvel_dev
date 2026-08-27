// Assembling a webOS application without flutter-webos.
//
// LG's CLI cannot run here: it bundles Dart 3.10.9, below Dartvel's 3.12
// floor, so it cannot even resolve the example's dependencies. That is a
// version wall rather than a secret, and it does not stop Dartvel assembling
// the package itself -- LG's engine exports FlutterEngineRun and its runner
// template carries Sony's copyright, so a webOS app is an eLinux app with a
// webOS manifest on it.
//
// The manifest is where this fails quietly. webOS rejects an application for
// reasons it reports as a generic install failure on the television, hours
// after the build that caused them.
import 'package:dartvel_cli/src/build/webos_package.dart';
import 'package:test/test.dart';

void main() {
  group('the application manifest', () {
    test('a native application declares itself native', () {
      // The default is "web". A Flutter app packaged as web loads nothing and
      // shows a blank screen, which reads as a rendering bug.
      final info = webosAppInfo(id: 'com.example.app', title: 'App');

      expect(info['type'], 'native');
      expect(info['main'], isNotNull);
    });

    test('the entry point names the executable in the package', () {
      final info = webosAppInfo(
        id: 'com.example.app',
        title: 'App',
        executable: 'dartvel_app',
      );

      expect(info['main'], 'dartvel_app');
    });

    test('it carries the fields a launcher needs', () {
      final info = webosAppInfo(id: 'com.example.app', title: 'App');

      expect(info['id'], 'com.example.app');
      expect(info['title'], 'App');
      expect(info['icon'], isNotNull);
      expect(info['version'], isNotNull);
    });
  });

  group('what webOS refuses', () {
    test('an id has to be reverse-DNS', () {
      // A bare word installs nowhere and the failure names no reason.
      expect(webosPackageProblems(webosAppInfo(id: 'app', title: 'A')),
          isNotEmpty);
      expect(
          webosPackageProblems(webosAppInfo(id: 'com.example.app', title: 'A')),
          isEmpty);
    });

    test('an uppercase id is rejected', () {
      // webOS ids are lowercase. An uppercase one is accepted by the packager
      // and refused by the television.
      final problems =
          webosPackageProblems(webosAppInfo(id: 'com.Example.App', title: 'A'));

      expect(problems.join(' '), contains('lowercase'));
    });

    test('a version needs three numeric parts', () {
      // "1.0" packages and fails to install. So does "1.0.0-beta".
      expect(
        webosPackageProblems(
            webosAppInfo(id: 'com.example.app', title: 'A', version: '1.0')),
        isNotEmpty,
      );
      expect(
        webosPackageProblems(webosAppInfo(
            id: 'com.example.app', title: 'A', version: '1.0.0-beta')),
        isNotEmpty,
      );
      expect(
        webosPackageProblems(
            webosAppInfo(id: 'com.example.app', title: 'A', version: '1.0.0')),
        isEmpty,
      );
    });

    test('a missing title is reported rather than defaulted', () {
      // A blank tile on the home screen is worse than a build that says so.
      expect(webosPackageProblems(webosAppInfo(id: 'com.example.app', title: '')),
          isNotEmpty);
    });

    test('every problem is reported at once', () {
      final problems = webosPackageProblems(
          webosAppInfo(id: 'App', title: '', version: '1'));

      expect(problems.length, greaterThanOrEqualTo(3));
    });
  });

  group('the package layout', () {
    test('a release package carries an AOT library and no kernel', () {
      final layout = webosPackageLayout(
        id: 'com.example.app',
        mode: WebosMode.release,
      );

      final targets = layout.entries.map((WebosEntry e) => e.target);
      expect(targets, contains('lib/libapp.so'));
      expect(targets, isNot(contains('data/flutter_assets/kernel_blob.bin')));
    });

    test('a debug package carries kernel and no AOT library', () {
      final layout =
          webosPackageLayout(id: 'com.example.app', mode: WebosMode.debug);

      final targets = layout.entries.map((WebosEntry e) => e.target);
      expect(targets, contains('data/flutter_assets/kernel_blob.bin'));
      expect(targets, isNot(contains('lib/libapp.so')));
    });

    test('the engine and the manifest are both in it', () {
      final layout =
          webosPackageLayout(id: 'com.example.app', mode: WebosMode.release);

      final targets = layout.entries.map((WebosEntry e) => e.target);
      expect(targets, contains('lib/libflutter_engine.so'));
      expect(targets, contains('appinfo.json'));
      expect(targets, contains('data/icudtl.dat'));
    });

    test('every path is relative, so nothing escapes the package root', () {
      final layout =
          webosPackageLayout(id: 'com.example.app', mode: WebosMode.release);

      for (final WebosEntry entry in layout.entries) {
        expect(entry.target, isNot(startsWith('/')));
        expect(entry.target, isNot(contains('..')));
      }
    });

    test('the package root is the application id', () {
      // ares-package builds the IPK from a directory, and webOS expects that
      // directory to be named for the application. A mismatch installs an
      // application the launcher cannot find.
      expect(
        webosPackageLayout(id: 'com.example.app', mode: WebosMode.release).root,
        'com.example.app',
      );
    });
  });

  group('the engine it needs', () {
    test('webOS wants a 32-bit ARM engine', () {
      // The whole reason this was blocked. Televisions run a 32-bit ARM
      // userland and Google publishes no linux-arm embedder engine.
      expect(webosEngineArchitecture, 'arm');
    });

    test('the AOT library is built by a host snapshotter for that target', () {
      // gen_snapshot runs on the builder and emits ARM. Asking for an ARM
      // gen_snapshot would be asking for a binary to run on the television.
      expect(webosGenSnapshotRunsOnHost, isTrue);
    });
  });
}
