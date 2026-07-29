import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
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

    test('maps TV platforms to supported Flutter build commands', () {
      expect(
        resolveFlutterBuildArguments(
          platform: 'tvos',
          buildMode: '--release',
        ),
        <String>['build', 'ios', '--release', '--no-codesign'],
      );
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
      } finally {
        Directory.current = oldCurrent;
        temp.deleteSync(recursive: true);
      }

      expect(processInvocations, <String>[
        'dart run dartvel_cli:dartvel routes',
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
}
