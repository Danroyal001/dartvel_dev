// dartvel.webhooks and the AsyncAPI document reaching the generated server.
//
// The envelope and signature are configuration, so this generates a real
// backend the way `dartvel routes` does, starts it as a process and asserts on
// what the process does: which format its deliveries are configured with, and
// what it serves at /api/asyncapi.json. A build that reads the block and a
// server that does not install it would pass any test of the generated text.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

Future<void> main(List<String> arguments) async {
  Object? error;
  final Map<String, Object?> answers = <String, Object?>{};
  try {
    final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
    final HttpClient client = HttpClient();
    try {
      for (final String path in <String>['/api/asyncapi.json', '/api/webhookformat']) {
        final request = await client.getUrl(
            Uri.parse('http://127.0.0.1:${handle.port}$path'));
        final response = await request.close();
        answers[path] = <String, Object?>{
          'status': response.statusCode,
          'type': response.headers.contentType?.mimeType,
          'body': await response.transform(utf8.decoder).join(),
        };
      }
    } finally {
      client.close(force: true);
    }
    await handle.stop();
  } catch (e) {
    error = e;
  }
  stdout.writeln('PROBE ${jsonEncode(<String, Object?>{
    'error': error?.toString(),
    'answers': answers,
  })}');
  exit(0);
}
''';

String _packages() {
  return p.dirname(p.dirname(p.dirname(p.dirname(p.dirname(
      Isolate.resolvePackageUriSync(Uri.parse(
              'package:dartvel_cli/src/generators/routes_generator.dart'))!
          .toFilePath())))));
}

Directory _project(String name, String webhooks, Map<String, String> files) {
  final String packages = _packages();
  final Directory project = Directory.systemTemp.createTempSync('dv_$name');
  void write(String relative, String content) {
    final File file = File(p.join(project.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: $name
version: 2.1.0
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
dartvel:
  backendHost: 127.0.0.1
$webhooks''');
  write('pubspec_overrides.yaml', '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
  files.forEach(write);
  return project;
}

Future<ProcessResult> _routes(Directory project) {
  final String cli = p.join(_packages(), 'dartvel_cli');
  return Process.run(
    Platform.resolvedExecutable,
    <String>[
      '--packages=${p.join(cli, '.dart_tool', 'package_config.json')}',
      p.join(cli, 'bin', 'routes.dart'),
    ],
    workingDirectory: project.path,
  );
}

const String _events = '''
import 'package:dartvel_core/dartvel.dart';

void declareEvents() {
  const DVWebhooks()
    ..declare(const DVWebhookEvent('order.paid'))
    ..declare(const DVWebhookEvent(
      'customer.updated',
      sensitiveFields: <String>{'ssn'},
    ));
}
''';

void main() {
  group('a configured application', () {
    late Directory project;
    late Map<String, Object?> probe;

    setUpAll(() async {
      project = _project('webhook_probe', '''
  webhooks:
    format: cloudevents
    mode: binary
    source: https://shop.example.com
    signature: standard
''', <String, String>{
        'lib/backend/events.dart': _events,
        'lib/backend/functions/webhookformat.get.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _webhookformat() async =>
    '\${DVWebhooks.config.format.name} '
    '\${DVWebhooks.config.cloudEventsMode.name} '
    '\${DVWebhooks.config.signature.name} '
    '\${DVWebhooks.config.source}';
''',
        'bin/probe.dart': _probe,
      });
      final ProcessResult generated = await _routes(project);
      if (generated.exitCode != 0) {
        throw StateError(
            'dartvel routes failed:\n${generated.stdout}\n${generated.stderr}');
      }
      final ProcessResult resolved = await Process.run(
          Platform.resolvedExecutable, <String>['pub', 'get'],
          workingDirectory: project.path);
      if (resolved.exitCode != 0) {
        throw StateError('dart pub get failed:\n${resolved.stderr}');
      }
      final ProcessResult ran = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', 'bin/probe.dart'],
        workingDirectory: project.path,
      ).timeout(const Duration(minutes: 3));
      final String? line = const LineSplitter()
          .convert('${ran.stdout}')
          .where((String l) => l.startsWith('PROBE '))
          .firstOrNull;
      if (line == null) {
        throw StateError('the probe did not run (exit ${ran.exitCode}):\n'
            '${ran.stdout}\n${ran.stderr}');
      }
      probe = jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
    });

    tearDownAll(() {
      if (project.existsSync()) project.deleteSync(recursive: true);
    });

    Map<String, Object?> answer(String path) =>
        (probe['answers'] as Map<String, Object?>)[path] as Map<String, Object?>;

    test('the server starts', () {
      expect(probe['error'], isNull);
    });

    test('the server delivers in the format pubspec.yaml names', () {
      expect(answer('/api/webhookformat')['body'],
          contains('cloudevents binary standard https://shop.example.com'));
    });

    test('the server serves the AsyncAPI document for the declared events, '
        'in the configured envelope', () {
      final Map<String, Object?> served = answer('/api/asyncapi.json');
      expect(served['status'], 200);
      expect(served['type'], 'application/json');
      final Map<String, Object?> doc =
          jsonDecode(served['body']! as String) as Map<String, Object?>;
      expect(doc['asyncapi'], '3.0.0');
      expect((doc['info'] as Map<String, Object?>)['version'], '2.1.0');
      expect((doc['channels'] as Map<String, Object?>).keys,
          <String>['customer.updated', 'order.paid']);
      final Map<String, Object?> message = ((doc['components']
              as Map<String, Object?>)['messages']
          as Map<String, Object?>)['order.paid'] as Map<String, Object?>;
      expect(
          ((message['headers'] as Map<String, Object?>)['required'] as List<Object?>),
          containsAll(<String>['ce-type', 'webhook-signature']));
    });

    test('the same document is written into the client at build time', () {
      final String generated = File(p.join(
              project.path, 'lib', 'dartvel_client', 'asyncapi.g.dart'))
          .readAsStringSync();
      final String served = answer('/api/asyncapi.json')['body']! as String;
      expect(generated, contains(served.trim()));
    });
  });

  test('a dartvel.webhooks block the runtime could not honour stops the build',
      () async {
    final Directory project = _project('webhook_bad_block', '''
  webhooks:
    format: json
''', const <String, String>{});
    addTearDown(() => project.deleteSync(recursive: true));
    final ProcessResult result = await _routes(project);
    expect(result.exitCode, isNot(0));
    expect('${result.stdout}${result.stderr}', contains('DV-WEBHOOK-009'));
  });

  test('an event whose name the build cannot read stops the build, rather '
      'than being left out of the document', () async {
    final Directory project = _project('webhook_bad_name', '', <String, String>{
      'lib/backend/events.dart': '''
import 'package:dartvel_core/dartvel.dart';

void declareEvents(String name) {
  const DVWebhooks().declare(DVWebhookEvent(name));
}
''',
    });
    addTearDown(() => project.deleteSync(recursive: true));
    final ProcessResult result = await _routes(project);
    expect(result.exitCode, isNot(0));
    expect('${result.stdout}${result.stderr}',
        allOf(contains('DV-WEBHOOK-010'), contains('lib/backend/events.dart:4')));
  });
}
