// What a Dartvel Android release build is by default: allowed onto the
// network, signed with the application's own key, unbackupable, refusing
// cleartext, and still able to find its own Java after R8 has been through it.
//
// Every one of these fails silently. Flutter puts INTERNET only in the debug
// and profile manifests, so a release build that cannot reach its backend
// looks exactly like a backend that is down. The template signs release with
// the debug key, which installs fine and is refused by Play only at upload --
// or, worse, is not refused by a side-loading channel at all. R8 strips a
// class nothing in Java refers to, and the only thing referring to the
// bridges is Dart, by name, at run time: a ClassNotFoundException on the
// first purchase, on a device, never in a debug build.
import 'dart:io';

import 'package:dartvel_cli/src/build/android_capture_bridge.dart';
import 'package:dartvel_cli/src/build/android_context_provider.dart';
import 'package:dartvel_cli/src/build/android_release_hardening.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _flutterManifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="dartvel_example"
        android:name="\${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:hardwareAccelerated="true"
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
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
''';

const String _kotlinGradle = '''
plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.app"

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
''';

const String _groovyGradle = '''
plugins {
    id "com.android.application"
    id "dev.flutter.flutter-gradle-plugin"
}

android {
    namespace "com.example.app"
    buildTypes {
        release {
            signingConfig signingConfigs.debug
        }
    }
}

