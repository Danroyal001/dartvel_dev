// `dartvel build <target> --cloud`: the build runs on the repository's own
// GitHub Actions, and the command follows it and brings the artifact home.
//
// The GitHub API is a real HTTP server on loopback, reached the way a GitHub
// Enterprise or self-hosted install is: through GITHUB_API_URL. git is the
// real git, in a real repository, because the remote and the branch are read
// from it and a fake would only agree with itself.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/cloud/cloud_build.dart';
import 'package:dartvel_cli/src/cloud/cloud_workflow.dart';
import 'package:dartvel_cli/src/cloud/github_repository.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('the GitHub repository a remote names', () {
    test('https and ssh remotes on github.com use api.github.com', () {
      for (final String remote in <String>[
        'https://github.com/acme/shop.git',
        'https://github.com/acme/shop',
        'git@github.com:acme/shop.git',
        'ssh://git@github.com/acme/shop.git',
        'https://x-access-token:abc@github.com/acme/shop.git',
      ]) {
        final DVGitHubRepository? repo = DVGitHubRepository.fromRemote(remote);
        expect(repo, isNotNull, reason: remote);
        expect(repo!.slug, 'acme/shop', reason: remote);
        expect(repo.apiBase, Uri.parse('https://api.github.com'), reason: remote);
      }
    });

    test('a GitHub Enterprise host is asked at its own /api/v3', () {
      final DVGitHubRepository repo =
          DVGitHubRepository.fromRemote('git@git.acme.dev:shop/app.git')!;
      expect(repo.slug, 'shop/app');
      expect(repo.apiBase, Uri.parse('https://git.acme.dev/api/v3'));
    });

    test('GITHUB_API_URL wins, which is how a self-hosted install is named', () {
      final DVGitHubRepository repo = DVGitHubRepository.fromRemote(
        'https://github.com/acme/shop.git',
        environment: <String, String>{'GITHUB_API_URL': 'http://127.0.0.1:9/'},
      )!;
      expect(repo.apiBase, Uri.parse('http://127.0.0.1:9'));
    });

    test('something that is not a repository URL is refused', () {
      expect(DVGitHubRepository.fromRemote('/srv/git/shop.git'), isNull);
      expect(DVGitHubRepository.fromRemote(''), isNull);
    });
  });

  group('the workflow a cloud build dispatches', () {
    final YamlMap workflow = loadYaml(dvCloudWorkflow(flutterVersion: '3.44.5')) as YamlMap;
    final YamlMap job = (workflow['jobs'] as YamlMap)['build'] as YamlMap;
    final List<YamlMap> steps = (job['steps'] as YamlList).cast<YamlMap>();

    test('is the same text every time, so a pushed copy can be compared', () {
      expect(dvCloudWorkflow(flutterVersion: '3.44.5'),
          dvCloudWorkflow(flutterVersion: '3.44.5'));
      expect(dvCloudWorkflow(flutterVersion: '3.44.5'),
          isNot(dvCloudWorkflow(flutterVersion: '3.44.6')));
    });

    test('builds iOS and macOS on macOS and Windows on Windows', () {
      final String runsOn = '${job['runs-on']}';
      final RegExpMatch m = RegExp(r"fromJSON\('(.*)'\)").firstMatch(runsOn)!;
      final Map<String, Object?> runners =
          jsonDecode(m.group(1)!) as Map<String, Object?>;
      expect(runners['ios'], startsWith('macos'));
      expect(runners['macos'], startsWith('macos'));
      expect(runners['windows'], startsWith('windows'));
      expect(runners['android'], startsWith('ubuntu'));
      expect(runners.keys.toSet(), dvCloudTargets.toSet());
    });

    test('pins the Flutter the project builds with', () {
      final YamlMap flutter =
          steps.firstWhere((YamlMap s) => '${s['uses']}'.startsWith('subosito/flutter-action'));
      expect((flutter['with'] as YamlMap)['flutter-version'], '3.44.5');
    });

    test('never expands an input inside a script, where it would be code', () {
      // A branch or app name is text somebody else can choose. Expanded into
      // a run: block it is shell; read from the environment it is a string.
      for (final YamlMap step in steps) {
        final Object? run = step['run'];
        if (run == null) continue;
        expect('$run', isNot(contains(r'${{')), reason: '${step['name']}');
      }
    });

    test('runs dartvel build and uploads what it wrote for every target', () {
      final String script = steps.map((YamlMap s) => '${s['run'] ?? ''}').join('\n');
      expect(script, contains('dartvel_cli:dartvel build "\$TARGET" --profile "\$PROFILE"'));
      for (final String target in dvCloudTargets) {
        expect(script, contains('$target/'), reason: 'no artifact path for $target');
      }
      final YamlMap upload =
          steps.firstWhere((YamlMap s) => '${s['uses']}'.startsWith('actions/upload-artifact'));
      expect((upload['with'] as YamlMap)['if-no-files-found'], 'error');
    });

    test('the copy this repository dispatches is the one the generator writes', () {
      // cloud-builds.yml dispatches it, and the command refuses while the
      // pushed copy differs; this says so in the test run instead.
      final String pin = '${((loadYaml(File('../../examples/basic_app/pubspec.yaml').readAsStringSync()) as YamlMap)['dartvel'] as YamlMap)['cloud']['flutter']}';
      expect(File('../../$dvCloudWorkflowPath').readAsStringSync(),
          dvCloudWorkflow(flutterVersion: pin),
          reason: 'regenerate .github/workflows/dartvel-cloud.yml with dvCloudWorkflow');
    });

    test('signs Android from repository secrets and says so when there are none', () {
      final YamlMap signing =
          steps.firstWhere((YamlMap s) => '${s['name']}'.contains('Android signing'));
      expect('${(signing['env'] as YamlMap)['KEYSTORE']}',
          contains('secrets.DARTVEL_ANDROID_KEYSTORE_BASE64'));
      expect('${signing['run']}', contains('debug key'));
    });
  });

  group('DVCloudBuild', () {
    late Directory repo;
    late _FakeGitHub github;
    late List<String> logs;

    setUp(() async {
      repo = Directory.systemTemp.createTempSync('dartvel_cloud_');
      await _git(repo.path, <String>['init', '-q', '-b', 'main']);
      await _git(repo.path, <String>['config', 'user.email', 'ci@example.com']);
      await _git(repo.path, <String>['config', 'user.name', 'CI']);
      await _git(repo.path, <String>['remote', 'add', 'origin', 'https://github.com/acme/shop.git']);
      File(p.join(repo.path, 'pubspec.yaml')).writeAsStringSync(
          'name: shop\ndartvel:\n  cloud:\n    flutter: 3.44.5\n');
      await _git(repo.path, <String>['add', '.']);
      await _git(repo.path, <String>['commit', '-q', '-m', 'init']);
      github = await _FakeGitHub.start();
      logs = <String>[];
    });

    tearDown(() async {
      await github.close();
      repo.deleteSync(recursive: true);
    });

    DVCloudBuild cloud({
      Map<String, String>? environment,
      bool ghLoggedIn = false,
    }) =>
        DVCloudBuild(
          environment: environment ??
              <String, String>{
                'GITHUB_API_URL': github.base,
                'GH_TOKEN': 'token-123',
              },
          processRun: (String executable, List<String> arguments,
              {String? workingDirectory}) async {
            if (executable == 'gh') {
              return ghLoggedIn
                  ? ProcessResult(0, 0, 'token-from-gh\n', '')
                  : ProcessResult(0, 1, '', 'not logged in');
            }
            return Process.run(executable, arguments,
                workingDirectory: workingDirectory);
          },
          log: logs.add,
          pollInterval: Duration.zero,
        );

    test('refuses a target that has no runner, before touching the network', () async {
      final int code = await cloud().run(DVCloudBuildRequest(root: repo.path, target: 'tizen'));
      expect(code, 64);
      expect(logs.join('\n'), contains('android'));
      expect(github.requests, isEmpty);
    });

    test('refuses a repository with no GitHub remote and says how to add one', () async {
      await _git(repo.path, <String>['remote', 'remove', 'origin']);
      final int code = await cloud().run(DVCloudBuildRequest(root: repo.path, target: 'android'));
      expect(code, 78);
      expect(logs.join('\n'), contains('git remote add origin'));
      expect(github.requests, isEmpty);
    });

    test('refuses without a token and names both ways to give one', () async {
      final int code = await cloud(environment: <String, String>{'GITHUB_API_URL': github.base})
          .run(DVCloudBuildRequest(root: repo.path, target: 'android'));
      expect(code, 77);
      expect(logs.join('\n'), allOf(contains('GH_TOKEN'), contains('gh auth login')));
      expect(github.requests, isEmpty);
    });

    test('takes the token gh is logged in with', () async {
      github.workflowOnRemote = dvCloudWorkflow(flutterVersion: '3.44.5');
      github.runConclusion = 'success';
      await cloud(environment: <String, String>{'GITHUB_API_URL': github.base}, ghLoggedIn: true)
          .run(DVCloudBuildRequest(root: repo.path, target: 'android'));
      expect(github.authorizations, everyElement('Bearer token-from-gh'));
    });

    test('writes the workflow and refuses to dispatch until it is pushed', () async {
      final int code = await cloud().run(DVCloudBuildRequest(root: repo.path, target: 'android'));
      expect(code, 78);
      final File written = File(p.join(repo.path, dvCloudWorkflowPath));
      expect(written.readAsStringSync(), dvCloudWorkflow(flutterVersion: '3.44.5'));
      expect(logs.join('\n'), allOf(contains('commit and push'), contains(dvCloudWorkflowPath)));
      expect(github.dispatches, isEmpty);
    });

    test('refuses when the pushed workflow is not the one this build writes', () async {
      github.workflowOnRemote = dvCloudWorkflow(flutterVersion: '3.40.0');
      final int code = await cloud().run(DVCloudBuildRequest(root: repo.path, target: 'android'));
      expect(code, 78);
      expect(github.dispatches, isEmpty);
    });

    test('dispatches, follows the run step by step, and brings the artifact home', () async {
      github.workflowOnRemote = dvCloudWorkflow(flutterVersion: '3.44.5');
      github.runConclusion = 'success';
      github.artifactFiles = <String, List<int>>{'app-release.apk': utf8.encode('an apk')};

      final int code = await cloud().run(DVCloudBuildRequest(root: repo.path, target: 'android'));

      expect(code, 0, reason: logs.join('\n'));
      expect(github.dispatches, hasLength(1));
      final Map<String, Object?> body = github.dispatches.single;
      expect(body['ref'], 'main');
      final Map<String, Object?> inputs = body['inputs']! as Map<String, Object?>;
      expect(inputs['target'], 'android');
      expect(inputs['profile'], 'release');
      expect(inputs['app'], '.');
      expect(inputs['publish'], '');
      expect('${inputs['request']}', hasLength(greaterThanOrEqualTo(8)));

      final String out = logs.join('\n');
      expect(out, contains(github.runUrl));
      expect(out, contains('dartvel build'));

      final File apk = File(p.join(repo.path, 'build', 'cloud', 'android', 'app-release.apk'));
      expect(apk.readAsStringSync(), 'an apk');
      // The download URL is storage on another host. The token is GitHub's
      // and goes nowhere else.
      expect(github.blobAuthorization, isNull);
    });

    test('an application in a subdirectory is built from there', () async {
      final Directory app = Directory(p.join(repo.path, 'apps', 'shop'))..createSync(recursive: true);
      File(p.join(app.path, 'pubspec.yaml')).writeAsStringSync(
          'name: shop\ndartvel:\n  cloud:\n    flutter: 3.44.5\n');
      github.workflowOnRemote = dvCloudWorkflow(flutterVersion: '3.44.5');
      github.runConclusion = 'success';

      final int code = await cloud().run(DVCloudBuildRequest(root: app.path, target: 'ios', profile: 'development'));

      expect(code, 0, reason: logs.join('\n'));
      final Map<String, Object?> inputs = github.dispatches.single['inputs']! as Map<String, Object?>;
      expect(inputs['app'], 'apps/shop');
      expect(inputs['profile'], 'development');
      expect(File(p.join(app.path, 'build', 'cloud', 'ios', 'app-release.apk')).existsSync(), isTrue);
    });

    test('a failed run fails the command, names the step and leaves nothing in build/', () async {
      github.workflowOnRemote = dvCloudWorkflow(flutterVersion: '3.44.5');
      github.runConclusion = 'failure';

      final int code = await cloud().run(DVCloudBuildRequest(root: repo.path, target: 'android'));

      expect(code, 1);
      final String out = logs.join('\n');
      expect(out, contains(github.runUrl));
      expect(out, contains('dartvel build'));
      expect(Directory(p.join(repo.path, 'build', 'cloud')).existsSync(), isFalse);
    });

    test('a publish rides the same run', () async {
      github.workflowOnRemote = dvCloudWorkflow(flutterVersion: '3.44.5');
      github.runConclusion = 'success';

      await cloud().run(DVCloudBuildRequest(
          root: repo.path, target: 'android', publish: 'firebase', dryRun: true));

      final Map<String, Object?> inputs = github.dispatches.single['inputs']! as Map<String, Object?>;
      expect(inputs['publish'], 'firebase');
      expect(inputs['dry_run'], 'true');
    });
  });
}

