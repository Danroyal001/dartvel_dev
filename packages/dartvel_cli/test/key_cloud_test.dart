// `dartvel key cloud`: signing and store credentials into Dartvel Cloud's
// credential store, where a worker building the project reads them. The CLI
// sends each value once and prints none of them.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/key_command.dart';
import 'package:dartvel_core/cloud.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late _FakeVault vault;
  late List<String> logs;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dartvel_key_cloud_');
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: shop\n');
    vault = await _FakeVault.start();
    logs = <String>[];
    exitCode = 0;
  });

  tearDown(() async {
    await vault.close();
    root.deleteSync(recursive: true);
    exitCode = 0;
  });

  Future<void> key(List<String> args, {List<int> stdin = const <int>[], Map<String, String>? environment}) =>
      (CommandRunner<void>('dartvel', 'test')
            ..addCommand(KeyCommand(
              cloud: KeyCloudCommand(
                root: root.path,
                environment: environment ??
                    <String, String>{'DARTVEL_CLOUD_URL': vault.url, 'DARTVEL_CLOUD_TOKEN': 'tok_1'},
                log: logs.add,
                readStdin: () async => stdin,
              ),
            )))
          .run(<String>['key', 'cloud', ...args]);

  test('stores a keystore under the project, byte for byte, and prints no value', () async {
    final List<int> jks = <int>[0xfe, 0xed, 0xfe, 0xed, 0, 1, 2, 255];
    File(p.join(root.path, 'upload.jks')).writeAsBytesSync(jks);
    await key(<String>['android-keystore', 'upload.jks']);
    expect(exitCode, 0, reason: logs.join('\n'));
    expect(vault.values['shop/android-keystore'], jks);
    expect(vault.authorization, 'Bearer tok_1');
    expect(logs.join('\n'), contains('android-keystore'));
  });

  test('a password comes from standard input and is never printed', () async {
    await key(<String>['android-keystore-password', '-'], stdin: utf8.encode('s3cret-pass'));
    expect(exitCode, 0, reason: logs.join('\n'));
    expect(utf8.decode(vault.values['shop/android-keystore-password']!), 's3cret-pass');
    expect(logs.join('\n'), isNot(contains('s3cret-pass')));
  });

  test('an empty value is refused rather than stored', () async {
    await key(<String>['android-keystore-password', '-']);
    expect(exitCode, 65);
    expect(vault.values, isEmpty);
  });

  test('a name the service does not know is refused, listing the ones it does', () async {
    File(p.join(root.path, 'x')).writeAsStringSync('x');
    await key(<String>['AWS_SECRET', 'x']);
    expect(exitCode, 64);
    expect(logs.join('\n'), contains('android-keystore'));
    expect(vault.requests, isEmpty);
  });

  test('a file that is not there is refused before anything is sent', () async {
    await key(<String>['android-keystore', 'missing.jks']);
    expect(exitCode, 66);
    expect(vault.requests, isEmpty);
  });

  test('with no name it lists what is set, and what can be', () async {
    vault.values['shop/android-key-alias'] = utf8.encode('upload');
    await key(<String>[]);
    expect(exitCode, 0, reason: logs.join('\n'));
    final String out = logs.join('\n');
    expect(out, contains('android-key-alias'));
    expect(out, isNot(contains('upload\n')));
    expect(out, contains('ios-provisioning-profile'));
  });

  test('--delete removes one', () async {
    vault.values['shop/play-service-account'] = utf8.encode('{}');
    await key(<String>['play-service-account', '--delete']);
    expect(exitCode, 0, reason: logs.join('\n'));
    expect(vault.values, isEmpty);
  });

  test('an account with no plan is sent to the plans page', () async {
    vault.plan = false;
    File(p.join(root.path, 'sa.json')).writeAsStringSync('{}');
    await key(<String>['firebase-service-account', 'sa.json']);
    expect(exitCode, 77);
    expect(logs.join('\n'), contains(dvCloudPlansUrl));
  });

  test('without a token it says where one comes from', () async {
    File(p.join(root.path, 'sa.json')).writeAsStringSync('{}');
    await key(<String>['firebase-service-account', 'sa.json'],
        environment: <String, String>{'DARTVEL_CLOUD_URL': vault.url});
    expect(exitCode, 77);
    expect(logs.join('\n'), contains('DARTVEL_CLOUD_TOKEN'));
    expect(vault.requests, isEmpty);
  });
}

class _FakeVault {
  _FakeVault._(this._server);

  final HttpServer _server;
  final Map<String, List<int>> values = <String, List<int>>{};
  final List<String> requests = <String>[];
  bool plan = true;
  String? authorization;

  String get url => 'http://127.0.0.1:${_server.port}';

  static Future<_FakeVault> start() async {
    final _FakeVault fake = _FakeVault._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    fake._server.listen(fake._handle);
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    requests.add('${request.method} ${request.uri.path}');
    authorization = request.headers.value('authorization');
    final HttpResponse response = request.response;
    final List<String> parts = request.uri.pathSegments;
    final List<int> body = <int>[];
    await for (final List<int> chunk in request) {
      body.addAll(chunk);
    }
    if (!plan) {
      response.statusCode = 402;
      response.write(jsonEncode(const DVCloudRefusal(
              status: 402, code: 'plan_required', message: 'Cloud needs a plan.', url: dvCloudPlansUrl)
          .toJson()));
      await response.close();
      return;
    }
    // api v1 projects <project> credentials [name]
    if (parts.length >= 5 && parts[2] == 'projects' && parts[4] == 'credentials') {
      final String project = parts[3];
      if (parts.length == 5 && request.method == 'GET') {
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(<String, Object?>{
          'names': <String>[
            for (final String k in values.keys)
              if (k.startsWith('$project/')) k.substring(project.length + 1),
          ],
        }));
      } else if (parts.length == 6 && request.method == 'PUT') {
        values['$project/${parts[5]}'] = body;
        response.statusCode = 204;
      } else if (parts.length == 6 && request.method == 'DELETE') {
        values.remove('$project/${parts[5]}');
        response.statusCode = 204;
      } else {
        response.statusCode = 404;
      }
      await response.close();
      return;
    }
    response.statusCode = 404;
    await response.close();
  }
}
