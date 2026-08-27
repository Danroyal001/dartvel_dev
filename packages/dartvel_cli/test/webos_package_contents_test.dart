// What is in the package, not what appinfo.json says about it.
//
// webosPackageProblems reads the metadata: it checks that `main` names
// something rather than nothing. It never checks that the something exists.
// So the example packaged, passed every check, uploaded as an artifact, and
// was recorded as "the package assembles" while carrying an appinfo.json
// pointing at a `dartvel_app` executable that was never built and an
// `icon.png` that was never copied.
//
// A television reports that as a generic install failure, hours later, with
// no mention of the missing file.
import 'package:dartvel_cli/src/build/webos_package.dart';
import 'package:test/test.dart';

/// Everything a good package holds, so each test can remove one thing.
Set<String> completePackage() => <String>{
      'appinfo.json',
      'dartvel_app',
      'icon.png',
      'lib/libflutter_engine.so',
      'lib/libapp.so',
      'data/icudtl.dat',
      'data/flutter_assets/AssetManifest.json',
    };

Map<String, Object?> info() => <String, Object?>{
      'id': 'com.dartvel.example',
      'title': 'Dartvel Example',
      'version': '1.0.0',
      'type': 'native',
      'main': 'dartvel_app',
      'icon': 'icon.png',
    };

void main() {
  group('the package holds what appinfo names', () {
    test('a complete package has no problems', () {
      expect(webosPackageContentProblems(info(), completePackage()), isEmpty);
    });

    test('the executable appinfo names must be in the package', () {
      // The one that actually shipped.
      final files = completePackage()..remove('dartvel_app');

      expect(
        webosPackageContentProblems(info(), files),
        contains(allOf(contains('dartvel_app'), contains('main'))),
      );
    });

    test('the icon appinfo names must be in the package', () {
      final files = completePackage()..remove('icon.png');

      expect(webosPackageContentProblems(info(), files),
          contains(contains('icon.png')));
    });

    test('a renamed executable is followed, not assumed', () {
      // The check has to read appinfo rather than look for the default name,
      // or it passes whenever the two agree and misses exactly the case where
      // they do not.
      final Map<String, Object?> renamed = info()..['main'] = 'other_app';
      final files = completePackage()
        ..remove('dartvel_app')
        ..add('other_app');

      expect(webosPackageContentProblems(renamed, files), isEmpty);
    });

    test('the engine must be there', () {
      final files = completePackage()..remove('lib/libflutter_engine.so');

      expect(webosPackageContentProblems(info(), files),
          contains(contains('libflutter_engine.so')));
    });

    test('the AOT library must be there', () {
      final files = completePackage()..remove('lib/libapp.so');

      expect(webosPackageContentProblems(info(), files),
          contains(contains('libapp.so')));
    });

    test('the assets and icu data must be there', () {
      final files = completePackage()
        ..remove('data/icudtl.dat')
        ..removeWhere((String p) => p.startsWith('data/flutter_assets/'));

      final problems = webosPackageContentProblems(info(), files);
      expect(problems, contains(contains('icudtl.dat')));
      expect(problems, contains(contains('flutter_assets')));
    });
  });
}
