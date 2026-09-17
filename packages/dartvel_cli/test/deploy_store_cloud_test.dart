// `dartvel deploy --store <store> --cloud`: the build and the upload in one run on
// a Dartvel Cloud worker. Only what the worker can really finish is
// sent; the rest is refused here, before anything is uploaded.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/cloud/cloud_build.dart';
import 'package:dartvel_cli/src/commands/deploy_command.dart';
import 'package:path/path.dart' as p;
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
        ..addCommand(DeployCommand(
          root: root.path,
          cloud: cloud,
          processRun: (String executable, List<String> arguments,
              {bool runInShell = false}) async {
            ran.add(<String>[executable, ...arguments]);
            return ProcessResult(0, 0, '', '');
          },
        )))
      .run(<String>['deploy', '--store', ...args]);

  test('Firebase builds a release APK and publishes it in the same run', () async {
    declare('dartvel:\n  publish:\n    firebase:\n      app: "1:1:android:ab"\n');
    // Nothing is built here: the artifact is the worker's.
    await publish(<String>['firebase-app-distribution', '--cloud', '--dry-run', '--cloud-token', 'tok']);
    expect(exitCode, 0);
    expect(ran, isEmpty);
    final DVCloudBuildRequest request = cloud.requests.single;
    expect(request.target, 'android');
    expect(request.profile, 'release');
    expect(request.publish, 'firebase');
    expect(request.dryRun, isTrue);
    expect(request.token, 'tok');
  });

  test('a declaration the upload would refuse is refused before the dispatch', () async {
    declare('dartvel:\n  publish:\n    firebase:\n      groups: [qa]\n');
    await publish(<String>['firebase-app-distribution', '--cloud']);
    expect(exitCode, 78);
    expect(cloud.requests, isEmpty);
  });

  test('Google Play builds an App Bundle in release and uploads it', () async {
    declare('dartvel:\n  publish:\n    play:\n      track: internal\n      credentials: play.json\n');
    await publish(<String>['play', '--cloud']);
    expect(exitCode, 0);
    final DVCloudBuildRequest request = cloud.requests.single;
    expect((request.target, request.format, request.profile, request.publish),
        ('android', 'aab', 'release', 'play'));
    expect(request.codesign, isTrue);
  });

  test('App Store Connect and TestFlight build a signed IPA and upload it', () async {
    for (final String store in <String>['appstore', 'testflight']) {
      exitCode = 0;
      declare('dartvel:\n  publish:\n    $store:\n      apiKey: K\n      apiIssuer: I\n');
      // From Linux: the upload runs on a macOS worker, where Xcode is.
      await publish(<String>[store, '--cloud']);
      expect(exitCode, 0, reason: store);
      final DVCloudBuildRequest request = cloud.requests.last;
      expect((request.target, request.format, request.publish), ('ios', 'ipa', store));
      expect(request.codesign, isTrue);
    }
  });

  test('an App Store declaration with no key is still refused before anything is sent', () async {
    declare('dartvel:\n  publish:\n    appstore:\n      apiIssuer: I\n');
    await publish(<String>['appstore', '--cloud']);
    expect(exitCode, 78);
    expect(cloud.requests, isEmpty);
  });
}
