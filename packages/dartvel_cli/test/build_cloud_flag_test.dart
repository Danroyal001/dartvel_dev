// `dartvel build <target> --cloud` hands the build to the cloud before any of
// this machine's checks: iOS is refused on Linux here only because Xcode is
// not here, and the point of the flag is that it does not need to be.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/cloud/cloud_build.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:test/test.dart';

class _RecordingCloud extends DVCloudBuild {
  final List<DVCloudBuildRequest> requests = <DVCloudBuildRequest>[];

  @override
  Future<int> run(DVCloudBuildRequest request) async {
    requests.add(request);
    return 0;
  }
}

void main() {
  late Directory root;
  late _RecordingCloud cloud;
  late List<String> local;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_build_cloud_');
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: shop\n');
    cloud = _RecordingCloud();
    local = <String>[];
    exitCode = 0;
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    exitCode = 0;
  });

  Future<void> build(List<String> args) => (CommandRunner<void>('dartvel', 'test')
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

  test('builds iOS in the cloud without asking whether this host can', () async {
    await build(<String>['ios', '--cloud', '--profile', 'development']);
    expect(local, isEmpty);
    expect(cloud.requests, hasLength(1));
    expect(cloud.requests.single.target, 'ios');
    expect(cloud.requests.single.profile, 'development');
    expect(cloud.requests.single.root, root.path);
    expect(exitCode, 0);
  });

  test('refuses to put every target in the cloud at once', () async {
    await build(<String>['--cloud']);
    expect(cloud.requests, isEmpty);
    expect(local, isEmpty);
    expect(exitCode, 64);
  });

  test('the cloud build exit code is the command exit code', () async {
    final _FailingCloud failing = _FailingCloud();
    await (CommandRunner<void>('dartvel', 'test')
          ..addCommand(BuildCommand(root: root.path, cloud: failing)))
        .run(<String>['build', 'android', '--cloud']);
    expect(exitCode, 1);
  });
}

class _FailingCloud extends DVCloudBuild {
  @override
  Future<int> run(DVCloudBuildRequest request) async => 1;
}
