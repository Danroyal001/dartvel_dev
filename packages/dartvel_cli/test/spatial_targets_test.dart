// `dartvel build horizon` and `dartvel build visionos`.
//
// Horizon OS runs Android apps as 2D panels, and the Horizon Store refuses an
// APK whose manifest is not what Meta documents. The checks below are held
// against `aapt2 dump` output captured from a real APK (test/fixtures/horizon),
// so a check that passes is one aapt2 would agree with.
//
// visionOS has no Flutter embedder; the target is the iPad-compatible iOS
// build Apple runs on Vision Pro as "Designed for iPad".
import 'dart:io';

import 'package:dartvel_cli/src/build/spatial_targets.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:dartvel_cli/src/commands/doctor_command.dart';
import 'package:dartvel_core/dartvel.dart' show DVXRConfig;
import 'package:test/test.dart';

const String _flutterManifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="xrapp"
        android:name="\${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
''';

const String _kotlinGradle = '''
    defaultConfig {
        applicationId = "com.example.xrapp"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
    }
''';

String _fixture(String name) =>
    File('test/fixtures/horizon/$name').readAsStringSync();

void main() {
  group('the spatial targets are build targets', () {
    test('both are accepted, built by "all", and askable by doctor', () {
      for (final String target in spatialBuildPlatforms) {
        expect(buildPlatformArguments, contains(target));
        expect(allBuildPlatforms, contains(target));
        expect(doctorTargets, contains(target),
            reason: '`dartvel build $target` exists, so `dartvel doctor --target $target` must too');
      }
      expect(spatialBuildPlatforms, <String>['horizon', 'visionos']);
    });

    test('horizon builds wherever Android does; visionos only on a Mac', () {
      for (final String host in <String>['linux', 'macos', 'windows']) {
        expect(isPlatformAvailableOn('horizon', host), isTrue, reason: host);
      }
      expect(isPlatformAvailableOn('visionos', 'macos'), isTrue);
      expect(isPlatformAvailableOn('visionos', 'linux'), isFalse);
      expect(isPlatformAvailableOn('visionos', 'windows'), isFalse);
    });

    test('each writes into the native project it is built from', () {
      expect(dvNativeProjectFor('horizon'), 'android');
      expect(dvNativeProjectFor('visionos'), 'ios');
      expect(dvNativeProjectFor('fireos'), 'fireos');
      expect(dvNativeProjectFor('linux'), 'linux');
    });
  });

  group('flutter arguments', () {
    test('horizon is a 64-bit APK at the SDK levels Meta requires, and says what it is', () {
      expect(
        resolveFlutterBuildArguments(platform: 'horizon', buildMode: '--release'),
        <String>[
          'build',
          'apk',
          '--release',
          '--target-platform',
          'android-arm64',
          '--android-project-arg=$dvHorizonMinSdkProperty=$dvHorizonMinSdk',
          '--android-project-arg=$dvHorizonTargetSdkProperty=$dvHorizonTargetSdk',
          '--dart-define=DARTVEL_PLATFORM=horizon',
        ],
      );
      expect(dvHorizonMinSdk, inInclusiveRange(29, 34));
      expect(dvHorizonTargetSdk, 34);
    });

    test('a plain android build carries none of it', () {
      final List<String> android =
          resolveFlutterBuildArguments(platform: 'android', buildMode: '--release');
      expect(android.where((String a) => a.contains('dartvel') || a.contains('arm64')), isEmpty);
    });

    test('visionos is the unsigned iPad-compatible iOS build, and says what it is', () {
      expect(
        resolveFlutterBuildArguments(platform: 'visionos', buildMode: '--release'),
        <String>['build', 'ios', '--release', '--no-codesign', '--dart-define=DARTVEL_PLATFORM=visionos'],
      );
      expect(
        resolveFlutterBuildArguments(platform: 'visionos', buildMode: '--debug', simulator: true),
        <String>['build', 'ios', '--debug', '--simulator', '--dart-define=DARTVEL_PLATFORM=visionos'],
      );
    });

    test('an App Bundle is refused for horizon with the reason, not a pointer to android', () {
      final String? problem = dvPackageFormatProblem(platform: 'horizon', format: 'aab');
      expect(problem, contains('APK'));
      expect(problem, isNot(contains('dartvel build android')));
    });
  });

  group('the Horizon manifest', () {
    final DVXRConfig defaults = DVXRConfig.parse(null);

    test('adds what Meta requires of a 2D panel app', () {
      final String out = dvHorizonManifest(_flutterManifest, defaults, enabled: true);
      expect(out, contains('<uses-feature android:name="android.hardware.vr.headtracking" '
          'android:required="false" android:version="1"/>'));
      expect(out, contains('android:name="com.oculus.supportedDevices" '
          'android:value="quest2|questpro|quest3|quest3s"'));
      expect(out, contains('<layout android:defaultWidth="1024dp" android:defaultHeight="640dp"/>'));
      expect(out, contains('android:installLocation="auto"'));
      // A panel app is not an immersive one. The VR category would launch it
      // as an OpenXR app with nothing to draw.
      expect(out, isNot(contains('com.oculus.intent.category.VR')));
    });

    test('the layout is inside the main activity and the device list inside the application', () {
      final String out = dvHorizonManifest(_flutterManifest, defaults, enabled: true);
      final int activity = out.indexOf('android:name=".MainActivity"');
      final int activityEnd = out.indexOf('</activity>');
      final int layout = out.indexOf('<layout ');
      expect(layout, greaterThan(activity));
      expect(layout, lessThan(activityEnd));
      final int devices = out.indexOf('com.oculus.supportedDevices');
      expect(devices, greaterThan(out.indexOf('<application')));
      expect(devices, lessThan(out.indexOf('</application>')));
      final int feature = out.indexOf('android.hardware.vr.headtracking');
      expect(feature, lessThan(out.indexOf('<application')));
    });

    test('a second build replaces the block rather than adding another', () {
      final String once = dvHorizonManifest(_flutterManifest, defaults, enabled: true);
      expect(dvHorizonManifest(once, defaults, enabled: true), once);
      expect('com.oculus.supportedDevices'.allMatches(once), hasLength(1));
    });

    test('an android build after a horizon build gets its manifest back unchanged', () {
      final String horizon = dvHorizonManifest(_flutterManifest, defaults, enabled: true);
      expect(dvHorizonManifest(horizon, defaults, enabled: false), _flutterManifest);
      expect(dvHorizonManifest(_flutterManifest, defaults, enabled: false), _flutterManifest);
    });

    test('the declared panel and devices reach the manifest', () {
      final DVXRConfig config = DVXRConfig.parse(<String, Object?>{
        'panel': <String, Object?>{'width': 1280, 'height': 800, 'minWidth': 360, 'minHeight': 225},
        'horizon': <String, Object?>{'devices': <String>['quest3', 'quest3s']},
      });
      final String out = dvHorizonManifest(_flutterManifest, config, enabled: true);
      expect(out, contains('android:defaultWidth="1280dp" android:defaultHeight="800dp" '
          'android:minWidth="360dp" android:minHeight="225dp"'));
      expect(out, contains('android:value="quest3|quest3s"'));
    });
  });

  group('the Horizon gradle hook', () {
    test('makes the SDK levels overridable from the command line, once', () {
      final String? out = dvHorizonGradle(_kotlinGradle);
      expect(out, isNotNull);
      expect(out, contains('findProperty("$dvHorizonMinSdkProperty")'));
      expect(out, contains('findProperty("$dvHorizonTargetSdkProperty")'));
      // Without the property the value is Flutter's, so android is untouched.
      expect(out, contains('?: flutter.minSdkVersion'));
      expect(out, contains('?: flutter.targetSdkVersion'));
      expect(dvHorizonGradle(out!), out);
    });

    test('reads a Groovy build file too', () {
      final String? out = dvHorizonGradle(
          '        minSdkVersion flutter.minSdkVersion\n        targetSdkVersion flutter.targetSdkVersion\n');
      expect(out, contains("findProperty('$dvHorizonMinSdkProperty')"));
      expect(out, contains("findProperty('$dvHorizonTargetSdkProperty')"));
    });

    test('a build file it cannot recognise is reported, not guessed at', () {
      expect(dvHorizonGradle('defaultConfig { minSdk = 21 }'), isNull);
    });
  });

  group('aapt2', () {
    test('the newest build-tools is used, compared as numbers', () {
      final Directory sdk = Directory.systemTemp.createTempSync('dv_aapt2_');
      addTearDown(() => sdk.deleteSync(recursive: true));
      for (final String version in <String>['9.0.0', '35.0.0', '36.0.0']) {
        File('${sdk.path}/build-tools/$version/aapt2').createSync(recursive: true);
      }
      expect(dvLocateAapt2(environment: <String, String>{'ANDROID_HOME': sdk.path}),
          '${sdk.path}/build-tools/36.0.0/aapt2');
      expect(dvLocateAapt2(environment: const <String, String>{}), isNull);
    });

    test('the APK is where flutter build apk writes it for the mode', () {
      expect(dvHorizonApkPath('/app', '--release'), '/app/build/app/outputs/flutter-apk/app-release.apk');
    });
  });

  group('the built APK is checked against the store\'s rules', () {
    final DVXRConfig defaults = DVXRConfig.parse(null);
    final String badging = _fixture('badging.txt');
    final String tree = _fixture('manifest_xmltree.txt');

    List<String> problems({String? badgingText, String? treeText, DVXRConfig? config}) =>
        dvHorizonApkProblems(
          badging: badgingText ?? badging,
          manifestTree: treeText ?? tree,
          config: config ?? defaults,
        );

    test('an APK built the way Meta documents passes', () {
      expect(problems(), isEmpty);
    });

    test('a target SDK other than 34 is refused', () {
      final List<String> said = problems(
          badgingText: badging.replaceFirst("targetSdkVersion:'34'", "targetSdkVersion:'36'"));
      expect(said.join('\n'), contains('targetSdkVersion 36'));
    });

    test('a minimum SDK below Horizon OS\'s floor is refused', () {
      final List<String> said =
          problems(badgingText: badging.replaceFirst("minSdkVersion:'32'", "minSdkVersion:'24'"));
      expect(said.join('\n'), contains('minSdkVersion 24'));
    });

    test('a required head-tracking feature is refused: a panel app runs without it', () {
      final List<String> said = problems(
          badgingText: badging.replaceFirst('uses-feature-not-required: name=\'android.hardware.vr.headtracking\'',
              'uses-feature: name=\'android.hardware.vr.headtracking\''));
      expect(said.join('\n'), contains('headtracking'));
    });

    test('a prohibited permission is named, including one a plugin merged in', () {
      final List<String> said = problems(
          badgingText: "$badging\nuses-permission: name='android.permission.READ_PHONE_STATE'\n");
      expect(said.join('\n'), contains('READ_PHONE_STATE'));
      expect(dvHorizonProhibitedPermissions, contains('BIND_DEVICE_ADMIN'));
      expect(dvHorizonProhibitedPermissions, contains('QUERY_ALL_PACKAGES'));
    });

    test('32-bit or x86 native code is refused', () {
      final List<String> said = problems(
          badgingText: badging.replaceFirst("native-code: 'arm64-v8a'", "native-code: 'arm64-v8a' 'x86_64'"));
      expect(said.join('\n'), contains('x86_64'));
    });

    test('an install location other than auto is refused', () {
      final List<String> said = problems(badgingText: badging.replaceFirst("install-location:'auto'\n", ''));
      expect(said.join('\n'), contains('installLocation'));
    });

    test('a missing or different device list is refused', () {
      expect(problems(treeText: tree.replaceAll('com.oculus.supportedDevices', 'com.example.other')).join('\n'),
          contains('supportedDevices'));
      final DVXRConfig quest3 = DVXRConfig.parse(<String, Object?>{
        'horizon': <String, Object?>{'devices': <String>['quest3']},
      });
      expect(problems(config: quest3).join('\n'), contains('quest3'));
    });

    test('a panel with no default size is refused', () {
      expect(problems(treeText: tree.replaceAll('defaultWidth', 'gravity')).join('\n'), contains('layout'));
    });

    test('the VR launcher category is refused on a panel app', () {
      expect(problems(treeText: '$tree\n  A: android:name="com.oculus.intent.category.VR"\n').join('\n'),
          contains('com.oculus.intent.category.VR'));
    });
  });
}