Future<void> _git(String dir, List<String> args) async {
  final ProcessResult r = await Process.run('git', args, workingDirectory: dir);
  if (r.exitCode != 0) throw StateError('git ${args.join(' ')}: ${r.stderr}');
}

/// The parts of the GitHub REST API a cloud build uses.
class _FakeGitHub {
  _FakeGitHub._(this._server);

  final HttpServer _server;
  final List<String> requests = <String>[];
  final List<String> authorizations = <String>[];
  final List<Map<String, Object?>> dispatches = <Map<String, Object?>>[];
  String? workflowOnRemote;
  String runConclusion = 'success';
  Map<String, List<int>> artifactFiles = <String, List<int>>{'app-release.apk': utf8.encode('x')};
  String? blobAuthorization = 'never requested';
  int _runPolls = 0;

  String get base => 'http://127.0.0.1:${_server.port}';
  String get runUrl => 'https://github.com/acme/shop/actions/runs/7';

  static Future<_FakeGitHub> start() async {
    final _FakeGitHub fake = _FakeGitHub._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    fake._server.listen(fake._handle);
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final String path = request.uri.path;
    final HttpResponse response = request.response;
    if (path == '/blob/artifact.zip') {
      blobAuthorization = request.headers.value('authorization');
      response.add(_zip(artifactFiles));
      await response.close();
      return;
    }
    requests.add('${request.method} $path');
    authorizations.add(request.headers.value('authorization') ?? '');
    Object? json;
    int status = 200;
    const String repo = '/repos/acme/shop';
    if (path == '$repo/contents/$dvCloudWorkflowPath') {
      if (workflowOnRemote == null) {
        status = 404;
        json = <String, Object?>{'message': 'Not Found'};
      } else {
        json = <String, Object?>{
          'encoding': 'base64',
          'content': base64.encode(utf8.encode(workflowOnRemote!)),
        };
      }
    } else if (path == '$repo/commits/main') {
      json = <String, Object?>{'sha': 'remote-sha'};
    } else if (path == '$repo/actions/workflows/dartvel-cloud.yml/dispatches') {
      dispatches.add(jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>);
      status = 204;
    } else if (path == '$repo/actions/workflows/dartvel-cloud.yml/runs') {
      final Map<String, Object?>? inputs =
          dispatches.isEmpty ? null : dispatches.last['inputs'] as Map<String, Object?>?;
      json = <String, Object?>{
        'workflow_runs': <Object?>[
          <String, Object?>{'id': 3, 'display_title': 'dartvel cloud android release [someone-else]'},
          if (inputs != null)
            <String, Object?>{
              'id': 7,
              'display_title': 'dartvel cloud ${inputs['target']} ${inputs['profile']} [${inputs['request']}]',
            },
        ],
      };
    } else if (path == '$repo/actions/runs/7') {
      _runPolls++;
      final bool done = _runPolls >= 3;
      json = <String, Object?>{
        'id': 7,
        'html_url': runUrl,
        'head_sha': 'remote-sha',
        'status': done ? 'completed' : 'in_progress',
        'conclusion': done ? runConclusion : null,
      };
    } else if (path == '$repo/actions/runs/7/jobs') {
      final bool done = _runPolls >= 3;
      json = <String, Object?>{
        'jobs': <Object?>[
          <String, Object?>{
            'name': 'dartvel build android',
            'steps': <Object?>[
              <String, Object?>{'name': 'flutter pub get', 'status': 'completed', 'conclusion': 'success'},
              <String, Object?>{
                'name': 'dartvel build',
                'status': done ? 'completed' : 'in_progress',
                'conclusion': done ? runConclusion : null,
              },
            ],
          },
        ],
      };
    } else if (path == '$repo/actions/runs/7/artifacts') {
      json = <String, Object?>{
        'artifacts': <Object?>[
          <String, Object?>{
            'id': 9,
            'name': 'dartvel-build',
            'expired': false,
            'archive_download_url': '$base$repo/actions/artifacts/9/zip',
          },
        ],
      };
    } else if (path == '$repo/actions/artifacts/9/zip') {
      // Another host name for the same server: storage is not GitHub.
      response.statusCode = 302;
      response.headers.set('location', 'http://localhost:${_server.port}/blob/artifact.zip');
      await response.close();
      return;
    } else {
      status = 404;
      json = <String, Object?>{'message': 'Not Found: $path'};
    }
    response.statusCode = status;
    if (json != null) {
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(json));
    }
    await response.close();
  }
}

