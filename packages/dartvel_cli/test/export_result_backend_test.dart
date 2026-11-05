// A backend function that returns a file, served and downloaded.
//
// A `@DVBackendFunction` returning `Future<DVExportResult>` -- the job
// portals' GET /api/tracker.csv -- went through the same jsonEncode as every
// other result, which threw "Converting object to an encodable object failed:
// Instance of 'DVExportResult'" and answered 500. A DVExportResult is the
// file: its bytes are the body, untouched; its content type is the
// content-type; its name is in an RFC 6266 content-disposition. Nothing is
// wrapped in JSON and metadata does not travel.
//
// This generates a real backend, starts it and asserts on what came over the
// wire -- never on the generated text -- for the file routes and for the
// non-JSON results that already worked and must keep working beside them: a
// String as text, a Stream<List<int>> as raw bytes, a List<int> and a Map as
// JSON.
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
        await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    final HttpClientResponse response = await request.close();
    final List<int> bytes = <int>[];
    await for (final List<int> chunk in response) {
      bytes.addAll(chunk);
    }
    return <String, Object?>{
      'status': response.statusCode,
      'type': response.headers.value('content-type'),
      'disposition': response.headers.value('content-disposition'),
      'bytes': base64.encode(bytes),
    };
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  const DVDatabase().configure(MemoryDVDatabaseAdapter());
  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  final Map<String, Object?> out = <String, Object?>{};
  try {
    for (final String name in <String>[
      'tracker.csv', 'report', 'note', 'raw', 'numbers', 'summary', 'hook',
    ]) {
      out[name] = await fetch(port, '/api/$name');
    }
  } finally {
    await handle.stop();
  }
  stdout.writeln('PROBE ${jsonEncode(out)}');
  exit(0);
}
''';

Future<String> packagesDirectory() async {
  final Uri cli = (await Isolate.resolvePackageUri(
    Uri.parse('package:dartvel_cli/src/generators/routes_generator.dart'),
  ))!;
  return p.dirname(
    p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))),
  );
}

Future<Directory> backendProject(String packages) async {
  final Directory project = Directory.systemTemp.createTempSync(
    'dv_export_result_',
  );
  void write(String relative, String content) {
    File(p.join(project.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: export_result_probe
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
  // The job portals' shape: a CSV with a byte-order mark in front.
  write('lib/backend/functions/tracker.csv.get.dart', '''
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<DVExportResult> _trackerCsv() async => DVExportResult(
      fileName: 'job-tracker.csv',
      contentType: 'text/csv; charset=utf-8',
      bytes: <int>[0xef, 0xbb, 0xbf, ...utf8.encode('company,title\\nAcme,"Dev, Sr"\\n')],
      metadata: const <String, String>{'tenant': 'tenant-secret'},
    );
''');
  // Not a Future, binary, and a name that needs filename*.
  write('lib/backend/functions/report.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
DVExportResult _report() => const DVExportResult(
      fileName: 'relevé "mai".pdf',
      contentType: 'application/pdf',
      bytes: <int>[0x25, 0x50, 0x44, 0x46, 0x00, 0xff, 0x0a],
    );
''');
  write('lib/backend/functions/note.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _note() async => '{"not": "decoded"}';
''');
  write('lib/backend/functions/raw.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Stream<List<int>> _raw() => Stream<List<int>>.fromIterable(<List<int>>[
      <int>[0, 1, 2],
      <int>[253, 254, 255],
    ]);
''');
  write('lib/backend/functions/numbers.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<List<int>> _numbers() async => <int>[1, 2, 3];
''');
  write('lib/backend/functions/summary.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _summary() async => <String, Object?>{'rows': 2};
''');
  // A raw handler typed Future<Response>, as Dartvel Authenticator's payment
  // webhook is: the generated route must still compile beside the file check.
  write('lib/backend/functions/hook.get.dart', '''
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;

@DVBackendFunction(rawPath: '/api/hook')
Future<dv.Response> handler(dv.Request req) async => dv.Response.text('hooked');
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
      'dartvel routes failed:\n${generated.stdout}\n${generated.stderr}',
    );
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

  setUpAll(() async {
    project = await backendProject(await packagesDirectory());
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  test('a DVExportResult is answered as the file, and the other non-JSON '
      'results keep their shapes', () async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
      includeParentEnvironment: false,
      environment: <String, String>{
        for (final String key in <String>[
          'PATH',
          'HOME',
          'PUB_CACHE',
          'TMPDIR',
        ])
          if (Platform.environment[key] != null)
            key: Platform.environment[key]!,
      },
    ).timeout(const Duration(minutes: 3));
    final String output = '${result.stdout}\n${result.stderr}';
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run (exit ${result.exitCode}):\n$output');
    }
    final Map<String, Object?> r =
        jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
    Map<String, Object?> at(String key) => r[key]! as Map<String, Object?>;
    List<int> bytesOf(String key) => base64.decode(at(key)['bytes']! as String);

    // The file itself: exact bytes (byte-order mark included), its type, its
    // name, and nothing JSON about it.
    expect(at('tracker.csv')['status'], 200, reason: '${at('tracker.csv')}');
    expect(at('tracker.csv')['type'], 'text/csv; charset=utf-8');
    expect(
      at('tracker.csv')['disposition'],
      "attachment; filename=\"job-tracker.csv\"; "
      "filename*=UTF-8''job-tracker.csv",
    );
    expect(bytesOf('tracker.csv'), <int>[
      0xef,
      0xbb,
      0xbf,
      ...utf8.encode('company,title\nAcme,"Dev, Sr"\n'),
    ]);
    // Metadata stays on the server.
    expect(jsonEncode(r), isNot(contains('tenant-secret')));

    // A synchronous export with binary bytes and a name that is not ASCII.
    expect(at('report')['status'], 200, reason: '${at('report')}');
    expect(at('report')['type'], 'application/pdf');
    expect(
      at('report')['disposition'],
      'attachment; filename="relev_ \\"mai\\".pdf"; '
      "filename*=UTF-8''relev%C3%A9%20%22mai%22.pdf",
    );
    expect(bytesOf('report'), <int>[0x25, 0x50, 0x44, 0x46, 0x00, 0xff, 0x0a]);

    // What already worked, unchanged.
    expect(at('note')['status'], 200);
    expect(at('note')['type'], startsWith('text/plain'));
    expect(utf8.decode(bytesOf('note')), '{"not": "decoded"}');
    expect(at('note')['disposition'], isNull);

    expect(at('raw')['status'], 200);
    expect(bytesOf('raw'), <int>[0, 1, 2, 253, 254, 255]);
    expect(at('raw')['disposition'], isNull);

    expect(at('numbers')['status'], 200);
    expect(at('numbers')['type'], startsWith('application/json'));
    expect(jsonDecode(utf8.decode(bytesOf('numbers'))), <int>[1, 2, 3]);

    expect(at('summary')['status'], 200);
    expect(at('summary')['type'], startsWith('application/json'));
    expect(jsonDecode(utf8.decode(bytesOf('summary'))), <String, Object?>{
      'rows': 2,
    });

    expect(at('hook')['status'], 200, reason: '${at('hook')}');
    expect(utf8.decode(bytesOf('hook')), 'hooked');
  });
}
