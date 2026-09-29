// The documentation site, served by a real generated backend.
//
// `access: studio` is the promise that the site behaves exactly as Studio
// does, and that is only true of the running server: a person navigating to
// a page is sent to Studio's sign-in, and the document, the graph and the
// compiled site are what a path nobody serves is -- the application's 404,
// not the site's shell from a fallback two layers further on. So this
// generates a backend, starts it with a site in a directory beside a web
// root, and asks it over HTTP.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

Future<Map<String, Object?>> fetch(int port, String path) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request =
        await client.get('127.0.0.1', port, path);
    request.followRedirects = false;
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    return <String, Object?>{
      'status': response.statusCode,
      'location': response.headers.value('location'),
      'body': body,
    };
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> serve(String access) async {
  final Directory base = Directory.systemTemp.createTempSync('dv_docs_probe_');
  void write(String relative, String content) {
    File('${base.path}/$relative')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }
  write('web/index.html', '<html><title>The site</title></html>');
  write('admin/index.html', '<html><title>Studio</title></html>');
  write('docs/index.html', '<html><title>DOCS-SHELL</title></html>');
  write('docs/docs.json', '{"application":"DOCS-PAYLOAD"}');
  write('docs/graph.json', '{"models":["DOCS-GRAPH"]}');
  write('docs/main.dart.js', '// DOCS-CODE');
  final dynamic handle = await gen.startBackend(
    host: '127.0.0.1',
    port: 0,
    spaRoot: '${base.path}/web',
    admin: const DVAdminMount(path: '/__studio', enabled: true, requiresAuth: true),
    adminRoot: '${base.path}/admin',
    docs: DVDocsMount(
      path: '/docs',
      enabled: true,
      access: access == 'public' ? DVDocsAccess.public : DVDocsAccess.studio,
    ),
    docsRoot: '${base.path}/docs',
  );
  final int port = handle.port as int;
  final Map<String, Object?> out = <String, Object?>{};
  try {
    for (final String path in <String>[
      '/docs',
      '/docs/',
      '/docs/models',
      '/docs/docs.json',
      '/docs/graph.json',
      '/docs/main.dart.js',
      '/docs/index.html',
      '/no-such-page/docs.json',
    ]) {
      out[path] = await fetch(port, path);
    }
  } finally {
    await handle.stop();
    base.deleteSync(recursive: true);
  }
  return out;
}

Future<void> main() async {
  const DVDatabase().configure(MemoryDVDatabaseAdapter());
  final Map<String, Object?> out = <String, Object?>{
    'studio': await serve('studio'),
    'public': await serve('public'),
  };
  stdout.writeln('PROBE ${jsonEncode(out)}');
  exit(0);
}
''';

Future<String> packagesDirectory() async {
  final Uri cli = (await Isolate.resolvePackageUri(
    Uri.parse('package:dartvel_cli/src/generators/routes_generator.dart'),
  ))!;
  return p.dirname(
      p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))));
}

Future<Directory> backendProject(String packages) async {
  final Directory project = Directory.systemTemp.createTempSync('dv_docs_be_');
  void write(String relative, String content) {
    File(p.join(project.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: docs_probe
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
dartvel:
  backendHost: 127.0.0.1
''');
  write('pubspec_overrides.yaml', '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
  write('lib/backend/functions/ping.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _ping() async => 'pong';
''');
  write('bin/probe.dart', _probe);

  final String cliPackage = p.join(packages, 'dartvel_cli');
  final ProcessResult generated = await Process.run(
    Platform.resolvedExecutable,
    <String>[
      '--packages=${p.join(cliPackage, '.dart_tool', 'package_config.json')}',
      p.join(cliPackage, 'bin', 'routes.dart'),
    ],
    workingDirectory: project.path,
  );
  if (generated.exitCode != 0) {
    throw StateError(
        'dartvel routes failed:\n${generated.stdout}\n${generated.stderr}');
  }
  final ProcessResult resolved = await Process.run(
    Platform.resolvedExecutable,
    <String>['pub', 'get'],
    workingDirectory: project.path,
  );
  if (resolved.exitCode != 0) {
    throw StateError('dart pub get failed:\n${resolved.stderr}');
  }
  return project;
}

void main() {
  late Directory project;
  late Map<String, Object?> probe;

  setUpAll(() async {
    project = await backendProject(await packagesDirectory());
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
    ).timeout(const Duration(minutes: 5));
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (line == null) {
      throw StateError('the probe printed nothing:\n'
          '${result.stdout}\n${result.stderr}');
    }
    probe = jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  Map<String, Object?> at(String access, String path) =>
      (probe[access]! as Map<String, Object?>)[path]! as Map<String, Object?>;

  group('access: studio', () {
    test('a person opening a page is sent to Studio\'s sign-in', () {
      for (final String path in <String>['/docs', '/docs/', '/docs/models']) {
        final Map<String, Object?> answer = at('studio', path);
        expect(answer['status'], 302, reason: path);
        expect(answer['location'],
            '/__studio/login?from=${Uri.encodeQueryComponent(path)}',
            reason: path);
      }
    });

    test('the document, the graph and the site are what nothing is', () {
      final Map<String, Object?> nothing =
          at('studio', '/no-such-page/docs.json');
      for (final String path in <String>[
        '/docs/docs.json',
        '/docs/graph.json',
        '/docs/main.dart.js',
        '/docs/index.html',
      ]) {
        // Whatever the application answers a path it does not serve with --
        // its not-found page on a site with a route manifest, the shell on
        // this bare one -- and never a byte of the documentation.
        final Map<String, Object?> answer = at('studio', path);
        expect(answer['status'], nothing['status'], reason: path);
        expect(answer['body'], nothing['body'], reason: path);
        expect(answer['body'], isNot(contains('DOCS-')), reason: path);
      }
    });
  });

  group('access: public', () {
    test('the site and its data are served to anybody', () {
      for (final String path in <String>['/docs', '/docs/', '/docs/models']) {
        final Map<String, Object?> answer = at('public', path);
        expect(answer['status'], 200, reason: path);
        expect(answer['body'], contains('DOCS-SHELL'), reason: path);
      }
      expect(at('public', '/docs/docs.json')['body'], contains('DOCS-PAYLOAD'));
      expect(at('public', '/docs/graph.json')['body'], contains('DOCS-GRAPH'));
      expect(at('public', '/docs/main.dart.js')['body'], '// DOCS-CODE');
    });
  });
}