flutter {
    source "../.."
}
''';

/// The `<application ...>` start tag of [manifest].
String _applicationTag(String manifest) {
  final int start = manifest.indexOf('<application');
  return manifest.substring(start, manifest.indexOf('>', start) + 1);
}

/// The value of [attribute] on [tag], or null.
String? _attribute(String tag, String attribute) =>
    RegExp('${RegExp.escape(attribute)}="([^"]*)"').firstMatch(tag)?.group(1);

DVAndroidReleaseConfig _config([Map<String, Object?>? android]) =>
    DVAndroidReleaseConfig.parse(
        android == null ? const <String, Object?>{} : <String, Object?>{'android': android});

void main() {
  group('dartvel.android release settings', () {
    test('default to network on, backup off, no cleartext host, no key', () {
      final DVAndroidReleaseConfig config = _config();
      expect(config.internet, isTrue);
      expect(config.allowBackup, isFalse);
      expect(config.cleartextHosts, isEmpty);
      expect(config.signingKeyProperties, isNull);
    });

    test('read what pubspec says', () {
      final DVAndroidReleaseConfig config = _config(<String, Object?>{
        'internet': false,
        'allowBackup': true,
        'cleartextHosts': <String>['printer.local', '192.168.1.20'],
        'signing': <String, Object?>{'keyProperties': '../secrets/key.properties'},
      });
      expect(config.internet, isFalse);
      expect(config.allowBackup, isTrue);
      expect(config.cleartextHosts, <String>['printer.local', '192.168.1.20']);
      expect(config.signingKeyProperties, '../secrets/key.properties');
    });

    test('refuse a cleartext host written as a URL', () {
      // A scheme or a path in a <domain> element matches nothing, so the
      // host the developer meant to allow stays refused and the build that
      // wrote it succeeded.
      expect(() => _config(<String, Object?>{'cleartextHosts': <String>['http://printer.local']}),
          throwsFormatException);
      expect(() => _config(<String, Object?>{'cleartextHosts': <String>['printer.local/api']}),
          throwsFormatException);
    });

    test('refuse a setting of the wrong type rather than guess', () {
      expect(() => _config(<String, Object?>{'allowBackup': 'no'}), throwsFormatException);
      expect(() => _config(<String, Object?>{'internet': 'yes'}), throwsFormatException);
      expect(() => _config(<String, Object?>{'signing': 'key.properties'}), throwsFormatException);
    });
  });

  group('the main manifest', () {
    test('asks for INTERNET, which Flutter leaves out of release', () {
      final String out = dvAndroidHardenedManifest(_flutterManifest, _config());
      expect(out, contains('<uses-permission android:name="android.permission.INTERNET"/>'));
      // Above <application>: inside it the merger drops it without a word.
      expect(out.indexOf('android.permission.INTERNET'), lessThan(out.indexOf('<application')));
    });

    test('does not ask for INTERNET when the application opts out', () {
      final String out = dvAndroidHardenedManifest(
          _flutterManifest, _config(<String, Object?>{'internet': false}));
      expect(out, isNot(contains('android.permission.INTERNET')));
    });

    test('does not declare INTERNET twice when the manifest already has it', () {
      final String already = _flutterManifest.replaceFirst('    <application',
          '    <uses-permission android:name="android.permission.INTERNET"/>\n    <application');
      final String out = dvAndroidHardenedManifest(already, _config());
      expect('android.permission.INTERNET'.allMatches(out).length, 1);
    });

    test('turns backup off and points at rules that exclude everything', () {
      final String tag = _applicationTag(dvAndroidHardenedManifest(_flutterManifest, _config()));
      expect(_attribute(tag, 'android:allowBackup'), 'false');
      // allowBackup=false does not stop an Android 12 device-to-device
      // transfer; only the extraction rules do.
      expect(_attribute(tag, 'android:dataExtractionRules'), '@xml/dartvel_data_extraction_rules');
      expect(_attribute(tag, 'android:fullBackupContent'), '@xml/dartvel_backup_rules');
    });

    test('allows backup when asked, still through the rules', () {
      final String tag = _applicationTag(dvAndroidHardenedManifest(
          _flutterManifest, _config(<String, Object?>{'allowBackup': true})));
      expect(_attribute(tag, 'android:allowBackup'), 'true');
      expect(_attribute(tag, 'android:dataExtractionRules'), '@xml/dartvel_data_extraction_rules');
    });

    test('refuses cleartext through the network security config', () {
      final String tag = _applicationTag(dvAndroidHardenedManifest(_flutterManifest, _config()));
      expect(_attribute(tag, 'android:usesCleartextTraffic'), 'false');
      expect(_attribute(tag, 'android:networkSecurityConfig'), '@xml/dartvel_network_security_config');
    });

    test('replaces a value already on <application> rather than adding a second', () {
      final String loose = _flutterManifest.replaceFirst(
          'android:label="dartvel_example"',
          'android:label="dartvel_example"\n        android:allowBackup="true"\n'
              '        android:usesCleartextTraffic="true"');
      final String tag = _applicationTag(dvAndroidHardenedManifest(loose, _config()));
      expect('android:allowBackup='.allMatches(tag).length, 1);
      expect(_attribute(tag, 'android:allowBackup'), 'false');
      expect(_attribute(tag, 'android:usesCleartextTraffic'), 'false');
      // The attributes it does not own stay as they were.
      expect(_attribute(tag, 'android:label'), 'dartvel_example');
      expect(_attribute(tag, 'android:icon'), '@mipmap/ic_launcher');
    });

    test('wins over a plugin manifest that says otherwise', () {
      // A library declaring allowBackup="true" is a manifest-merger error
      // against an application declaring false, unless the application says
      // it replaces it.
      final String out = dvAndroidHardenedManifest(_flutterManifest, _config());
      expect(out, contains('xmlns:tools="http://schemas.android.com/tools"'));
      final String? replace = _attribute(_applicationTag(out), 'tools:replace');
      expect(replace, isNotNull);
      expect(replace!.split(','), containsAll(<String>[
        'android:allowBackup',
        'android:usesCleartextTraffic',
        'android:networkSecurityConfig',
      ]));
    });

    test('is the same after a second build', () {
      final String once = dvAndroidHardenedManifest(_flutterManifest, _config());
      expect(dvAndroidHardenedManifest(once, _config()), once);
    });

    test('takes INTERNET back out when the application opts out later', () {
      final String once = dvAndroidHardenedManifest(_flutterManifest, _config());
      final String after = dvAndroidHardenedManifest(
          once, _config(<String, Object?>{'internet': false}));
      expect(after, isNot(contains('android.permission.INTERNET')));
    });

    test('composes with the other manifest writers in build order, twice', () {
      String build(String manifest) {
        String out = dvAndroidContextProviderManifest(manifest);
        out = dvAndroidCaptureManifest(out, const <String>[]);
        return dvAndroidHardenedManifest(out, _config());
      }

      final String once = build(_flutterManifest);
      final String twice = build(once);
      expect(twice, once);
      expect(twice, contains('dev.dartvel.jni.DartvelContext'));
      expect(twice, contains('dev.dartvel.jni.DartvelBridgeActivity'));
      expect('android.permission.INTERNET'.allMatches(twice).length, 1);
      expect(_attribute(_applicationTag(twice), 'android:allowBackup'), 'false');
    });
  });

  group('the network security config', () {
    test('refuses cleartext everywhere in release', () {
      final String xml = dvAndroidNetworkSecurityConfig(const <String>[], development: false);
      expect(xml, contains('<base-config cleartextTrafficPermitted="false">'));
      expect(xml, isNot(contains('cleartextTrafficPermitted="true"')));
      expect(xml, isNot(contains('localhost')));
    });

    test('allows cleartext to exactly the listed hosts', () {
      final String xml = dvAndroidNetworkSecurityConfig(
          const <String>['printer.local'], development: false);
      expect(xml, contains('<base-config cleartextTrafficPermitted="false">'));
      expect(xml, contains('<domain-config cleartextTrafficPermitted="true">'));
      expect(xml, contains('<domain includeSubdomains="false">printer.local</domain>'));
      expect(xml, isNot(contains('10.0.2.2')));
    });

    test('adds the machine running the emulator for a debug or profile build', () {
      final String xml = dvAndroidNetworkSecurityConfig(const <String>[], development: true);
      for (final String host in <String>['localhost', '127.0.0.1', '10.0.2.2']) {
        expect(xml, contains('<domain includeSubdomains="false">$host</domain>'));
      }
      expect(xml, contains('<base-config cleartextTrafficPermitted="false">'));
    });
  });

  group('the backup rules', () {
    const List<String> domains = <String>['root', 'file', 'database', 'sharedpref', 'external'];

    test('exclude every domain from cloud backup and device transfer when backup is off', () {
      final String xml = dvAndroidDataExtractionRules(allowBackup: false);
      for (final String section in <String>['cloud-backup', 'device-transfer']) {
        final String body = RegExp('<$section[^>]*>(.*?)</$section>', dotAll: true)
            .firstMatch(xml)!
            .group(1)!;
        for (final String domain in domains) {
          expect(body, contains('<exclude domain="$domain" path="."/>'),
              reason: '$section must exclude $domain');
        }
      }
      final String full = dvAndroidBackupRules(allowBackup: false);
      for (final String domain in domains) {
        expect(full, contains('<exclude domain="$domain" path="."/>'));
      }
    });

    test('exclude the databases and Dartvel state when backup is on', () {
      for (final String xml in <String>[
        dvAndroidDataExtractionRules(allowBackup: true),
        dvAndroidBackupRules(allowBackup: true),
      ]) {
        expect(xml, contains('<exclude domain="database" path="."/>'));
        // The session token and the offline data models live here.
        expect(xml, contains('<exclude domain="file" path="dartvel-device/"/>'));
        expect(xml, contains('<exclude domain="file" path="dartvel-offline/"/>'));
        // And not everything: that would be backup off by another name.
        expect(xml, isNot(contains('<exclude domain="root" path="."/>')));
      }
    });
  });

  group('the R8 keep rules', () {
    test('keep every class Dart looks up by name', () {
      // Read from the Dart that looks them up rather than from a list kept
      // here, so a new bridge that nobody added a rule for fails this test.
      final Directory flutter = Directory(p.join('..', 'dartvel_flutter', 'lib'));
      final Directory core = Directory(p.join('..', 'dartvel_core', 'lib'));
      final Set<String> looked = <String>{};
      for (final Directory dir in <Directory>[flutter, core]) {
        for (final FileSystemEntity file in dir.listSync(recursive: true)) {
          if (file is! File || !file.path.endsWith('.dart')) continue;
          for (final Match match
              in RegExp(r'dev/dartvel/[A-Za-z/]+').allMatches(file.readAsStringSync())) {
            looked.add(match.group(0)!.replaceAll('/', '.'));
          }
        }
      }
      expect(looked, contains('dev.dartvel.jni.DartvelContext'));
      final String rules = dvAndroidProguardRules('');
      final List<RegExp> keeps = <RegExp>[
        for (final Match keep in RegExp(r'-keep class ([\w.*]+) \{ \*; \}').allMatches(rules))
          RegExp('^${RegExp.escape(keep.group(1)!).replaceAll(r'\*\*', r'.*')}\$'),
      ];
      for (final String name in looked) {
        expect(keeps.any((RegExp keep) => keep.hasMatch(name)), isTrue,
            reason: '$name is looked up from Dart and no rule keeps it');
      }
    });

    test('keep what the developer already had, and appear once after two builds', () {
      const String own = '-keep class com.example.Own { *; }\n';
      final String once = dvAndroidProguardRules(own);
      expect(once, startsWith(own));
      expect(dvAndroidProguardRules(once), once);
    });
  });

  group('release signing in Gradle', () {
    test('signs release with the key the build hands it, never the debug key', () {
      final String out = dvAndroidGradleWithSigning(_kotlinGradle, kotlinScript: true);
      final String block = out.substring(out.indexOf('// dartvel.android.signing: start'));
      expect(block, contains('create("dartvelRelease")'));
      expect(block, contains('signingConfig = signingConfigs.getByName("dartvelRelease")'));
      for (final String name in dvAndroidSigningEnvironment) {
        expect(block, contains('"$name"'));
      }
      // After the template's own buildTypes, so it is the assignment that
      // stands.
      expect(out.indexOf('// dartvel.android.signing: start'),
          greaterThan(out.indexOf('signingConfigs.getByName("debug")')));
      // A release build Gradle is asked for with no key fails rather than
      // falling back.
      expect(block, contains('GradleException'));
      expect(block, contains('dartvel.android.signing'));
    });

    test('has the same block in Groovy', () {
      final String out = dvAndroidGradleWithSigning(_groovyGradle, kotlinScript: false);
      expect(out, contains("create('dartvelRelease')"));
      expect(out, contains("signingConfig signingConfigs.getByName('dartvelRelease')"));
      expect(out, contains('GradleException'));
    });

    test('carries no secret, and is the same after a second build', () {
      final String once = dvAndroidGradleWithSigning(_kotlinGradle, kotlinScript: true);
      expect(dvAndroidGradleWithSigning(once, kotlinScript: true), once);
      expect(once, isNot(contains('storePassword = "')));
    });
  });

  group('the release key', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('dv-signing-'));
    tearDown(() => temp.deleteSync(recursive: true));

    File keystore(String name) => File(p.join(temp.path, name))..createSync(recursive: true);

    test('comes from the four environment variables', () {
      keystore('upload.jks');
      final DVAndroidSigningResolution found = dvResolveAndroidSigning(
        root: temp.path,
        config: _config(),
        environment: <String, String>{
          'DARTVEL_ANDROID_KEYSTORE': p.join(temp.path, 'upload.jks'),
          'DARTVEL_ANDROID_KEYSTORE_PASSWORD': 'store-secret',
          'DARTVEL_ANDROID_KEY_ALIAS': 'upload',
          'DARTVEL_ANDROID_KEY_PASSWORD': 'key-secret',
        },
      );
      expect(found.problem, isNull);
      expect(found.signing!.environment['DARTVEL_ANDROID_KEY_ALIAS'], 'upload');
      expect(found.signing!.environment['DARTVEL_ANDROID_KEYSTORE'], p.join(temp.path, 'upload.jks'));
    });

    test('uses the keystore password for the key when no key password is given', () {
      // keytool's PKCS12 keys share the store's password, and Dartvel Cloud's
      // android-key-password is "when it is not the keystore's".
      keystore('upload.jks');
      final DVAndroidSigningResolution found = dvResolveAndroidSigning(
        root: temp.path,
        config: _config(),
        environment: <String, String>{
          'DARTVEL_ANDROID_KEYSTORE': p.join(temp.path, 'upload.jks'),
          'DARTVEL_ANDROID_KEYSTORE_PASSWORD': 'store-secret',
          'DARTVEL_ANDROID_KEY_ALIAS': 'upload',
        },
      );
      expect(found.problem, isNull);
      expect(found.signing!.keyPassword, 'store-secret');
    });

    test('is refused when the variables are half set', () {
      final DVAndroidSigningResolution found = dvResolveAndroidSigning(
        root: temp.path,
        config: _config(),
        environment: <String, String>{'DARTVEL_ANDROID_KEYSTORE': 'upload.jks'},
      );
      expect(found.signing, isNull);
      expect(found.problem, contains('DARTVEL_ANDROID_KEY_ALIAS'));
      expect(found.problem, contains('DARTVEL_ANDROID_KEYSTORE_PASSWORD'));
    });

    test('comes from the properties file dartvel.android.signing names', () {
      keystore('secrets/upload.jks');
      File(p.join(temp.path, 'secrets', 'key.properties')).writeAsStringSync(
          'storeFile=upload.jks\nstorePassword=s\nkeyAlias=upload\nkeyPassword=k\n');
      final DVAndroidSigningResolution found = dvResolveAndroidSigning(
        root: temp.path,
        config: _config(<String, Object?>{
          'signing': <String, Object?>{'keyProperties': 'secrets/key.properties'},
        }),
        environment: const <String, String>{},
      );
      expect(found.problem, isNull);
      // storeFile is relative to the properties file, as Gradle reads it.
      expect(found.signing!.environment['DARTVEL_ANDROID_KEYSTORE'],
          p.join(temp.path, 'secrets', 'upload.jks'));
      expect(found.signing!.environment['DARTVEL_ANDROID_KEY_PASSWORD'], 'k');
    });

    test('is refused, saying how to configure one, when there is none', () {
      final DVAndroidSigningResolution found = dvResolveAndroidSigning(
        root: temp.path,
        config: _config(),
        environment: const <String, String>{},
      );
      expect(found.signing, isNull);
      expect(found.problem, contains('debug key'));
      expect(found.problem, contains('dartvel.android.signing'));
      expect(found.problem, contains('DARTVEL_ANDROID_KEYSTORE'));
      expect(found.problem, contains('keytool'));
    });

    test('is refused when the properties file leaves a value out', () {
      keystore('upload.jks');
      File(p.join(temp.path, 'key.properties'))
          .writeAsStringSync('storeFile=upload.jks\nkeyAlias=upload\nkeyPassword=k\n');
      final DVAndroidSigningResolution found = dvResolveAndroidSigning(
        root: temp.path,
        config: _config(<String, Object?>{
          'signing': <String, Object?>{'keyProperties': 'key.properties'},
        }),
        environment: const <String, String>{},
      );
      expect(found.signing, isNull);
      expect(found.problem, contains('storePassword'));
    });

    test('is refused when the keystore is not where it says', () {
      final DVAndroidSigningResolution found = dvResolveAndroidSigning(
        root: temp.path,
        config: _config(),
        environment: <String, String>{
          'DARTVEL_ANDROID_KEYSTORE': p.join(temp.path, 'missing.jks'),
          'DARTVEL_ANDROID_KEYSTORE_PASSWORD': 's',
          'DARTVEL_ANDROID_KEY_ALIAS': 'upload',
          'DARTVEL_ANDROID_KEY_PASSWORD': 'k',
        },
      );
      expect(found.signing, isNull);
      expect(found.problem, contains('missing.jks'));
    });

    test('is refused when dartvel.android.signing names a file that is not there', () {
      final DVAndroidSigningResolution found = dvResolveAndroidSigning(
        root: temp.path,
        config: _config(<String, Object?>{
          'signing': <String, Object?>{'keyProperties': 'nope.properties'},
        }),
        environment: const <String, String>{},
      );
      expect(found.signing, isNull);
      expect(found.problem, contains('nope.properties'));
    });
  });
}
