// `dartvel build <target> --brownfield` extends Flutter's add-to-app rather
// than reimplementing it: the project is built as the artifact a native host
// embeds, through Flutter's own `build aar`, `build ios-framework` and
// `build macos-framework`, with an entry point per project that the host
// starts an engine at.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/build/brownfield.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('the entry point is named after the project', () {
    expect(dvBrownfieldEntryName('checkout'), 'dartvelEmbeddedEntry_checkout');
  });

  test('the entry source starts the runtime as an embedded entry, '
      'from main and from the named entry point', () {
    final String source = dvBrownfieldEntrySource('checkout');
    expect(source, contains("import 'package:checkout/dartvel_client/application.g.dart';"));
    expect(source, contains('void main() => dartvelRunEmbedded(\'checkout\');'));
    expect(source, contains("@pragma('vm:entry-point')"));
    expect(source,
        contains("void dartvelEmbeddedEntry_checkout() => dartvelRunEmbedded('checkout');"));
  });

  group('plan', () {
    test('android builds a release AAR from a staged module', () {
      final DVBrownfieldPlan plan =
          dvBrownfieldPlan(platform: 'android', package: 'checkout', buildMode: '--release');
      expect(plan.stagesModule, isTrue);
      expect(plan.flutterArguments,
          <String>['build', 'aar', '--no-debug', '--no-profile', '--release']);
      expect(plan.output, p.join('build', 'brownfield', 'android'));
    });

    test('ios and macos build frameworks with the entry as the target', () {
      for (final (String platform, String command) in <(String, String)>[
        ('ios', 'ios-framework'),
        ('macos', 'macos-framework'),
      ]) {
        final DVBrownfieldPlan plan =
            dvBrownfieldPlan(platform: platform, package: 'checkout', buildMode: '--release');
        expect(plan.flutterArguments.take(2), <String>['build', command], reason: platform);
        expect(plan.flutterArguments, containsAllInOrder(<String>['--target', dvBrownfieldEntryPath]),
            reason: platform);
        expect(plan.flutterArguments,
            containsAll(<String>['--no-debug', '--no-profile', '--release']), reason: platform);
        expect(plan.flutterArguments,
            containsAllInOrder(<String>['--output', p.join('build', 'brownfield', platform)]),
            reason: platform);
        expect(plan.needsMacHost, isTrue, reason: platform);
      }
    });

    test('a debug build asks Flutter for debug only', () {
      final DVBrownfieldPlan plan =
          dvBrownfieldPlan(platform: 'android', package: 'checkout', buildMode: '--debug');
      expect(plan.flutterArguments, <String>['build', 'aar', '--debug', '--no-profile', '--no-release']);
    });

    test('a target with no brownfield build yet is refused with the reason, '
        'never a plain build', () {
      for (final String platform in <String>['web', 'linux', 'windows', 'web-server', 'tizen']) {
        expect(
          () => dvBrownfieldPlan(platform: platform, package: 'checkout', buildMode: '--release'),
          throwsA(isA<DVBrownfieldRefusal>()
              .having((DVBrownfieldRefusal r) => r.message, 'message', contains(platform))),
          reason: platform,
        );
      }
    });
  });

  group('staging a module', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('brownfield_');
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: checkout
dependencies:
  flutter:
    sdk: flutter
  dartvel_flutter:
    path: ../packages/dartvel_flutter
flutter:
  uses-material-design: true
  assets:
    - assets/
''');
      Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
      File(p.join(root.path, 'lib', 'main.dart')).writeAsStringSync('void main() {}\n');
      File(p.join(root.path, 'lib', 'pages', 'index.dart')).writeAsStringSync('// page\n');
      Directory(p.join(root.path, 'assets')).createSync();
      Directory(p.join(root.path, 'android')).createSync();
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('the module keeps the package name, declares itself a module, '
        'and resolves path dependencies from where it stands', () {
      final Directory module = dvStageBrownfieldModule(root: root.path, package: 'checkout');
      expect(p.isWithin(p.join(root.path, 'build', 'brownfield'), module.path), isTrue);
      final String pubspec = File(p.join(module.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('name: checkout'));
      expect(pubspec, contains('  module:'));
      expect(pubspec, contains('    androidPackage: dev.dartvel.brownfield.checkout'));
      expect(pubspec, contains('    iosBundleIdentifier: dev.dartvel.brownfield.checkout'));
      expect(pubspec,
          contains('path: ${p.normalize(p.join(root.path, '..', 'packages', 'dartvel_flutter'))}'));
      expect(pubspec, contains('    - assets/'));
    });

    test('lib/main.dart is the embedded entry, and the rest of lib and the '
        'assets are the project\'s own files', () {
      final Directory module = dvStageBrownfieldModule(root: root.path, package: 'checkout');
      expect(File(p.join(module.path, 'lib', 'main.dart')).readAsStringSync(),
          dvBrownfieldEntrySource('checkout'));
      expect(File(p.join(root.path, 'lib', 'main.dart')).readAsStringSync(), 'void main() {}\n',
          reason: 'the project itself is never changed');
      expect(File(p.join(module.path, 'lib', 'pages', 'index.dart')).readAsStringSync(), '// page\n');
      expect(FileSystemEntity.isLinkSync(p.join(module.path, 'lib', 'pages')), isTrue);
      expect(FileSystemEntity.isLinkSync(p.join(module.path, 'assets')), isTrue);
      expect(Directory(p.join(module.path, 'android')).existsSync(), isFalse,
          reason: 'a module has its own ephemeral .android host');
    });

    test('a top-level file is copied, not linked, so a Flutter command run '
        'in the module cannot write into the project', () {
      File(p.join(root.path, 'analysis_options.yaml'))
          .writeAsStringSync('include: package:lints/recommended.yaml\n');
      final Directory module = dvStageBrownfieldModule(root: root.path, package: 'checkout');
      final String staged = p.join(module.path, 'analysis_options.yaml');
      expect(FileSystemEntity.isLinkSync(staged), isFalse);
      // Flutter's own analysis_options migration rewrites this file in
      // whatever project it runs in.
      File(staged).writeAsStringSync('rewritten by a tool\n');
      expect(File(p.join(root.path, 'analysis_options.yaml')).readAsStringSync(),
          'include: package:lints/recommended.yaml\n');
      expect(FileSystemEntity.isLinkSync(p.join(module.path, 'assets')), isTrue,
          reason: 'directories are still the project\'s own, linked');
    });

    test('staging twice starts from a clean module', () {
      dvStageBrownfieldModule(root: root.path, package: 'checkout');
      File(p.join(root.path, 'lib', 'extra.dart')).writeAsStringSync('// extra\n');
      final Directory module = dvStageBrownfieldModule(root: root.path, package: 'checkout');
      expect(File(p.join(module.path, 'lib', 'extra.dart')).existsSync(), isTrue);
    });
  });

  group('running', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('brownfield_run_');
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: checkout\nflutter:\n  uses-material-design: true\n');
      Directory(p.join(root.path, 'lib')).createSync();
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('android: resolves and builds in the staged module, then puts the '
        'Maven repository and the host notes in build/brownfield/android', () async {
      final List<String> calls = <String>[];
      final int code = await dvRunBrownfieldBuild(
        root: root.path,
        platform: 'android',
        buildMode: '--release',
        log: (_) {},
        run: (String executable, List<String> arguments, String directory) async {
          calls.add('$executable ${arguments.join(' ')} @ ${p.relative(directory, from: root.path)}');
          if (arguments.take(2).join(' ') == 'build aar') {
            final Directory repo = Directory(p.join(directory, 'build', 'host', 'outputs', 'repo'))
              ..createSync(recursive: true);
            File(p.join(repo.path, 'flutter_release-1.0.aar')).writeAsStringSync('aar');
          }
          return 0;
        },
      );
      expect(code, 0);
      expect(calls, <String>[
        'flutter pub get @ build/brownfield/module',
        'flutter build aar --no-debug --no-profile --release @ build/brownfield/module',
      ]);
      final String out = p.join(root.path, 'build', 'brownfield', 'android');
      expect(File(p.join(out, 'repo', 'flutter_release-1.0.aar')).existsSync(), isTrue);
      expect(File(p.join(out, 'HOST.md')).readAsStringSync(), contains('dartvelEmbeddedEntry_checkout'));
    });

    test('a failed Flutter build fails the brownfield build', () async {
      final int code = await dvRunBrownfieldBuild(
        root: root.path,
        platform: 'android',
        buildMode: '--release',
        log: (_) {},
        run: (String executable, List<String> arguments, String directory) async =>
            arguments.first == 'build' ? 1 : 0,
      );
      expect(code, isNot(0));
    });

    test('a refused target exits 69 without staging anything', () async {
      final List<String> logged = <String>[];
      final int code = await dvRunBrownfieldBuild(
        root: root.path,
        platform: 'linux',
        buildMode: '--release',
        log: logged.add,
        run: (_, __, ___) async => fail('nothing runs'),
      );
      expect(code, 69);
      expect(logged.join(), contains('linux'));
      expect(Directory(p.join(root.path, 'build')).existsSync(), isFalse);
    });
  });

  group('dartvel build --brownfield', () {
    Future<(List<String>, int)> build(List<String> arguments) async {
      final Directory temp = Directory.systemTemp.createTempSync('brownfield_cmd_');
      File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync('name: checkout\n');
      Directory(p.join(temp.path, 'lib')).createSync();
      final List<String> calls = <String>[];
      final BuildCommand command = BuildCommand(
        root: temp.path,
        preflight: (String platform, {bool? autoInstall}) async => true,
        processRun: (String executable, List<String> arguments,
            {String? workingDirectory, bool runInShell = false}) async {
          calls.add(<String>[executable, ...arguments].join(' '));
          return ProcessResult(0, 0, '', '');
        },
        hasBuildRunner: (String root) => false,
      );
      final int before = exitCode;
      try {
        await (CommandRunner<void>('dartvel', 'test')..addCommand(command))
            .run(<String>['build', ...arguments]);
        return (calls, exitCode);
      } finally {
        exitCode = before;
        temp.deleteSync(recursive: true);
      }
    }

    test('a refused target generates nothing and exits 69', () async {
      final (List<String> calls, int code) = await build(<String>['linux', '--brownfield']);
      expect(calls, isEmpty);
      expect(code, 69);
    });

    test('android generates the client, then builds the module', () async {
      final (List<String> calls, _) = await build(<String>['android', '--brownfield']);
      expect(calls.first, startsWith('dart run dartvel_cli:dartvel routes'));
      expect(calls.skip(1), <String>[
        'flutter pub get',
        'flutter build aar --no-debug --no-profile --release',
      ]);
    });
  });
}
