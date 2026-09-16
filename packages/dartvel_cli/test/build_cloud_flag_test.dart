// `dartvel build <target> --cloud` hands the build to Dartvel Cloud before any
// of this machine's checks: iOS is refused on Linux here only because Xcode is
// not here, and the point of the flag is that it does not need to be.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/cloud/cloud_build.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:test/test.dart';

class _RecordingCloud extends DVCloudBuilder {
  _RecordingCloud([this.code = 0]);

  final int code;
  final List<DVCloudBuildRequest> requests = <DVCloudBuildRequest>[];

  @override
  Future<int> run(DVCloudBuildRequest request) async {
    requests.add(request);
    return code;
  }
}

void main() {
  late Directory root;
  late List<String> local;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_build_cloud_');
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: shop\n');
    local = <String>[];
    exitCode = 0;
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    exitCode = 0;
  });

  Future<void> build(_RecordingCloud cloud, List<String> args) =>
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

  test('builds iOS in the cloud without asking whether this host can', () async {
    final _RecordingCloud cloud = _RecordingCloud();
    await build(cloud, <String>['ios', '--cloud', '--profile', 'development', '--cloud-token', 'tok']);
    expect(local, isEmpty);
    final DVCloudBuildRequest request = cloud.requests.single;
    expect(request.target, 'ios');
    expect(request.profile, 'development');
    expect(request.root, root.path);
    expect(request.token, 'tok');
    expect(exitCode, 0);
  });

  test('refuses to put every target in the cloud at once', () async {
    final _RecordingCloud cloud = _RecordingCloud();
    await build(cloud, <String>['--cloud']);
    expect(cloud.requests, isEmpty);
    expect(local, isEmpty);
    expect(exitCode, 64);
  });

  test('the cloud build exit code is the command exit code', () async {
    await build(_RecordingCloud(77), <String>['android', '--cloud']);
    expect(exitCode, 77);
  });
}
