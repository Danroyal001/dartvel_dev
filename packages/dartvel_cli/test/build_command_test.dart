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
      expect(allBuildPlatforms, isNot(contains('sony-elinux-iso')));
      expect(allBuildPlatforms, isNot(contains('sony-elinux-img')));
    });

    test('routes webOS through the embedded embedder, not flutter build web',
        () {
      expect(flutterBuildPlatforms, isNot(contains('webos')));
      expect(embeddedBuildPlatforms, contains('webos'));
    });
  });
}
