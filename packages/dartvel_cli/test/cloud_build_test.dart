// `dartvel build <target> --cloud`: the project is packed, sent to Dartvel
// Cloud, built on a Dartvel worker, followed to the end and brought home into
// build/cloud/<target>.
//
// The service is a real HTTP server on loopback speaking the protocol in
// package:dartvel_core/cloud.dart, reached through DARTVEL_CLOUD_URL.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartvel_cli/src/cloud/cloud_build.dart';
import 'package:dartvel_cli/src/updates/zip_entries.dart';
import 'package:dartvel_core/cloud.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late _FakeCloud cloud;
  late List<String> logs;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dartvel_cloud_build_');
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: shop\n');
    File(p.join(root.path, 'lib', 'main.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}\n');
    File(p.join(root.path, 'build', 'app', 'old.apk'))
      ..createSync(recursive: true)
      ..writeAsStringSync('stale');
    File(p.join(root.path, '.env')).writeAsStringSync('STRIPE_KEY=sk_live');
    cloud = await _FakeCloud.start();
    logs = <String>[];
  });

  tearDown(() async {
    await cloud.close();
    root.deleteSync(recursive: true);
  });

  DVCloudBuilder builder({Map<String, String>? environment}) => DVCloudBuilder(
        environment: environment ??
            <String, String>{
              'DARTVEL_CLOUD_URL': cloud.url,
              'DARTVEL_CLOUD_TOKEN': 'tok_1',
            },
        log: logs.add,
        retryDelay: Duration.zero,
      );

  DVCloudBuildRequest request({String target = 'android', String? token}) =>
      DVCloudBuildRequest(root: root.path, target: target, token: token);

  test('refuses a target no worker builds, before sending anything', () async {
    expect(await builder().run(request(target: 'tizen')), 64);
    expect(logs.join('\n'), contains('android'));
    expect(cloud.requests, isEmpty);
  });

  test('refuses without a token and says where one comes from', () async {
    final int code = await builder(environment: <String, String>{'DARTVEL_CLOUD_URL': cloud.url})
        .run(request());
    expect(code, 77);
    expect(logs.join('\n'), allOf(contains('DARTVEL_CLOUD_TOKEN'), contains('--cloud-token')));
    expect(cloud.requests, isEmpty);
  });

  test('an account with no plan is refused with the plans page, and nothing is built', () async {
    cloud.plan = false;
    final int code = await builder().run(request());
    expect(code, 77);
    final String out = logs.join('\n');
    expect(out, contains('plan'));
    expect(out, contains(dvCloudPlansUrl));
    expect(Directory(p.join(root.path, 'build', 'cloud')).existsSync(), isFalse);
  });

  test('sends the source without build output or env files, and the spec beside it', () async {
    cloud.artifacts = <String, List<int>>{'app-release.apk': utf8.encode('apk')};
    expect(await builder().run(request(token: 'tok_flag')), 0, reason: logs.join('\n'));

    expect(cloud.authorization, 'Bearer tok_flag');
    expect(cloud.spec!.project, 'shop');
    expect(cloud.spec!.target, 'android');
    expect(cloud.spec!.profile, 'release');
    final Map<String, List<int>> uploaded = cloud.sourceEntries!;
    expect(uploaded.keys, containsAll(<String>['pubspec.yaml', 'lib/main.dart']));
    expect(utf8.decode(uploaded['lib/main.dart']!), 'void main() {}\n');
    expect(uploaded.keys.where((String k) => k.startsWith('build/')), isEmpty);
    expect(uploaded.containsKey('.env'), isFalse);
  });

  test('an application inside a repository sends the repository, and says where the app is', () async {
    Future<void> git(List<String> args) async {
      final ProcessResult r = await Process.run('git', args, workingDirectory: root.path);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }

    final Directory app = Directory(p.join(root.path, 'apps', 'shop'))..createSync(recursive: true);
    File(p.join(app.path, 'pubspec.yaml')).writeAsStringSync('name: shop\n');
    File(p.join(app.path, 'build', 'web', 'main.dart.js'))
      ..createSync(recursive: true)
      ..writeAsStringSync('output');
    File(p.join(root.path, 'packages', 'core', 'lib', 'core.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('// sibling');
    File(p.join(root.path, '.gitignore')).writeAsStringSync('secret.txt\n');
    File(p.join(root.path, 'secret.txt')).writeAsStringSync('ignored');
    await git(<String>['init', '-q']);

    expect(await builder().run(DVCloudBuildRequest(root: app.path, target: 'web')), 0,
        reason: logs.join('\n'));

    expect(cloud.spec!.app, 'apps/shop');
    final Iterable<String> sent = cloud.sourceEntries!.keys;
    expect(sent, containsAll(<String>['apps/shop/pubspec.yaml', 'packages/core/lib/core.dart']));
    expect(sent, isNot(contains('secret.txt')));
    expect(sent.where((String k) => k.contains('/build/')), isEmpty);
  });

  test('a store package and the signing choice are sent with the spec', () async {
    await builder().run(DVCloudBuildRequest(
        root: root.path, target: 'ios', format: 'ipa', codesign: false));
    expect(cloud.spec!.format, 'ipa');
    expect(cloud.spec!.codesign, isFalse);
  });

  test('prints the build log as it arrives and downloads every artifact', () async {
    cloud.artifacts = <String, List<int>>{
      'app-release.apk': utf8.encode('an apk'),
      'Runner.app/Info.plist': utf8.encode('plist'),
    };
    cloud.installUrl = 'https://cloud.example/i/b_1';

    expect(await builder().run(request()), 0, reason: logs.join('\n'));

    final String out = logs.join('\n');
    expect(out, contains('Running Gradle task'));
    expect(out, contains('https://cloud.example/i/b_1'));
    // And as a QR code a phone can scan off the terminal.
    final int link = logs.indexWhere((String l) => l.contains('https://cloud.example/i/b_1'));
    expect(logs.skip(link + 1).where((String l) => l.contains('█')), hasLength(greaterThan(10)));
    final String dir = p.join(root.path, 'build', 'cloud', 'android');
    expect(File(p.join(dir, 'app-release.apk')).readAsStringSync(), 'an apk');
    expect(File(p.join(dir, 'Runner.app', 'Info.plist')).readAsStringSync(), 'plist');
  });

  test('a dropped event stream is resumed where it stopped, without repeating lines', () async {
    cloud.dropStreamAfterFirstEvent = true;
    expect(await builder().run(request()), 0, reason: logs.join('\n'));
    expect(cloud.lastEventIds, contains('1'));
    expect(logs.where((String l) => l.contains('Resolving dependencies')), hasLength(1));
    expect(logs.where((String l) => l.contains('Running Gradle task')), hasLength(1));
  });

  test('an artifact that does not match its checksum fails the build and is not kept', () async {
    cloud.artifacts = <String, List<int>>{'app-release.apk': utf8.encode('an apk')};
    cloud.corruptDownloads = true;
    expect(await builder().run(request()), 1);
    expect(logs.join('\n'), contains('checksum'));
    expect(File(p.join(root.path, 'build', 'cloud', 'android', 'app-release.apk')).existsSync(), isFalse);
  });

  test('a failed build fails the command with its reason', () async {
    cloud.finalStatus = DVCloudBuildStatus.failed;
    expect(await builder().run(request()), 1);
    expect(logs.join('\n'), contains('Gradle task assembleRelease failed'));
    expect(Directory(p.join(root.path, 'build', 'cloud')).existsSync(), isFalse);
  });

  test('a service that does not answer is said to be unreachable', () async {
    final int port = cloud.port;
    await cloud.close();
    final int code = await builder(environment: <String, String>{
      'DARTVEL_CLOUD_URL': 'http://127.0.0.1:$port',
      'DARTVEL_CLOUD_TOKEN': 'tok',
    }).run(request());
    expect(code, 69);
    expect(logs.join('\n'), contains('127.0.0.1:$port'));
  });
}

class _FakeCloud {
  _FakeCloud._(this._server);

  final HttpServer _server;
  final List<String> requests = <String>[];
  final List<String?> lastEventIds = <String?>[];
  bool plan = true;
  bool dropStreamAfterFirstEvent = false;
  bool corruptDownloads = false;
  DVCloudBuildStatus finalStatus = DVCloudBuildStatus.succeeded;
  Map<String, List<int>> artifacts = <String, List<int>>{'app-release.apk': utf8.encode('x')};
  String? installUrl;
  String? authorization;
  DVCloudBuildSpec? spec;
  Map<String, List<int>>? sourceEntries;
  bool _dropped = false;

  int get port => _server.port;
  String get url => 'http://127.0.0.1:$port';

  static Future<_FakeCloud> start() async {
    final _FakeCloud fake = _FakeCloud._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    fake._server.listen(fake._handle);
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  List<DVCloudEvent> get _events => <DVCloudEvent>[
        const DVCloudEvent.log(1, 'Resolving dependencies'),
        const DVCloudEvent.status(2, DVCloudBuildStatus.running),
        const DVCloudEvent.log(3, 'Running Gradle task'),
        DVCloudEvent.status(4, finalStatus),
      ];

  DVCloudBuild get _build => DVCloudBuild(
        id: 'b_1',
        spec: spec!,
        status: finalStatus,
        installUrl: installUrl,
        message: finalStatus == DVCloudBuildStatus.failed
            ? 'Gradle task assembleRelease failed'
            : null,
        artifacts: finalStatus == DVCloudBuildStatus.succeeded
            ? <DVCloudArtifact>[
                for (final MapEntry<String, List<int>> a in artifacts.entries)
                  DVCloudArtifact(name: a.key, size: a.value.length, sha256: '${sha256.convert(a.value)}'),
              ]
            : const <DVCloudArtifact>[],
      );

  Future<void> _json(HttpResponse response, int status, Object json) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(json));
    await response.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final String path = request.uri.path;
    requests.add('${request.method} $path');
    final HttpResponse response = request.response;
    authorization = request.headers.value('authorization');
    if (request.method == 'POST' && path == '/api/v1/builds') {
      if (!plan) {
        await request.drain<void>();
        await _json(response, 402, const DVCloudRefusal(
          status: 402,
          code: 'plan_required',
          message: 'Cloud builds need a paid plan.',
          url: dvCloudPlansUrl,
        ).toJson());
        return;
      }
      spec = DVCloudBuildSpec.fromJson(
          jsonDecode(request.headers.value(dvCloudBuildHeader)!) as Map<String, Object?>);
      final File zip = File('${Directory.systemTemp.createTempSync('fake_cloud_').path}/s.zip');
      final IOSink sink = zip.openWrite();
      await sink.addStream(request);
      await sink.close();
      sourceEntries = dvReadZipEntries(zip.path, (_) => true);
      zip.parent.deleteSync(recursive: true);
      await _json(response, 201, DVCloudBuild(
        id: 'b_1',
        spec: spec!,
        status: DVCloudBuildStatus.queued,
        queuePosition: 2,
      ).toJson());
      return;
    }
    if (path == '/api/v1/builds/b_1/events') {
      final String? last = request.headers.value('last-event-id');
      lastEventIds.add(last);
      final int after = int.tryParse(last ?? '') ?? 0;
      response.headers.contentType = ContentType('text', 'event-stream');
      response.bufferOutput = false;
      for (final DVCloudEvent e in _events.where((DVCloudEvent e) => e.id > after)) {
        response.write(dvCloudEncodeEvent(e));
        await response.flush();
        if (dropStreamAfterFirstEvent && !_dropped) {
          _dropped = true;
          await response.close();
          return;
        }
      }
      await response.close();
      return;
    }
    if (path == '/api/v1/builds/b_1') {
      await _json(response, 200, _build.toJson());
      return;
    }
    const String prefix = '/api/v1/builds/b_1/artifacts/';
    if (path.startsWith(prefix)) {
      final String name = Uri.decodeComponent(path.substring(prefix.length));
      final List<int>? bytes = artifacts[name];
      if (bytes == null) {
        response.statusCode = 404;
      } else {
        response.add(corruptDownloads ? <int>[...bytes, 0] : bytes);
      }
      await response.close();
      return;
    }
    response.statusCode = 404;
    await response.close();
  }
}
