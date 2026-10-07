import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/adoption/adoption_plan.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:dartvel_cli/src/commands/init_command.dart';
import 'package:dartvel_cli/src/templates/project_templates.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ephemeral native folders configuration and flags', () {
    test('InitCommand flags default to all platforms (web, mobile, desktop)', () {
      final command = InitCommand();
      expect(command.argParser.options['web']?.defaultsTo, isTrue);
      expect(command.argParser.options['mobile']?.defaultsTo, isTrue);
      expect(command.argParser.options['desktop']?.defaultsTo, isTrue);
    });

    test('.gitignore template lists native platform folders as build outputs', () {
      final gitignore = ProjectTemplates.gitignoreTemplate;
      expect(gitignore, contains('android/'));
      expect(gitignore, contains('ios/'));
      expect(gitignore, contains('web/'));
      expect(gitignore, contains('linux/'));
      expect(gitignore, contains('windows/'));
      expect(gitignore, contains('macos/'));
    });

    test('pubspec template enables all target platforms by default with SDK constraints', () {
      final pubspec = ProjectTemplates.pubspecTemplate(
        name: 'sample_app',
        org: 'com.example.sample',
      );

      expect(pubspec, contains('sdk: ">=3.13.0 <4.0.0"'));
      expect(pubspec, contains('flutter: ">=3.47.0"'));
      expect(pubspec, contains('org: com.example.sample'));

      // Top-level platforms block
      expect(pubspec, contains('platforms:'));
      expect(pubspec, contains('  android:'));
      expect(pubspec, contains('  ios:'));
      expect(pubspec, contains('  web:'));
      expect(pubspec, contains('  linux:'));
      expect(pubspec, contains('  macos:'));
      expect(pubspec, contains('  windows:'));

      // dartvel section platforms list
      expect(pubspec, contains('    - android'));
      expect(pubspec, contains('    - ios'));
      expect(pubspec, contains('    - web'));
      expect(pubspec, contains('    - linux'));
      expect(pubspec, contains('    - macos'));
      expect(pubspec, contains('    - windows'));
    });

    test('pubspec template allows opting out of platforms', () {
      final pubspec = ProjectTemplates.pubspecTemplate(
        name: 'mobile_only',
        org: 'com.example',
        desktop: false,
        web: false,
        mobile: true,
      );

      expect(pubspec, contains('  android:'));
      expect(pubspec, contains('  ios:'));
      expect(pubspec, isNot(contains('  linux:')));
      expect(pubspec, isNot(contains('  macos:')));
      expect(pubspec, isNot(contains('  windows:')));
      expect(pubspec, isNot(contains('  web:')));
      expect(pubspec, isNot(contains('flutter_web_plugins')));
    });

    test('adoption report states existing Flutter native folders are left untouched and regenerated on build', () {
      final temp = Directory.systemTemp.createTempSync('dv_adopt_test_');
      addTearDown(() => temp.deleteSync(recursive: true));
      File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync('''
name: existing_app
environment:
  sdk: ^3.13.0
dependencies:
  flutter:
    sdk: flutter
''');

      final plan = dvPlanAdoption(temp.path);
      expect(
        plan.render(),
        contains('native platform folders: existing android/, ios/, etc. folders are left untouched; missing platform folders are regenerated on build.'),
      );
    });
  });

  group('dartvel create creates no native folders', () {
    test('scaffolds project structure without android, ios, web, or desktop folders', () async {
      final temp = Directory.systemTemp.createTempSync('dv_create_ephemeral_');
      addTearDown(() => temp.deleteSync(recursive: true));

      final runner = CommandRunner<void>('dartvel', 'Dartvel CLI')
        ..addCommand(InitCommand());

      await runner.run(['create', temp.path, '--project-name', 'ephemeral_app']);

      // Essential Dartvel files exist
      expect(File(p.join(temp.path, 'pubspec.yaml')).existsSync(), isTrue);
      expect(File(p.join(temp.path, 'lib', 'main.dart')).existsSync(), isTrue);
      expect(File(p.join(temp.path, '.gitignore')).existsSync(), isTrue);
      expect(File(p.join(temp.path, 'README.md')).existsSync(), isTrue);

      // Ephemeral native platform folders MUST NOT exist
      expect(Directory(p.join(temp.path, 'android')).existsSync(), isFalse,
          reason: 'android/ folder must be ephemeral and not created at create time');
      expect(Directory(p.join(temp.path, 'ios')).existsSync(), isFalse,
          reason: 'ios/ folder must be ephemeral and not created at create time');
      expect(Directory(p.join(temp.path, 'web')).existsSync(), isFalse,
          reason: 'web/ folder must be ephemeral and not created at create time');
      expect(Directory(p.join(temp.path, 'linux')).existsSync(), isFalse,
          reason: 'linux/ folder must be ephemeral and not created at create time');
      expect(Directory(p.join(temp.path, 'windows')).existsSync(), isFalse,
          reason: 'windows/ folder must be ephemeral and not created at create time');
      expect(Directory(p.join(temp.path, 'macos')).existsSync(), isFalse,
          reason: 'macos/ folder must be ephemeral and not created at create time');
    });
  });

  group('dartvel build auto-generates missing platform scaffold and applies writers', () {
    test('auto-generates missing platform folder then applies launcher identity + splash', () async {
      final temp = Directory.systemTemp.createTempSync('dv_build_ephemeral_');
      addTearDown(() => temp.deleteSync(recursive: true));

      File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync('''
name: ephemeral_test_app
environment:
  sdk: ">=3.13.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
dartvel:
  org: com.example.ephemeral
  pwa:
    name: "Custom App Title"
  splash:
    color: "#123456"
''');
      Directory(p.join(temp.path, 'lib')).createSync(recursive: true);
      File(p.join(temp.path, 'lib', 'main.dart')).writeAsStringSync('void main() {}');

      expect(Directory(p.join(temp.path, 'android')).existsSync(), isFalse);

      final List<String> processCalls = <String>[];
      final command = BuildCommand(
        root: temp.path,
        preflight: (String platform, {bool? autoInstall}) async => true,
        hasBuildRunner: (String root) => false,
        processStart: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          Map<String, String>? environment,
          bool runInShell = false,
        }) async {
          processCalls.add('$executable ${arguments.join(' ')}');
          return _FakeProcess();
        },
        processRun: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          bool runInShell = false,
        }) async {
          final invocation = '$executable ${arguments.join(' ')}';
          processCalls.add(invocation);

          if (executable == 'flutter' && arguments.contains('create')) {
            // Simulate flutter create generating the basic android scaffold
            final resDir = Directory(p.join(temp.path, 'android', 'app', 'src', 'main', 'res', 'values'));
            resDir.createSync(recursive: true);
            Directory(p.join(temp.path, 'android', 'app', 'src', 'main', 'res', 'drawable')).createSync(recursive: true);
            File(p.join(temp.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml')).writeAsStringSync('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="ephemeral_test_app"
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
''');
            File(p.join(resDir.path, 'styles.xml')).writeAsStringSync('''
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>
</resources>
''');
            File(p.join(temp.path, 'android', 'app', 'src', 'main', 'res', 'drawable', 'launch_background.xml')).writeAsStringSync('''
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@android:color/white" />
</layer-list>
''');
            return ProcessResult(0, 0, 'Scaffold generated', '');
          }

          return ProcessResult(0, 0, 'Build successful', '');
        },
      );

      final runner = CommandRunner<void>('dartvel', 'Dartvel CLI')
        ..addCommand(command);

      await runner.run(<String>['build', 'android']);

      // 1. flutter create was called quietly for android before build
      expect(
        processCalls.any((call) => call.contains('flutter create --platforms=android')),
        isTrue,
        reason: 'Build should call flutter create for missing android platform scaffold',
      );

      // 2. android/ folder now exists
      expect(Directory(p.join(temp.path, 'android')).existsSync(), isTrue);

      // 3. Launcher identity was applied (label was updated from pubspec dartvel.pwa.name)
      final manifest = File(p.join(temp.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml')).readAsStringSync();
      expect(manifest, contains('android:label="Custom App Title"'));

      // 4. Native splash was applied
      final splashXml = File(p.join(temp.path, 'android', 'app', 'src', 'main', 'res', 'values', 'dartvel_splash.xml'));
      expect(splashXml.existsSync(), isTrue);
      expect(splashXml.readAsStringSync(), contains('#123456'));
    });
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
