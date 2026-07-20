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

    test('maps TV and webOS platforms to supported Flutter build commands', () {
      expect(
        resolveFlutterBuildArguments(
          platform: 'webos',
          buildMode: '--release',
          obfuscate: true,
        ),
        <String>['build', 'web', '--release'],
      );

      expect(
        resolveFlutterBuildArguments(
          platform: 'tvos',
          buildMode: '--release',
        ),
        <String>['build', 'ios', '--release', '--no-codesign'],
      );
    });
  });
}
