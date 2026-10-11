// `dartvel build android` end to end, with Flutter faked: a release build
// with no release key is refused before anything is generated, and one with
// a key hands it to Gradle through the environment and writes the release
// defaults into the project it builds.
import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="release_app"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
''';

const String _gradle = '''
plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.release_app"
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
''';

class _Started {
  _Started(this.arguments, this.environment);
  final List<String> arguments;
  final Map<String, String>? environment;
}

/// A project with an Android scaffold already in place, and [signing] under
/// `dartvel.android` when given.
Directory _project({bool signing = false}) {
  final Directory temp = Directory.systemTemp.createTempSync('dv_android_release_');
  File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync('''
name: release_app
environment:
  sdk: ">=3.13.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
dartvel:
  org: com.example
${signing ? '  android:\n    signing:\n      keyProperties: signing/key.properties\n' : ''}''');
  Directory(p.join(temp.path, 'lib')).createSync(recursive: true);
  File(p.join(temp.path, 'lib', 'main.dart')).writeAsStringSync('void main() {}');
  final Directory main = Directory(p.join(temp.path, 'android', 'app', 'src', 'main'))
    ..createSync(recursive: true);
  File(p.join(main.path, 'AndroidManifest.xml')).writeAsStringSync(_manifest);
  File(p.join(temp.path, 'android', 'app', 'build.gradle.kts')).writeAsStringSync(_gradle);
  if (signing) {
    Directory(p.join(temp.path, 'signing')).createSync();
    File(p.join(temp.path, 'signing', 'upload.jks')).writeAsStringSync('');
    File(p.join(temp.path, 'signing', 'key.properties')).writeAsStringSync(
        'storeFile=upload.jks\nstorePassword=store-secret\nkeyAlias=upload\nkeyPassword=key-secret\n');
  }
  return temp;
}

/// Every process the build ran to completion (generation), by command line.
final List<String> _ran = <String>[];

/// The exit code the last [_build] left.
int _exit = 0;

Future<List<_Started>> _build(Directory root, List<String> arguments) async {
  final List<_Started> started = <_Started>[];
  _ran.clear();
  final BuildCommand command = BuildCommand(
    root: root.path,
    preflight: (String platform, {bool? autoInstall}) async => true,
    hasBuildRunner: (String root) => false,
    processRun: (String executable, List<String> arguments,
            {String? workingDirectory, bool runInShell = false}) async {
      _ran.add('$executable ${arguments.join(' ')}');
      return ProcessResult(0, 0, '', '');
    },
    processStart: (String executable, List<String> arguments,
        {String? workingDirectory, Map<String, String>? environment, bool runInShell = false}) async {
      started.add(_Started(arguments, environment));
      return _FakeProcess();
    },
  );
  final int previous = exitCode;
  try {
    await (CommandRunner<void>('dartvel', 'test')..addCommand(command))
        .run(<String>['build', ...arguments]);
    _exit = exitCode;
  } finally {
    exitCode = previous;
  }
  return started;
}

void main() {
  test('a release build with no release key is refused before anything is written', () async {
    // Skipped where the host itself carries a key: the refusal is the point.
    if ((Platform.environment['DARTVEL_ANDROID_KEYSTORE'] ?? '').isNotEmpty) return;
    final Directory root = _project();
    addTearDown(() => root.deleteSync(recursive: true));

    final List<_Started> started = await _build(root, <String>['android']);

    expect(started, isEmpty, reason: 'Flutter must not be started without a release key');
    expect(_exit, 1);
    // Refused before generation, as a toolchain that is missing is.
    expect(_ran.where((String run) => run.contains('routes')), isEmpty);
    expect(File(p.join(root.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml')).readAsStringSync(),
        _manifest);
    expect(File(p.join(root.path, 'android', 'app', 'build.gradle.kts')).readAsStringSync(), _gradle);
  });

  test('a development build needs no release key and keeps the debug key', () async {
    final Directory root = _project();
    addTearDown(() => root.deleteSync(recursive: true));

    final List<_Started> started =
        await _build(root, <String>['android', '--profile', 'profile']);

    expect(started, hasLength(1));
    expect(started.single.arguments, contains('--profile'));
    expect(started.single.environment?['DARTVEL_ANDROID_KEYSTORE'], isNull);
  });

  test('a release build with a key hands it to Gradle and writes the release defaults', () async {
    final Directory root = _project(signing: true);
    addTearDown(() => root.deleteSync(recursive: true));

    final List<_Started> started = await _build(root, <String>['android']);

    expect(started, hasLength(1));
    final _Started flutter = started.single;
    expect(flutter.arguments, contains('--release'));
    expect(flutter.environment?['DARTVEL_ANDROID_KEYSTORE'],
        p.join(root.path, 'signing', 'upload.jks'));
    expect(flutter.environment?['DARTVEL_ANDROID_KEY_ALIAS'], 'upload');
    expect(flutter.environment?['DARTVEL_ANDROID_KEYSTORE_PASSWORD'], 'store-secret');
    // Never on the command line, which is logged and visible in `ps`.
    expect(flutter.arguments.join(' '), isNot(contains('secret')));

    final String android = p.join(root.path, 'android', 'app');
    final String manifest = File(p.join(android, 'src', 'main', 'AndroidManifest.xml')).readAsStringSync();
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
    expect(File(p.join(android, 'build.gradle.kts')).readAsStringSync(),
        contains('signingConfigs.getByName("dartvelRelease")'));
    expect(File(p.join(android, 'proguard-rules.pro')).readAsStringSync(),
        contains('-keep class dev.dartvel.** { *; }'));
    for (final String xml in <String>[
      'src/main/res/xml/dartvel_network_security_config.xml',
      'src/debug/res/xml/dartvel_network_security_config.xml',
      'src/profile/res/xml/dartvel_network_security_config.xml',
      'src/main/res/xml/dartvel_backup_rules.xml',
      'src/main/res/xml/dartvel_data_extraction_rules.xml',
    ]) {
      expect(File(p.join(android, xml)).existsSync(), isTrue, reason: '$xml was not written');
    }
    // Nothing secret is written into the project.
    for (final FileSystemEntity file in Directory(p.join(root.path, 'android')).listSync(recursive: true)) {
      if (file is File) {
        expect(file.readAsStringSync(), isNot(contains('store-secret')), reason: file.path);
      }
    }
  });

  test('a release build after one with a key keeps one signing block', () async {
    final Directory root = _project(signing: true);
    addTearDown(() => root.deleteSync(recursive: true));

    await _build(root, <String>['android']);
    final String once = File(p.join(root.path, 'android', 'app', 'build.gradle.kts')).readAsStringSync();
    final String manifestOnce =
        File(p.join(root.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml')).readAsStringSync();
    await _build(root, <String>['android']);

    expect(File(p.join(root.path, 'android', 'app', 'build.gradle.kts')).readAsStringSync(), once);
    expect(File(p.join(root.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml')).readAsStringSync(),
        manifestOnce);
  });
}

class _FakeProcess implements Process {
  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();
  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();
  @override
  IOSink get stdin => IOSink(_FakeStreamConsumer());
  @override
  Future<int> get exitCode => Future<int>.value(0);
  @override
  int get pid => 1234;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

class _FakeStreamConsumer implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) async {}
  @override
  Future<void> close() async {}
}