/// A stored (uncompressed) zip of [files].
Uint8List _zip(Map<String, List<int>> files) {
  final BytesBuilder out = BytesBuilder();
  final BytesBuilder central = BytesBuilder();
  void u16(BytesBuilder b, int v) => b.add(<int>[v & 0xff, (v >> 8) & 0xff]);
  void u32(BytesBuilder b, int v) =>
      b.add(<int>[v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  files.forEach((String name, List<int> data) {
    final List<int> nameBytes = utf8.encode(name);
    final int offset = out.length;
    final int crc = _crc32(data);
    u32(out, 0x04034b50);
    u16(out, 20); u16(out, 0); u16(out, 0); u16(out, 0); u16(out, 0);
    u32(out, crc); u32(out, data.length); u32(out, data.length);
    u16(out, nameBytes.length); u16(out, 0);
    out.add(nameBytes);
    out.add(data);
    u32(central, 0x02014b50);
    u16(central, 20); u16(central, 20); u16(central, 0); u16(central, 0);
    u16(central, 0); u16(central, 0);
    u32(central, crc); u32(central, data.length); u32(central, data.length);
    u16(central, nameBytes.length); u16(central, 0); u16(central, 0);
    u16(central, 0); u16(central, 0); u32(central, 0); u32(central, offset);
    central.add(nameBytes);
  });
  final int centralOffset = out.length;
  final Uint8List dir = central.toBytes();
  out.add(dir);
  u32(out, 0x06054b50);
  u16(out, 0); u16(out, 0);
  u16(out, files.length); u16(out, files.length);
  u32(out, dir.length); u32(out, centralOffset);
  u16(out, 0);
  return out.toBytes();
}

int _crc32(List<int> data) {
  int crc = 0xffffffff;
  for (final int byte in data) {
    crc ^= byte;
    for (int k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}
