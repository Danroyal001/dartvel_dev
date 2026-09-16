// What `dartvel build android --profile development` writes into a project so
// the build pairs with `dartvel dev`.
import 'dart:io';

import 'package:dartvel_cli/src/build/build_profile.dart';
import 'package:dartvel_cli/src/devclient/android_dev_client.dart';
import 'package:dartvel_core/dartvel.dart' show DVDevClientManifest;
import 'package:test/test.dart';

const String _flutterCreateDebugManifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- The INTERNET permission is required for development. -->
    <uses-permission android:name="android.permission.INTERNET"/>
</manifest>
''';

void main() {
  group('the debug manifest', () {
    test('declares an activity a scanned dartvel-dev://pair link opens', () {
      final String manifest = dvAndroidDevClientDebugManifest(
        _flutterCreateDebugManifest,
      );
      expect(manifest, contains('dev.dartvel.devclient.DartvelDevPairActivity'));
      expect(manifest, contains('android:scheme="dartvel-dev"'));
      expect(manifest, contains('android:host="pair"'));
      expect(manifest, contains('android.intent.category.BROWSABLE'));
      // Inside <manifest>, or the packager refuses the file.
      expect(
        manifest.indexOf('<application>'),
        lessThan(manifest.indexOf('</manifest>')),
      );
    });

    test('building twice declares it once', () {
      final String once = dvAndroidDevClientDebugManifest(
        _flutterCreateDebugManifest,
      );
      final String twice = dvAndroidDevClientDebugManifest(once);
      expect(twice, once);
      expect(
        'DartvelDevPairActivity'.allMatches(twice).length,
        1,
      );
    });

    test('a project without a debug manifest gets one that can reach the '
        'network', () {
      final String manifest = dvAndroidDevClientDebugManifest(null);
      expect(
        'android.permission.INTERNET'.allMatches(manifest).length,
        1,
      );
      expect(manifest, contains('DartvelDevPairActivity'));
    });

    test('INTERNET is added once when the manifest lacks it', () {
      final String manifest = dvAndroidDevClientDebugManifest(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '</manifest>\n',
      );
      expect('android.permission.INTERNET'.allMatches(manifest).length, 1);
    });
  });

  group('the development entrypoint', () {
    test('starts the session before the application\'s own main', () {
      final String source = dvDevelopmentEntrypointSource(package: 'shopfront');
      expect(source, contains("import 'package:shopfront/main.dart' as app;"));
      expect(
        source.indexOf('DVDevClientSession.start()'),
        lessThan(source.indexOf('entry(args)')),
      );
      expect(source, contains('package:dartvel_flutter/dev_client.dart'));
    });

    test('a target under lib/ is imported by its package URI', () {
      // The same library the rest of the application imports; a file: URI
      // would be a second copy of it, with its own globals.
      expect(
        dvDevelopmentEntrypointSource(
          package: 'shopfront',
          target: 'lib/src/entry.dart',
        ),
        contains("import 'package:shopfront/src/entry.dart' as app;"),
      );
    });

    test('a target outside lib/ is imported relative to the entrypoint', () {
      expect(dvDevelopmentEntrypoint, startsWith('.dart_tool/dartvel/'));
      expect(
        dvDevelopmentEntrypointSource(
          package: 'shopfront',
          target: 'integration_test/app.dart',
        ),
        contains("import '../../integration_test/app.dart' as app;"),
      );
    });
  });

  test('the glue records the manifest this build compiled in', () {
    final String source = dvAndroidDevClientSource(
      const DVDevClientManifest(
        target: 'android',
        bindings: <String>['plugin:jni', 'dartvel_flutter@0.5.0'],
      ),
    );
    expect(
      source,
      contains(
        r'MANIFEST = "{\"target\":\"android\",\"bindings\":'
        r'[\"dartvel_flutter@0.5.0\",\"plugin:jni\"]}"',
      ),
    );
  });

  test('the Dart session calls the class the build writes', () {
    // Two packages that cannot import each other name the same class; a
    // rename on one side is a development build that never pairs.
    final String session = File(
      '../dartvel_flutter/lib/src/devclient/dev_session.dart',
    ).readAsStringSync();
    expect(session, contains("'$dvAndroidDevClientClass'"));
    expect(dvAndroidDevClientPath, contains(dvAndroidDevClientClass));
  });

  group('which builds get the dev client', () {
    test('an Android development build, built from the entrypoint', () {
      expect(
        dvDevelopmentBuildTarget(
          platform: 'android',
          profile: DVBuildProfile.development,
          target: null,
        ),
        dvDevelopmentEntrypoint,
      );
    });

    test('never a profile or release build', () {
      for (final DVBuildProfile profile in <DVBuildProfile>[
        DVBuildProfile.profile,
        DVBuildProfile.release,
      ]) {
        expect(
          dvDevelopmentBuildTarget(
            platform: 'android',
            profile: profile,
            target: 'lib/main.dart',
          ),
          'lib/main.dart',
        );
      }
    });

    test('not other platforms, which have no tunnel yet', () {
      expect(
        dvDevelopmentBuildTarget(
          platform: 'linux',
          profile: DVBuildProfile.development,
          target: null,
        ),
        isNull,
      );
    });
  });
}
