// `dartvel build dev-client --target <platform>`: what the shell is built
// from, and every reason not to start building it.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:dartvel_cli/src/devclient/dev_client_project.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _gradleWithFlavor = '''
android {
    flavorDimensions += "app"
    productFlavors {
        create("devclient") {
            dimension = "app"
            applicationIdSuffix = ".devclient"
        }
    }
}
''';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_dev_client_build_');
    File(
      p.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: shopfront\n');
    File(p.join(root.path, 'pubspec.lock')).writeAsStringSync('''
packages:
  dartvel_flutter:
    source: hosted
    version: "0.4.0"
''');
    File(p.join(root.path, '.flutter-plugins-dependencies')).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'plugins': <String, Object?>{
          'android': <Object?>[
            <String, Object?>{
              'name': 'jni',
              'native_build': true,
              'dev_dependency': false,
            },
          ],
          'ios': <Object?>[],
        },
      }),
    );
    File(p.join(root.path, 'android', 'app', 'build.gradle.kts'))
      ..createSync(recursive: true)
      ..writeAsStringSync(_gradleWithFlavor);
  });

  tearDown(() => root.deleteSync(recursive: true));

  DVDevClientBuildPlan plan({
    String target = 'android',
    String host = 'linux',
    bool Function(String)? onPath,
    bool androidSdk = true,
  }) => dvDevClientBuildPlan(
    root: root.path,
    target: target,
    host: host,
    onPath: onPath ?? (_) => true,
    androidSdkInstalled: androidSdk,
  );

  test(
    'an Android shell builds the devclient flavor from its own entrypoint',
    () {
      final DVDevClientBuildPlan built = plan();

      expect(built.problems, isEmpty);
      expect(built.executable, 'flutter');
      expect(built.arguments.take(2), <String>['build', 'apk']);
      expect(
        built.arguments,
        containsAllInOrder(<String>['--flavor', 'devclient']),
      );
      expect(
        built.arguments,
        containsAllInOrder(<String>['-t', built.entrypointPath]),
      );
      expect(built.manifest.bindings, <String>[
        'dartvel_flutter@0.4.0',
        'plugin:jni',
      ]);
    },
  );

  test('the entrypoint carries the manifest, the marker, and no app code', () {
    final String source = plan().entrypointSource;

    expect(source, contains("'plugin:jni'"));
    expect(source, contains("'dartvel_flutter@0.4.0'"));
    expect(source, contains("target: 'android'"));
    expect(source, contains('package:dartvel_flutter/dev_client.dart'));
    expect(source, contains('DVAndroidBindings.register()'));
    // A shell holds no application code, so it cannot import the client.
    expect(source, isNot(contains('dartvel_client')));
    expect(source, isNot(contains('package:shopfront')));
  });

  test('iOS is refused off macOS before anything else is looked at', () {
    File(p.join(root.path, '.flutter-plugins-dependencies')).deleteSync();

    final DVDevClientBuildPlan built = plan(target: 'ios');

    expect(built.ok, isFalse);
    expect(built.problems, hasLength(1));
    expect(built.problems.single, contains('macOS'));
  });

  test('a store target with no flavor of its own is refused', () {
    // Without its own application id the shell installs over the real
    // application on the tester's phone.
    File(
      p.join(root.path, 'android', 'app', 'build.gradle.kts'),
    ).writeAsStringSync('android {}\n');

    final DVDevClientBuildPlan built = plan();

    expect(built.ok, isFalse);
    expect(built.problems.join(), contains('applicationIdSuffix'));
  });

  test('plugins nobody resolved are refused rather than recorded as none', () {
    File(p.join(root.path, '.flutter-plugins-dependencies')).deleteSync();

    final DVDevClientBuildPlan built = plan();

    expect(built.ok, isFalse);
    expect(built.problems.join(), contains('pub get'));
  });

  test('a missing Flutter is refused before generation', () {
    final DVDevClientBuildPlan built = plan(
      onPath: (String tool) => tool != 'flutter',
    );
    expect(built.ok, isFalse);
    expect(built.problems.join(), contains('flutter'));
  });

  test('a missing Android SDK is refused with instructions, not fetched', () {
    final DVDevClientBuildPlan built = plan(androidSdk: false);
    expect(built.ok, isFalse);
    expect(built.problems.join(), contains('Android SDK'));
  });

  test('desktop and embedded targets are refused: they take a launch flag', () {
    final DVDevClientBuildPlan built = plan(target: 'linux');
    expect(built.ok, isFalse);
    expect(built.problems.join(), contains('android'));
  });

  group('the command', () {
    late List<List<String>> ran;

    setUp(() {
      ran = <List<String>>[];
      exitCode = 0;
    });

    tearDown(() {
      exitCode = 0;
    });

    Future<void> build(List<String> args, {bool Function(String)? onPath}) =>
        (CommandRunner<void>('dartvel', 'test')..addCommand(
              BuildCommand(
                root: root.path,
                onPath: onPath ?? (_) => true,
                processRun:
                    (
                      String executable,
                      List<String> arguments, {
                      String? workingDirectory,
                      bool runInShell = false,
                    }) async {
                      ran.add(<String>[executable, ...arguments]);
                      return ProcessResult(0, 0, '', '');
                    },
              ),
            ))
            .run(<String>['build', ...args]);

    test('a refused plan runs nothing and writes nothing', () async {
      await build(<String>['dev-client', '--target', 'plan9']);

      expect(exitCode, isNot(0));
      expect(ran, isEmpty);
      expect(
        File(p.join(root.path, dvDevClientEntrypoint)).existsSync(),
        isFalse,
      );
    });

    test('no target is a usage error', () async {
      await build(<String>['dev-client']);

      expect(exitCode, 64);
      expect(ran, isEmpty);
    });
  });
}
