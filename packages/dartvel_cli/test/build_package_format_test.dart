// `dartvel build android --format aab` and `dartvel build ios --format ipa`:
// the two packages a store takes. An APK and an unsigned Runner.app are what
// a device installs; Google Play refuses the first and App Store Connect the
// second, so without these `dartvel publish play` and `appstore` had nothing
// to upload.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/cloud/cloud_build.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:test/test.dart';

class _RecordingCloud extends DVCloudBuilder {
  final List<DVCloudBuildRequest> requests = <DVCloudBuildRequest>[];

  @override
  Future<int> run(DVCloudBuildRequest request) async {
    requests.add(request);
    return 0;
  }
}

void main() {
  group('the Flutter command', () {
    test('an Android App Bundle is flutter build appbundle', () {
      final List<String> args = resolveFlutterBuildArguments(
        platform: 'android',
        buildMode: '--release',
        format: 'aab',
        splitPerAbi: true,
      );
      expect(args.take(3), <String>['build', 'appbundle', '--release']);
      // A bundle is split by Play per device; the flag is an APK's.
      expect(args, isNot(contains('--split-per-abi')));
    });

    test('an IPA is flutter build ipa, signed unless told otherwise', () {
      final List<String> signed = resolveFlutterBuildArguments(
        platform: 'ios',
        buildMode: '--release',
        format: 'ipa',
        exportOptionsPlist: 'ios/ExportOptions.plist',
      );
      expect(signed.take(3), <String>['build', 'ipa', '--release']);
      expect(signed, isNot(contains('--no-codesign')));
      expect(signed, isNot(contains('--simulator')));
      expect(signed, containsAllInOrder(<String>['--export-options-plist', 'ios/ExportOptions.plist']));

      final List<String> unsigned = resolveFlutterBuildArguments(
        platform: 'ios',
        buildMode: '--release',
        format: 'ipa',
        codesign: false,
      );
      expect(unsigned.take(2), <String>['build', 'ipa']);
      expect(unsigned, contains('--no-codesign'));
    });

    test('without a format, Android is still an APK and iOS still unsigned', () {
      expect(resolveFlutterBuildArguments(platform: 'android', buildMode: '--release')[1], 'apk');
      expect(resolveFlutterBuildArguments(platform: 'ios', buildMode: '--release'),
          containsAll(<String>['ios', '--no-codesign']));
    });
  });

  group('what the build refuses', () {
    test('a package format on the wrong target', () {
      expect(dvPackageFormatProblem(platform: 'ios', format: 'aab'), contains('android'));
      expect(dvPackageFormatProblem(platform: 'android', format: 'ipa'), contains('ios'));
      expect(dvPackageFormatProblem(platform: 'web', format: 'aab'), isNotNull);
    });

    test('an IPA for a simulator, which a store cannot take', () {
      expect(dvPackageFormatProblem(platform: 'ios', format: 'ipa', simulator: true), isNotNull);
    });

    test('signing options without an IPA to sign', () {
      expect(dvPackageFormatProblem(platform: 'ios', exportOptionsPlist: 'x.plist'), contains('--format ipa'));
      expect(dvPackageFormatProblem(platform: 'ios', codesign: false), contains('--format ipa'));
    });

    test('nothing when the combination makes sense', () {
      expect(dvPackageFormatProblem(platform: 'android', format: 'aab'), isNull);
      expect(dvPackageFormatProblem(platform: 'ios', format: 'ipa', codesign: false), isNull);
      expect(dvPackageFormatProblem(platform: 'ios', format: 'ipa', exportOptionsPlist: 'x.plist'), isNull);
      expect(dvPackageFormatProblem(platform: 'sony-elinux', format: 'iso'), isNull);
      expect(dvPackageFormatProblem(platform: 'android'), isNull);
    });

    test('a store package names where it is written', () {
      expect(dvPackageOutput(platform: 'android', format: 'aab', buildMode: '--release'),
          'build/app/outputs/bundle/release');
      expect(dvPackageOutput(platform: 'ios', format: 'ipa', buildMode: '--release'), 'build/ios/ipa');
      expect(dvPackageOutput(platform: 'ios', format: 'ipa', buildMode: '--release', codesign: false),
          'build/ios/archive');
    });
  });

  group('the command', () {
    late Directory root;
    late List<String> local;

    setUp(() {
      root = Directory.systemTemp.createTempSync('dartvel_build_format_');
      File('${root.path}/pubspec.yaml').writeAsStringSync('name: shop\n');
      local = <String>[];
      exitCode = 0;
    });

    tearDown(() {
      root.deleteSync(recursive: true);
      exitCode = 0;
    });

    Future<void> build(List<String> args, {DVCloudBuilder? cloud}) =>
        (CommandRunner<void>('dartvel', 'test')
              ..addCommand(BuildCommand(
                root: root.path,
                cloud: cloud,
                preflight: (String platform, {bool? autoInstall}) async {
                  local.add('preflight $platform');
                  return false;
                },
                processRun: (String executable, List<String> arguments,
                    {String? workingDirectory, bool runInShell = false}) async {
                  local.add(executable);
                  return ProcessResult(0, 0, '', '');
                },
              )))
            .run(<String>['build', ...args]);

    test('an App Bundle for iOS is refused before anything starts', () async {
      await build(<String>['ios', '--format', 'aab']);
      expect(exitCode, 64);
      expect(local, isEmpty);
    });

    test('a cloud build carries the format and the signing choice', () async {
      final _RecordingCloud cloud = _RecordingCloud();
      await build(<String>['ios', '--cloud', '--format', 'ipa', '--no-codesign'], cloud: cloud);
      expect(cloud.requests.single.format, 'ipa');
      expect(cloud.requests.single.codesign, isFalse);

      await build(<String>['android', '--cloud', '--format', 'aab'], cloud: cloud);
      expect(cloud.requests.last.format, 'aab');
      expect(cloud.requests.last.codesign, isTrue);
    });

    test('a cloud build refuses the same combinations', () async {
      final _RecordingCloud cloud = _RecordingCloud();
      await build(<String>['android', '--cloud', '--format', 'ipa'], cloud: cloud);
      expect(exitCode, 64);
      expect(cloud.requests, isEmpty);
    });
  });
}
