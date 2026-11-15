// How fast `dartvel build android` is, without changing what it builds:
// one ABI when one is asked for, and Gradle's build cache and parallel
// execution on in the Android project the build generates.
import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/build/android_gradle_speed.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A project with an Android scaffold already in place, as `flutter create`
/// leaves one.
Directory _project() {
  final Directory temp = Directory.systemTemp.createTempSync(
    'dv_android_speed_',
  );
  File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync('''
name: speed_app
environment:
  sdk: ">=3.13.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
dartvel:
  org: com.example
''');
  Directory(p.join(temp.path, 'lib')).createSync(recursive: true);
  File(p.join(temp.path, 'lib', 'main.dart'))
      .writeAsStringSync('void main() {}');
  final Directory main = Directory(
    p.join(temp.path, 'android', 'app', 'src', 'main'),
  )..createSync(recursive: true);
  File(p.join(main.path, 'AndroidManifest.xml')).writeAsStringSync(
    '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <application android:label="speed_app"></application>\n'
    '</manifest>\n',
  );
  File(p.join(temp.path, 'android', 'gradle.properties')).writeAsStringSync(
    'org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G\n'
    'android.useAndroidX=true\n',
  );
  return temp;
}

Future<List<List<String>>> _build(
  Directory root,
  List<String> arguments,
) async {
  final List<List<String>> started = <List<String>>[];
  final BuildCommand command = BuildCommand(
    root: root.path,
    preflight: (String platform, {bool? autoInstall}) async => true,
    hasBuildRunner: (String root) => false,
    processRun: (
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      bool runInShell = false,
    }) async => ProcessResult(0, 0, '', ''),
    processStart:
        (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          Map<String, String>? environment,
          bool runInShell = false,
        }) async {
          started.add(arguments);
          return _FakeProcess();
        },
  );
  final int previous = exitCode;
  try {
    await (CommandRunner<void>(
      'dartvel',
      'test',
    )..addCommand(command)).run(<String>['build', ...arguments]);
  } finally {
    exitCode = previous;
  }
  return started;
}

void main() {
  group('one ABI when one is asked for', () {
    test('--arch on an Android build compiles that ABI alone', () {
      final List<String> args = resolveFlutterBuildArguments(
        platform: 'android',
        buildMode: '--release',
        splitPerAbi: true,
        androidArch: 'arm',
      );
      expect(
        args,
        containsAllInOrder(<String>['--target-platform', 'android-arm']),
      );
      expect(args, contains('--split-per-abi'));
      expect(
        resolveFlutterBuildArguments(
          platform: 'android',
          buildMode: '--release',
          androidArch: 'arm64',
        ),
        containsAllInOrder(<String>['--target-platform', 'android-arm64']),
      );
      expect(
        resolveFlutterBuildArguments(
          platform: 'fireos',
          buildMode: '--release',
          androidArch: 'x64',
        ),
        containsAllInOrder(<String>['--target-platform', 'android-x64']),
      );
    });

    test('without --arch every ABI is built, as before', () {
      expect(
        resolveFlutterBuildArguments(
          platform: 'android',
          buildMode: '--release',
          splitPerAbi: true,
        ),
        <String>['build', 'apk', '--release', '--split-per-abi'],
      );
    });

    test('an architecture means nothing to a build that is not Android', () {
      expect(
        resolveFlutterBuildArguments(
          platform: 'web',
          buildMode: '--release',
          androidArch: 'arm',
        ),
        isNot(contains('--target-platform')),
      );
    });

    test(
      'dartvel build android --arch arm hands Flutter that ABI only',
      () async {
        final Directory root = _project();
        addTearDown(() => root.deleteSync(recursive: true));

        final List<List<String>> started = await _build(root, <String>[
          'android',
          '--profile',
          'profile',
          '--split-per-abi',
          '--arch',
          'arm',
        ]);
        expect(started, hasLength(1));
        expect(
          started.single,
          containsAllInOrder(<String>['--target-platform', 'android-arm']),
        );

        final List<List<String>> all = await _build(root, <String>[
          'android',
          '--profile',
          'profile',
          '--split-per-abi',
        ]);
        expect(
          all.single,
          isNot(contains('--target-platform')),
          reason:
              'the default --arch is for embedded builds and must not '
              'narrow an Android build nobody asked to narrow',
        );
      },
    );
  });

  group('Gradle settings', () {
    test('the build cache and parallel execution are switched on', () {
      final Directory root = _project();
      addTearDown(() => root.deleteSync(recursive: true));

      expect(dvWriteAndroidGradleSpeed(root.path), isTrue);
      final String properties = File(
        p.join(root.path, 'android', 'gradle.properties'),
      ).readAsStringSync();
      expect(properties, contains('org.gradle.caching=true'));
      expect(properties, contains('org.gradle.parallel=true'));
      // What the project had is kept, in its place.
      expect(
        properties,
        startsWith(
          'org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G\n'
          'android.useAndroidX=true\n',
        ),
      );
    });

    test('a second build writes nothing', () {
      final Directory root = _project();
      addTearDown(() => root.deleteSync(recursive: true));

      dvWriteAndroidGradleSpeed(root.path);
      final File file = File(p.join(root.path, 'android', 'gradle.properties'));
      final String once = file.readAsStringSync();
      expect(dvWriteAndroidGradleSpeed(root.path), isFalse);
      expect(file.readAsStringSync(), once);
    });

    test('a setting the project chose is never overridden', () {
      final Directory root = _project();
      addTearDown(() => root.deleteSync(recursive: true));
      final File file = File(p.join(root.path, 'android', 'gradle.properties'));
      file.writeAsStringSync(
        'org.gradle.caching=false\n'
        'org.gradle.parallel = false\n',
      );

      dvWriteAndroidGradleSpeed(root.path);
      final String properties = file.readAsStringSync();
      expect(properties, isNot(contains('org.gradle.caching=true')));
      expect(properties, isNot(contains('org.gradle.parallel=true')));
    });

    test('no Android project, nothing written', () {
      final Directory root = Directory.systemTemp.createTempSync(
        'dv_no_android_',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      expect(dvWriteAndroidGradleSpeed(root.path), isFalse);
      expect(Directory(p.join(root.path, 'android')).existsSync(), isFalse);
    });

    test('dartvel build android writes them before Gradle runs', () async {
      final Directory root = _project();
      addTearDown(() => root.deleteSync(recursive: true));

      await _build(root, <String>['android', '--profile', 'profile']);
      expect(
        File(p.join(root.path, 'android', 'gradle.properties'))
            .readAsStringSync(),
        contains('org.gradle.caching=true'),
      );
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
