// `dartvel publish <store> --cloud`: the build and the upload in one run on
// the repository's own Actions. Only what the runner can really finish is
// dispatched; the rest is refused here, before a runner starts.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/cloud/cloud_build.dart';
import 'package:dartvel_cli/src/commands/publish_command.dart';
import 'package:path/path.dart' as p;
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
  late List<List<String>> ran;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_publish_cloud_');
    cloud = _RecordingCloud();
    ran = <List<String>>[];
    exitCode = 0;
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    exitCode = 0;
  });

  void declare(String publish) =>
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: shop\n$publish');

  Future<void> publish(List<String> args) => (CommandRunner<void>('dartvel', 'test')
        ..addCommand(PublishCommand(
          root: root.path,
          cloud: cloud,
          processRun: (String executable, List<String> arguments,
              {String? workingDirectory, bool runInShell = false}) async {
            ran.add(<String>[executable, ...arguments]);
            return ProcessResult(0, 0, '', '');
          },
        )))
      .run(<String>['publish', ...args]);

  test('Firebase builds a release APK and publishes it in the same run', () async {
    declare('dartvel:\n  publish:\n    firebase:\n      app: "1:1:android:ab"\n');
    // Nothing is built here: the artifact is the runner's.
    await publish(<String>['firebase', '--cloud', '--dry-run']);
    expect(exitCode, 0);
    expect(ran, isEmpty);
    final DVCloudBuildRequest request = cloud.requests.single;
    expect(request.target, 'android');
    expect(request.profile, 'release');
    expect(request.publish, 'firebase');
    expect(request.dryRun, isTrue);
  });

  test('a declaration the upload would refuse is refused before the dispatch', () async {
    declare('dartvel:\n  publish:\n    firebase:\n      groups: [qa]\n');
    await publish(<String>['firebase', '--cloud']);
    expect(exitCode, 78);
    expect(cloud.requests, isEmpty);
  });

  test('Google Play is refused: dartvel build android writes an APK, and Play takes a bundle', () async {
    declare('dartvel:\n  publish:\n    play:\n      track: internal\n      credentials: play.json\n');
    await publish(<String>['play', '--cloud']);
    expect(exitCode, 78);
    expect(cloud.requests, isEmpty);
  });

  test('App Store Connect is refused: dartvel build ios does not sign', () async {
    for (final String store in <String>['appstore', 'testflight']) {
      exitCode = 0;
      declare('dartvel:\n  publish:\n    $store:\n      apiKey: K\n      apiIssuer: I\n');
      await publish(<String>[store, '--cloud']);
      expect(exitCode, 78, reason: store);
    }
    expect(cloud.requests, isEmpty);
  });
}
