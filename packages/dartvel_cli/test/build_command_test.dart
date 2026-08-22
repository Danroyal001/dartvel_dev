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

  buildTimeoutTests();
  terminalRenderingTests();
  everyBuildPathIsBoundedTests();

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
      // The embedder's scripts locate their workspace through this variable
      // and refuse to run without it. Dartvel installed the checkout, so it
      // knows the answer and should not ask the developer to edit a profile.
      expect(plan.environment['FUCHSIA_EMBEDDER_DIR'],
          '/home/dev/.dartvel/toolchains/dartvel_fuchsia');
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

    test('defaults to x64, because that is the only engine the embedder ships',
        () {
      // --arch defaults to arm64 for TVs and embedded boards. Fuchsia has an
      // x64 prebuilt engine only, so inheriting that default made a plain
      // `dartvel build fuchsia` fail with "no arm64 engine in
      // src/embedder/engine/debug_arm64" without anyone choosing arm64.
      expect(resolveEmbeddedArch('fuchsia', 'arm64'), 'x64');
      expect(resolveEmbeddedArch('tizen', 'arm64'), 'arm64');
      expect(resolveEmbeddedArch('sony-elinux', 'arm64'), 'arm64');
    });

    test('an explicit --arch still wins, engine present or not', () {
      // Someone who has built an arm64 engine should be able to use it, and
      // the embedder says so clearly enough if they have not.
      expect(resolveEmbeddedArch('fuchsia', 'arm64', explicit: true), 'arm64');
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

// Appended: a build that hangs is worse than one that fails, because it is
// indistinguishable from a slow one and keeps costing until something else
// stops it. A macOS build once ran 41 minutes producing nothing at all.
void buildTimeoutTests() {
  group('build timeout', () {
    test('defaults to a generous but finite limit', () {
      // Generous because a clean release build on a cold cache is genuinely
      // slow; finite because nothing else here notices a stall.
      expect(parseBuildTimeout(null), const Duration(minutes: 45));
      expect(parseBuildTimeout(''), const Duration(minutes: 45));
      expect(parseBuildTimeout('   '), const Duration(minutes: 45));
    });

    test('an explicit number of minutes is honoured', () {
      expect(parseBuildTimeout('90'), const Duration(minutes: 90));
      expect(parseBuildTimeout(' 5 '), const Duration(minutes: 5));
    });

    test('zero disables the limit rather than meaning instantly', () {
      // The obvious wrong reading of 0 would kill every build immediately.
      expect(parseBuildTimeout('0'), isNull);
    });

    test('a value that is not minutes is refused, not silently defaulted', () {
      // Silently falling back would turn a typo into a limit nobody chose.
      expect(() => parseBuildTimeout('soon'), throwsFormatException);
      expect(() => parseBuildTimeout('-1'), throwsFormatException);
      expect(() => parseBuildTimeout('1.5'), throwsFormatException);
    });
  });
}

// Written before the fix. Every path that starts a long-running child process
// must be bounded, not just the Flutter one: an embedded build that wedges is
// indistinguishable from a slow one and runs to whatever cap it was given.
// Two Windows attempts burned 257 and 226 minutes producing no output.
void everyBuildPathIsBoundedTests() {
  group('every build path is bounded', () {
    test('the embedded build path awaits its child through the same guard',
        () {
      // Asserting on behaviour is not possible without spawning a real
      // embedder, so this asserts the structural property that makes the
      // behaviour possible: no build path may await a raw exitCode.
      final source = File('lib/src/commands/build_command.dart')
          .readAsStringSync();

      // The guard itself is where exitCode is legitimately awaited, so its
      // own body is excluded — everything else awaiting a raw exitCode is a
      // path that can hang forever.
      final guardStart = source.indexOf('Future<int?> _awaitBuild(');
      expect(guardStart, greaterThan(0), reason: 'the guard must exist');
      // From the body, not the declaration: the parameter list closes with
      // `}) async {`, which also matches a method-closing brace.
      final guardBody = source.indexOf('async {', guardStart);
      final guardEnd = source.indexOf('\n  }', guardBody);
      final outsideGuard =
          source.substring(0, guardStart) + source.substring(guardEnd);

      final unguarded = RegExp(r'await\s+[A-Za-z_][A-Za-z0-9_]*\.exitCode\b')
          .allMatches(outsideGuard)
          .map((m) => m.group(0))
          .toList();
      expect(
        unguarded,
        isEmpty,
        reason: 'a child process awaited directly cannot be timed out; '
            'route it through _awaitBuild',
      );
    });

    test('the scaffold generation step is bounded too', () {
      // Generating an embedder scaffold shells out to the vendor CLI, which
      // is exactly the kind of process that has hung before.
      final source = File('lib/src/commands/build_command.dart')
          .readAsStringSync();
      final scaffoldSection = source.substring(
        source.indexOf('Could not generate the'),
      );
      expect(
        scaffoldSection.contains('.exitCode.timeout') ||
            source.contains('_awaitBuild'),
        isTrue,
        reason: 'scaffold generation must not be able to hang indefinitely',
      );
    });
  });
}

// Terminal rendering, step one: resolving the target and refusing to link a
// backend nobody asked for. Written against the spec's table, before any of it
// exists.
//
// | dartvel build linux                    | GUI yes | terminal no  |
// | dartvel build linux + dartvel.terminal | GUI yes | terminal yes |
// | dartvel build linux-cli / linux-tui    | GUI no  | terminal yes |
void terminalRenderingTests() {
  group('terminal target resolution', () {
    test('-cli resolves to the base platform with a terminal presentation',
        () {
      // A presentation, not a platform: linux-cli is still the linux target.
      final resolved = normalizeBuildTarget('linux-cli');
      expect(resolved.platform, 'linux');
      expect(resolved.format, 'tui');
    });

    test('-tui is the same target under another name', () {
      // -tui says what it does, -cli says where it runs.
      expect(normalizeBuildTarget('linux-tui'),
          equals(normalizeBuildTarget('linux-cli')));
    });

    test('every desktop target and fuchsia accept the suffix', () {
      for (final platform in <String>['linux', 'windows', 'macos', 'fuchsia']) {
        for (final suffix in <String>['cli', 'tui']) {
          final resolved = normalizeBuildTarget('$platform-$suffix');
          expect(resolved.platform, platform, reason: '$platform-$suffix');
          expect(resolved.format, 'tui', reason: '$platform-$suffix');
        }
      }
    });

    test('a plain target is unchanged', () {
      // The regression that matters: adding a suffix must not alter the
      // meaning of the targets that already worked.
      expect(normalizeBuildTarget('linux').platform, 'linux');
      expect(normalizeBuildTarget('linux').format, isNull);
      expect(normalizeBuildTarget('sony-elinux-iso').format, 'iso');
      expect(normalizeBuildTarget('tpk').platform, 'tizen');
    });

    test('the suffixes are accepted arguments', () {
      for (final target in <String>[
        'linux-cli',
        'linux-tui',
        'windows-cli',
        'macos-tui',
        'fuchsia-cli',
      ]) {
        expect(buildPlatformArguments, contains(target));
      }
    });

    test('a suffix on a target that cannot render in a terminal is refused',
        () {
      // Not because Android has no terminal — Termux is one. Because a
      // linux-cli binary cannot run there: Termux is Android userland, so it
      // uses bionic rather than glibc and has no /lib/ld-linux-aarch64.so.1
      // to load a linux-gnu binary with. Supporting it would mean an
      // Android-triple build and an engine that runs without an Activity,
      // which is a project rather than a suffix.
      //
      // Accepting the suffix and quietly building something else would be
      // worse than refusing it.
      expect(() => normalizeBuildTarget('android-cli'), throwsFormatException);
      expect(() => normalizeBuildTarget('web-tui'), throwsFormatException);
    });
  });

  group('terminal backend selection', () {
    test('a plain desktop build links no terminal backend', () {
      // The default, and the one that must not regress: an application that
      // said nothing pays nothing.
      final backends = resolveRenderBackends(
        format: null,
        terminalOptIn: false,
      );
      expect(backends, <DVRenderBackend>{DVRenderBackend.gui});
    });

    test('opting in adds the terminal backend without removing the GUI', () {
      final backends = resolveRenderBackends(
        format: null,
        terminalOptIn: true,
      );
      expect(backends, <DVRenderBackend>{
        DVRenderBackend.gui,
        DVRenderBackend.terminal,
      });
    });

    test('a terminal-only build links no GUI backend at all', () {
      // Not a window that stays closed. Nothing.
      final backends = resolveRenderBackends(
        format: 'tui',
        terminalOptIn: false,
      );
      expect(backends, <DVRenderBackend>{DVRenderBackend.terminal});
    });

    test('a terminal-only build ignores the opt-in rather than adding a GUI',
        () {
      // Asking for a terminal build is the stronger statement; the pubspec key
      // enables a mode, it does not add one back.
      final backends = resolveRenderBackends(
        format: 'tui',
        terminalOptIn: true,
      );
      expect(backends, <DVRenderBackend>{DVRenderBackend.terminal});
    });
  });
}
