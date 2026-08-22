import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('resolveFlutterBuildArguments', () {
    test('uses supported web flags for current Flutter SDKs', () {
      final args = resolveFlutterBuildArguments(
        platform: 'web',
        buildMode: '--release',
        obfuscate: true,
        treeShakeIcons: true,
      );

      expect(args, <String>[
        'build',
        'web',
        '--release',
        '--tree-shake-icons',
      ]);
      expect(args, isNot(contains('--obfuscate')));
      expect(args, isNot(contains('--web-renderer')));
    });

    test('maps Android-family platforms to apk builds', () {
      expect(
        resolveFlutterBuildArguments(
          platform: 'android',
          buildMode: '--release',
          splitPerAbi: true,
          obfuscate: true,
        ),
        <String>[
          'build',
          'apk',
          '--release',
          '--obfuscate',
          '--split-debug-info',
          'build/debug-info',
          '--split-per-abi',
        ],
      );

      expect(
        resolveFlutterBuildArguments(
          platform: 'fireos',
          buildMode: '--release',
        ),
        <String>['build', 'apk', '--release'],
      );
    });

    test('tvOS is not a Flutter build platform in disguise', () {
      // `flutter build ios` produces an iPhone app whatever the caller names
      // it; tvOS belongs to the flutter-tvos embedder.
      expect(flutterBuildPlatforms, isNot(contains('tvos')));
      expect(embeddedBuildPlatforms, contains('tvos'));
    });
  });

  group('normalizeBuildTarget', () {
    test('splits Sony eLinux distribution targets into platform + format', () {
      expect(
        normalizeBuildTarget('sony-elinux-iso'),
        (platform: 'sony-elinux', format: 'iso'),
      );
      expect(
        normalizeBuildTarget('sony-elinux-img'),
        (platform: 'sony-elinux', format: 'img'),
      );
    });

    test('passes non-distribution targets through with a null format', () {
      expect(
        normalizeBuildTarget('sony-elinux'),
        (platform: 'sony-elinux', format: null),
      );
      expect(
        normalizeBuildTarget('all'),
        (platform: 'all', format: null),
      );
    });

    test('aliases tpk to the tizen target', () {
      expect(
        normalizeBuildTarget('tpk'),
        (platform: 'tizen', format: null),
      );
    });
  });

  group('resolveEmbeddedBuildPlan', () {
    test('builds Tizen through flutter-tizen', () {
      final plan = resolveEmbeddedBuildPlan(
        platform: 'tizen',
        buildMode: '--release',
        arch: 'arm64',
        deviceProfile: 'lobby-display',
      );

      expect(plan, isNotNull);
      expect(plan!.executable, 'flutter-tizen');
      expect(plan.arguments, <String>[
        'build',
        'tpk',
        '--release',
        '--device-profile',
        'lobby-display',
      ]);
    });

    test('builds Sony eLinux through flutter-elinux with target arch', () {
      final plan = resolveEmbeddedBuildPlan(
        platform: 'sony-elinux',
        buildMode: '--release',
        arch: 'arm64',
      );

      expect(plan, isNotNull);
      expect(plan!.executable, 'flutter-elinux');
      expect(plan.arguments, <String>[
        'build',
        'elinux',
        '--release',
        '--target-arch',
        'arm64',
      ]);
    });

    test('builds webOS through flutter-webos (LG embedder)', () {
      final plan = resolveEmbeddedBuildPlan(
        platform: 'webos',
        buildMode: '--release',
        arch: 'arm64',
        deviceProfile: 'lg-tv',
      );

      expect(plan, isNotNull);
      expect(plan!.executable, 'flutter-webos');
      expect(plan.arguments, <String>[
        'build',
        'webos',
        '--release',
        '--device-profile',
        'lg-tv',
      ]);
    });

    test('builds tvOS through flutter-tvos (community embedder)', () {
      final plan = resolveEmbeddedBuildPlan(
        platform: 'tvos',
        buildMode: '--release',
        arch: 'arm64',
      );

      expect(plan, isNotNull);
      expect(plan!.executable, 'flutter-tvos');
      expect(plan.arguments, <String>['build', 'tvos', '--release']);
    });

    test('tvOS simulator builds are debug: the only unsigned path is JIT', () {
      // A release/profile device build requires a configured Xcode signing
      // team; the embedder accepts --simulator only with a debug build.
      final plan = resolveEmbeddedBuildPlan(
        platform: 'tvos',
        buildMode: '--release',
        arch: 'arm64',
        deviceProfile: 'simulator',
      );

      expect(plan, isNotNull);
      expect(plan!.executable, 'flutter-tvos');
      expect(plan.arguments, <String>['build', 'tvos', '--debug', '--simulator']);
    });

    test('embedders that need a platform directory carry how to make one', () {
      // Each of these refuses to build a project with no platform directory
      // ("This project is not configured for <platform>"). The directory is
      // generated output, so the plan carries the command that generates it.
      final expected = <String, String>{
        'tizen': 'tizen',
        'sony-elinux': 'elinux',
        'webos': 'webos',
        'tvos': 'tvos',
      };
      expected.forEach((platform, directory) {
        final plan = resolveEmbeddedBuildPlan(
          platform: platform,
          buildMode: '--release',
          arch: 'arm64',
        );
        expect(plan!.scaffoldDirectory, directory,
            reason: '$platform needs $directory/');
        expect(plan.scaffoldArguments.first, 'create',
            reason: '$platform scaffold must be generated by the embedder');
      });
    });

    test('Fuchsia has no scaffold: it stages the app into a Bazel workspace',
        () {
      final plan = resolveEmbeddedBuildPlan(
        platform: 'fuchsia',
        buildMode: '--release',
        arch: 'x64',
      );

      expect(plan, isNotNull);
      expect(plan!.scaffoldDirectory, isNull);
    });

    test('returns null for non-embedded platforms', () {
      expect(
        resolveEmbeddedBuildPlan(
          platform: 'android',
          buildMode: '--release',
          arch: 'arm64',
        ),
        isNull,
      );
    });
  });

  group('allBuildPlatforms', () {
    test('includes embedded/TV embedders but not distribution images', () {
      expect(allBuildPlatforms, contains('tizen'));
      expect(allBuildPlatforms, contains('sony-elinux'));
      expect(allBuildPlatforms, contains('webos'));
      expect(allBuildPlatforms, contains('vscode'));
      expect(allBuildPlatforms, isNot(contains('sony-elinux-iso')));
      expect(allBuildPlatforms, isNot(contains('sony-elinux-img')));
    });

    test('routes webOS through the embedded embedder, not flutter build web',
        () {
      expect(flutterBuildPlatforms, isNot(contains('webos')));
      expect(embeddedBuildPlatforms, contains('webos'));
    });
  });

  group('resolveRequestedPlatform', () {
    String resolve(List<String> positional,
            {String option = 'all', bool wasParsed = false}) =>
        resolveRequestedPlatform(
          positional: positional,
          optionValue: option,
          optionWasParsed: wasParsed,
        );

    test('honours the documented positional form', () {
      // Regression: `dartvel build web` used to ignore the argument entirely
      // and build every platform.
      expect(resolve(['web']), 'web');
      expect(resolve(['tizen']), 'tizen');
      expect(resolve(['webos']), 'webos');
      expect(resolve(['sony-elinux']), 'sony-elinux');
      expect(resolve(['vscode']), 'vscode');
    });

    test('accepts alias and distribution target names positionally', () {
      expect(resolve(['tpk']), 'tpk');
      expect(resolve(['sony-elinux-iso']), 'sony-elinux-iso');
      expect(resolve(['sony-elinux-img']), 'sony-elinux-img');
    });

    test('falls back to the option when nothing is positional', () {
      expect(resolve([]), 'all');
      expect(resolve([], option: 'android', wasParsed: true), 'android');
    });

    test('allows the positional and option forms to agree', () {
      expect(resolve(['web'], option: 'web', wasParsed: true), 'web');
    });

    test('rejects an unknown platform instead of building everything', () {
      expect(() => resolve(['wbe']), throwsFormatException);
    });

    test('rejects conflicting positional and option platforms', () {
      expect(
        () => resolve(['web'], option: 'android', wasParsed: true),
        throwsFormatException,
      );
    });

    test('rejects more than one positional platform', () {
      expect(() => resolve(['web', 'android']), throwsFormatException);
    });
  });

  group('isPlatformAvailableOn', () {
    test('does not claim desktop targets cross-compile', () {
      // Regression: `windows` claimed availability on Linux, so
      // `dartvel build windows` hard-failed there instead of skipping.
      expect(isPlatformAvailableOn('windows', 'linux'), isFalse);
      expect(isPlatformAvailableOn('windows', 'macos'), isFalse);
      expect(isPlatformAvailableOn('linux', 'macos'), isFalse);
      expect(isPlatformAvailableOn('linux', 'windows'), isFalse);
    });

    test('builds each desktop target on its own host', () {
      expect(isPlatformAvailableOn('windows', 'windows'), isTrue);
      expect(isPlatformAvailableOn('linux', 'linux'), isTrue);
      expect(isPlatformAvailableOn('macos', 'macos'), isTrue);
    });

    test('gates the Apple targets on macOS', () {
      for (final platform in ['ios', 'macos', 'tvos']) {
        expect(isPlatformAvailableOn(platform, 'macos'), isTrue);
        expect(isPlatformAvailableOn(platform, 'linux'), isFalse);
        expect(isPlatformAvailableOn(platform, 'windows'), isFalse);
      }
    });

    test('treats web and the Android family as host-independent', () {
      for (final host in ['linux', 'macos', 'windows']) {
        expect(isPlatformAvailableOn('web', host), isTrue);
        expect(isPlatformAvailableOn('android', host), isTrue);
        expect(isPlatformAvailableOn('fireos', host), isTrue);
      }
    });

    test('reports embedder targets as unavailable to the Flutter path', () {
      // Embedded targets route through _buildEmbedded, which checks for the
      // embedder executable instead.
      for (final platform in embeddedBuildPlatforms) {
        expect(isPlatformAvailableOn(platform, 'linux'), isFalse);
      }
    });
  });

  group('validateVSCodeArtifacts', () {
    test('requires extension JavaScript and Flutter webview assets', () {
      final temp = Directory.systemTemp.createTempSync('dartvel_vscode_test_');
      try {
        final buildStartedAt = DateTime.now();
        var validation =
            validateVSCodeArtifacts(temp.path, since: buildStartedAt);
        expect(validation.isValid, isFalse);
        expect(
          validation.missing,
          containsAll(<String>[
            'compiled extension host JavaScript under out/ or dist/',
            'build/web/flutter_bootstrap.js',
            'build/web/assets/',
          ]),
        );

        Directory('${temp.path}/out').createSync();
        File('${temp.path}/out/extension.js').writeAsStringSync('compiled');
        Directory('${temp.path}/build/web/assets').createSync(recursive: true);
        File('${temp.path}/build/web/assets/AssetManifest.json')
            .writeAsStringSync('{}');
        File('${temp.path}/build/web/flutter_bootstrap.js')
            .writeAsStringSync('boot');

        validation = validateVSCodeArtifacts(temp.path, since: buildStartedAt);
        expect(validation.isValid, isTrue);
        expect(validation.missing, isEmpty);
      } finally {
        temp.deleteSync(recursive: true);
      }
    });

    test('rejects stale artifacts from a previous build', () {
      final temp = Directory.systemTemp.createTempSync('dartvel_vscode_test_');
      try {
        Directory('${temp.path}/out').createSync();
        final extension = File('${temp.path}/out/extension.js')
          ..writeAsStringSync('old');
        Directory('${temp.path}/build/web/assets').createSync(recursive: true);
        final asset = File('${temp.path}/build/web/assets/AssetManifest.json')
          ..writeAsStringSync('{}');
        final bootstrap = File('${temp.path}/build/web/flutter_bootstrap.js')
          ..writeAsStringSync('boot');
        final oldTime = DateTime(2000);
        extension.setLastModifiedSync(oldTime);
        asset.setLastModifiedSync(oldTime);
        bootstrap.setLastModifiedSync(oldTime);

        final validation = validateVSCodeArtifacts(
          temp.path,
          since: DateTime(2026),
        );

        expect(validation.isValid, isFalse);
        expect(
          validation.missing,
          containsAll(<String>[
            'compiled extension host JavaScript under out/ or dist/',
            'build/web/flutter_bootstrap.js',
            'build/web/assets/',
          ]),
        );
      } finally {
        temp.deleteSync(recursive: true);
      }
    });
  });

  group('BuildCommand', () {
    test('skips generation when target preflight skips every platform',
        () async {
      final temp = Directory.systemTemp.createTempSync('dartvel_build_test_');
      final oldCurrent = Directory.current;
      final processInvocations = <String>[];
      final preflightPlatforms = <String>[];
      final command = BuildCommand(
        preflight: (String platform, {bool? autoInstall}) async {
          preflightPlatforms.add(platform);
          return false;
        },
        processRun: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          bool runInShell = false,
        }) async {
          processInvocations.add(<String>[executable, ...arguments].join(' '));
          return ProcessResult(0, 0, '', '');
        },
        hasBuildRunner: (String root) => true,
      );
      final runner = CommandRunner<void>('dartvel', 'test')
        ..addCommand(command);

      try {
        Directory.current = temp;
        await runner.run(<String>['build', 'windows']);
      } finally {
        Directory.current = oldCurrent;
        temp.deleteSync(recursive: true);
      }

      expect(preflightPlatforms, <String>['windows']);
      expect(processInvocations, isEmpty);
    });

    test('generates routes before running build_runner', () async {
      final temp = Directory.systemTemp.createTempSync('dartvel_build_test_');
      final oldCurrent = Directory.current;
      final processInvocations = <String>[];
      final command = BuildCommand(
        preflight: (String platform, {bool? autoInstall}) async => true,
        processRun: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          bool runInShell = false,
        }) async {
          processInvocations.add(<String>[executable, ...arguments].join(' '));
          return ProcessResult(0, 0, '', '');
        },
        hasBuildRunner: (String root) => true,
      );
      final runner = CommandRunner<void>('dartvel', 'test')
        ..addCommand(command);

      try {
        Directory.current = temp;
        await runner.run(<String>['build', 'windows']);
      } finally {
        Directory.current = oldCurrent;
        temp.deleteSync(recursive: true);
      }

      expect(processInvocations, <String>[
        'dart run dartvel_cli:dartvel routes',
        'dart run build_runner build --delete-conflicting-outputs',
      ]);
    });

    test('builds vscode extension after dartvel generation', () async {
      final temp = Directory.systemTemp.createTempSync('dartvel_build_test_');
      final oldCurrent = Directory.current;
      final oldExitCode = exitCode;
      final processInvocations = <String>[];
      final command = BuildCommand(
        preflight: (String platform, {bool? autoInstall}) async => true,
        processRun: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          bool runInShell = false,
        }) async {
          processInvocations.add(<String>[executable, ...arguments].join(' '));
          if (executable == 'npm' &&
              arguments.length == 2 &&
              arguments[0] == 'run' &&
              arguments[1] == 'compile') {
            final root = workingDirectory ?? Directory.current.path;
            Directory('$root/out').createSync(recursive: true);
            File('$root/out/extension.js').writeAsStringSync('compiled');
            Directory('$root/build/web/assets').createSync(recursive: true);
            File('$root/build/web/assets/AssetManifest.json')
                .writeAsStringSync('{}');
            File('$root/build/web/flutter_bootstrap.js')
                .writeAsStringSync('boot');
          }
          return ProcessResult(0, 0, '', '');
        },
        hasBuildRunner: (String root) => true,
      );
      final runner = CommandRunner<void>('dartvel', 'test')
        ..addCommand(command);
      int? observedExitCode;

      try {
        Directory.current = temp;
        File('pubspec.yaml').writeAsStringSync('''
name: vscode_app
dependencies:
  flutter_vscode: ^0.0.1
dev_dependencies:
  build_runner: ^2.5.4
''');
        await runner.run(<String>['build', 'vscode']);
        observedExitCode = exitCode;
      } finally {
        Directory.current = oldCurrent;
        temp.deleteSync(recursive: true);
        exitCode = oldExitCode;
      }

      expect(observedExitCode, oldExitCode);
      expect(processInvocations, <String>[
        'dart run dartvel_cli:dartvel routes',
        'dart run build_runner build --delete-conflicting-outputs',
        'dart run flutter_vscode:generate_vscode_extension',
        'flutter pub get',
        'npm install',
        'npm run compile',
      ]);
    });

    test('vscode build fails before scaffold commands without build_runner',
        () async {
      final temp = Directory.systemTemp.createTempSync('dartvel_build_test_');
      final oldCurrent = Directory.current;
      final oldExitCode = exitCode;
      final processInvocations = <String>[];
      final command = BuildCommand(
        preflight: (String platform, {bool? autoInstall}) async => true,
        processRun: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          bool runInShell = false,
        }) async {
          processInvocations.add(<String>[executable, ...arguments].join(' '));
          return ProcessResult(0, 0, '', '');
        },
        hasBuildRunner: (String root) => false,
      );
      final runner = CommandRunner<void>('dartvel', 'test')
        ..addCommand(command);

      try {
        Directory.current = temp;
        File('pubspec.yaml').writeAsStringSync('''
name: vscode_app
dependencies:
  flutter_vscode: ^0.0.1
''');
        await runner.run(<String>['build', 'vscode']);
        expect(exitCode, 1);
      } finally {
        Directory.current = oldCurrent;
        temp.deleteSync(recursive: true);
        exitCode = oldExitCode;
      }

      expect(processInvocations, <String>[
        'dart run dartvel_cli:dartvel routes',
      ]);
    });

    test('vscode build fails when compile exits without artifacts', () async {
      final temp = Directory.systemTemp.createTempSync('dartvel_build_test_');
      final oldCurrent = Directory.current;
      final oldExitCode = exitCode;
      final processInvocations = <String>[];
      final command = BuildCommand(
        preflight: (String platform, {bool? autoInstall}) async => true,
        processRun: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          bool runInShell = false,
        }) async {
          processInvocations.add(<String>[executable, ...arguments].join(' '));
          return ProcessResult(0, 0, '', '');
        },
        hasBuildRunner: (String root) => true,
      );
      final runner = CommandRunner<void>('dartvel', 'test')
        ..addCommand(command);

      try {
        Directory.current = temp;
        File('pubspec.yaml').writeAsStringSync('''
name: vscode_app
dependencies:
  flutter_vscode: ^0.0.1
dev_dependencies:
  build_runner: ^2.5.4
''');
        await runner.run(<String>['build', 'vscode']);
        expect(exitCode, 1);
      } finally {
        Directory.current = oldCurrent;
        temp.deleteSync(recursive: true);
        exitCode = oldExitCode;
      }

      expect(processInvocations, <String>[
        'dart run dartvel_cli:dartvel routes',
        'dart run build_runner build --delete-conflicting-outputs',
        'dart run flutter_vscode:generate_vscode_extension',
        'flutter pub get',
        'npm install',
        'npm run compile',
      ]);
    });

    test('vscode build fails before scaffold commands without flutter_vscode',
        () async {
      final temp = Directory.systemTemp.createTempSync('dartvel_build_test_');
      final oldCurrent = Directory.current;
      final oldExitCode = exitCode;
      final processInvocations = <String>[];
      final command = BuildCommand(
        preflight: (String platform, {bool? autoInstall}) async => true,
        processRun: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          bool runInShell = false,
        }) async {
          processInvocations.add(<String>[executable, ...arguments].join(' '));
          return ProcessResult(0, 0, '', '');
        },
        hasBuildRunner: (String root) => false,
      );
      final runner = CommandRunner<void>('dartvel', 'test')
        ..addCommand(command);

      try {
        Directory.current = temp;
        File('pubspec.yaml').writeAsStringSync('''
name: vscode_app
dependencies:
  flutter:
    sdk: flutter
''');
        await runner.run(<String>['build', 'vscode']);
      } finally {
        Directory.current = oldCurrent;
        temp.deleteSync(recursive: true);
        exitCode = oldExitCode;
      }

      expect(processInvocations, <String>[
        'dart run dartvel_cli:dartvel routes',
      ]);
    });
  });

  group('fuchsia', () {
    test('is an embedded target, not a Flutter-path one', () {
      expect(embeddedBuildPlatforms, contains('fuchsia'));
      expect(isPlatformAvailableOn('fuchsia', 'linux'), isFalse);
    });

    test('its embedder builds on Linux only', () {
      // The embedder's own README states it cannot be built on macOS or
      // Windows natively, so those hosts skip rather than fail mid-build.
      expect(embeddedHostRequirement('fuchsia'), 'linux');
      expect(embeddedHostRequirement('tizen'), isNull);
      expect(embeddedHostRequirement('webos'), isNull);
      expect(embeddedHostRequirement('sony-elinux'), isNull);
    });

    test('the build plan drives the embedder script, not a flutter wrapper',
        () {
      // Unlike flutter-tizen or flutter-webos there is no embedder binary:
      // the Fuchsia embedder is a Bazel workspace with its own script.
      final plan = resolveEmbeddedBuildPlan(
        platform: 'fuchsia',
        buildMode: '--release',
        arch: 'x64',
        appPath: '/work/my_app',
        toolchainHome: '/home/dev',
      );

      expect(plan, isNotNull);
      // An absolute path into the checkout, not a bare name. This test used to
      // assert the name `dartvel_fuchsia` — which is nothing that is ever
      // installed, so the build could only ever skip. The plan was shaped
      // right and unrunnable, and asserting the shape did not catch it.
      expect(plan!.executable,
          '/home/dev/.dartvel/toolchains/dartvel_fuchsia/$fuchsiaAppBuildScript');
      expect(p.isAbsolute(plan.executable), isTrue);
      expect(plan.arguments, containsAllInOrder(<String>['--cpu', 'x64']));
    });

    test('the app is passed by path, so nothing Dartvel-specific is handed '
        'to the embedder', () {
      // A Dartvel app is an ordinary Flutter package. The embedder stays a
      // general one: the same script serves a plain `flutter create` app.
      final plan = resolveEmbeddedBuildPlan(
        platform: 'fuchsia',
        buildMode: '--release',
        arch: 'x64',
        appPath: '/work/my_app',
        toolchainHome: '/home/dev',
      );

      expect(plan!.arguments, contains('/work/my_app'));
      expect(plan.arguments.join(' '), isNot(contains('dartvel_app')));
    });

    test('an arm64 build asks the embedder for arm64', () {
      final plan = resolveEmbeddedBuildPlan(
        platform: 'fuchsia',
        buildMode: '--release',
        arch: 'arm64',
        appPath: '/work/my_app',
      );

      expect(plan!.arguments, containsAllInOrder(<String>['--cpu', 'arm64']));
    });
  });
}
