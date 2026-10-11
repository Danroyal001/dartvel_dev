// The generated backend's symbols endpoint and the crash endpoint reading
// reports with what was uploaded: served, uploaded to, reported to.
//
// The fixtures are real. The Dart stack comes from an AOT program compiled
// with the flags `flutter build --obfuscate --split-debug-info` uses and run
// until it printed its stack; the symbols file is the one that compile saved.
// The JVM mapping is an R8 file in R8's grammar. The assertions are on what
// the server answered and what it stored, never on generated text:
//
//  * an endpoint that is reachable with no token configured;
//  * a symbols file accepted from someone who did not hold the token;
//  * a report stored in the compiler's names although its symbols were there;
//  * symbols for one release applied to another's report.
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String token = 'backend-symbols-token-0123456789';

const String _program = '''
class Checkout {
  void pay(int amount) {
    if (amount > 0) throw StateError('declined');
  }
}

void runCheckout() => Checkout().pay(5);

void main() {
  try {
    runCheckout();
  } catch (error, stack) {
    print(stack);
  }
}
''';

const String _mapping = r'''
# compiler: R8
com.example.shop.PaymentGateway -> a.b:
# {"id":"sourceFile","fileName":"PaymentGateway.kt"}
    1:3:void charge(long):20:22 -> a
''';

const String _probe = r'''
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart' hide Platform;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

String sha(List<int> bytes) => sha256.convert(bytes).toString();

Future<Map<String, Object?>> send(
  int port,
  String method,
  String path,
  List<int> bytes, {
  String? bearer,
  String? checksum,
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    if (bearer != null) request.headers.set('authorization', 'Bearer $bearer');
    if (checksum != null) request.headers.set('x-dartvel-sha256', checksum);
    request.headers.contentType = ContentType.binary;
    request.add(bytes);
    final HttpClientResponse response = await request.close();
    return <String, Object?>{
      'status': response.statusCode,
      'body': await response.transform(utf8.decoder).join(),
    };
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> put(int port, String release, String name,
        List<int> bytes, {String? bearer, String? checksum}) =>
    send(port, 'PUT', '/api/_dartvel/symbols/${Uri.encodeComponent(release)}/$name',
        bytes, bearer: bearer, checksum: checksum ?? sha(bytes));

Map<String, Object?> manifestFor(String release, Map<String, (String, List<int>)> files) =>
    <String, Object?>{
      'v': 1,
      'release': release,
      'createdAt': DateTime.utc(2026, 10, 11).toIso8601String(),
      'files': <Object?>[
        for (final MapEntry<String, (String, List<int>)> e in files.entries)
          <String, Object?>{
            'name': e.key,
            'kind': e.value.$1,
            'sha256': sha(e.value.$2),
            'bytes': e.value.$2.length,
            if (e.value.$1 == 'dartSymbols') 'buildId': Platform.environment['PROBE_BUILD_ID'],
          },
      ],
    };

DVCrashReport report(String id, String release, String errorType,
        List<DVCrashFrame> frames) =>
    DVCrashReport(
      id: id,
      kind: DVCrashKind.fatal,
      errorType: errorType,
      message: 'm',
      frames: frames,
      fingerprint: 'unsymbolicated',
      context: DVCrashContext(release: release, installId: 'install-1', platform: 'android'),
      occurredAt: DateTime.utc(2026, 10, 11),
    );

Future<void> main() async {
  const DVDatabase().configure(MemoryDVDatabaseAdapter());
  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  final Map<String, Object?> out = <String, Object?>{};
  try {
    final List<int> mapping = utf8.encode(File('mapping.txt').readAsStringSync());
    final List<int> symbols = File('app.symbols').readAsBytesSync();
    final String stack = File('stack.txt').readAsStringSync();

    out['wrongToken'] = await put(port, '2.0.0', 'mapping.txt', mapping, bearer: 'nope');
    out['noToken'] = await put(port, '2.0.0', 'mapping.txt', mapping);
    out['badChecksum'] = await put(port, '2.0.0', 'mapping.txt', mapping,
        bearer: Platform.environment['DARTVEL_SYMBOLS_TOKEN'], checksum: sha(utf8.encode('other')));
    out['traversal'] = await put(port, '2.0.0', '..%2Fx', mapping,
        bearer: Platform.environment['DARTVEL_SYMBOLS_TOKEN']);

    final String good = Platform.environment['DARTVEL_SYMBOLS_TOKEN'] ?? '';
    out['mapping'] = await put(port, '2.0.0', 'mapping.txt', mapping, bearer: good);
    out['symbols'] = await put(port, '2.0.0', 'app.android-arm64.symbols', symbols, bearer: good);
    final List<int> manifest = utf8.encode(jsonEncode(manifestFor('2.0.0', <String, (String, List<int>)>{
      'mapping.txt': ('r8Mapping', mapping),
      'app.android-arm64.symbols': ('dartSymbols', symbols),
    })));
    out['manifest'] = await put(port, '2.0.0', 'manifest.json', manifest, bearer: good);

    // A crash from 2.0.0 in R8's names, one from the Dart snapshot, and one
    // from 1.0.0, which has no symbols.
    Future<Map<String, Object?>> crash(DVCrashReport r) => send(port, 'POST',
        '/api/_dartvel/crashes', utf8.encode(jsonEncode(r.toJson())));
    out['jvmCrash'] = await crash(report('j1', '2.0.0', 'a.b', const <DVCrashFrame>[
      DVCrashFrame(function: 'a', uri: 'jvm:a.b', line: 2),
      DVCrashFrame(function: 'performCreate', uri: 'jvm:android.app.Activity', line: 8000),
    ]));
    out['dartCrash'] = await crash(report('d1', '2.0.0', 'StateError', DVCrashFrame.parse(stack)));
    out['otherRelease'] = await crash(report('o1', '1.0.0', 'a.b', const <DVCrashFrame>[
      DVCrashFrame(function: 'a', uri: 'jvm:a.b', line: 2),
    ]));

    final List<Map<String, Object?>> rows =
        await const DVDatabase().query('SELECT id, report FROM dv_crash_reports');
    out['reports'] = <String, Object?>{
      for (final Map<String, Object?> row in rows)
        '${row['id']}': jsonDecode('${row['report']}'),
    };
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
  return p.dirname(p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))));
}

void main() {
  late Directory project;
  late Directory symbolsDirectory;
  late String stack;

  setUpAll(() async {
    final String packages = await packagesDirectory();
    project = Directory.systemTemp.createTempSync('dv_symbols_backend_');
    symbolsDirectory = Directory.systemTemp.createTempSync('dv_symbols_store_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: symbols_probe
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  crypto: ^3.0.7
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
dartvel:
  backendHost: 127.0.0.1
  crashes:
    sink: dartvel
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
    write('mapping.txt', _mapping);

    // The Dart half: compile, run, keep the stack and the symbols file.
    final String dart = Platform.resolvedExecutable;
    write('crash.dart', _program);
    final ProcessResult compiled = Process.runSync(dart, <String>[
      'compile',
      'aot-snapshot',
      '--extra-gen-snapshot-options=--dwarf-stack-traces-mode,--save-debugging-info=${p.join(project.path, 'app.symbols')},--obfuscate',
      '-o',
      p.join(project.path, 'app.aot'),
      p.join(project.path, 'crash.dart'),
    ]);
    if (compiled.exitCode != 0) fail('fixture did not compile:\n${compiled.stderr}');
    final ProcessResult ran = Process.runSync(
        p.join(p.dirname(dart), 'dartaotruntime'), <String>[p.join(project.path, 'app.aot')]);
    stack = '${ran.stdout}';
    write('stack.txt', stack);

    final String cliPackage = p.join(packages, 'dartvel_cli');
    final ProcessResult generated = await Process.run(
      dart,
      <String>[
        '--packages=${p.join(cliPackage, '.dart_tool', 'package_config.json')}',
        p.join(cliPackage, 'bin', 'routes.dart'),
      ],
      workingDirectory: project.path,
    );
    if (generated.exitCode != 0) {
      throw StateError('dartvel routes failed:\n${generated.stdout}\n${generated.stderr}');
    }
    final ProcessResult resolved =
        await Process.run(dart, <String>['pub', 'get'], workingDirectory: project.path);
    if (resolved.exitCode != 0) throw StateError('pub get failed:\n${resolved.stderr}');
  });

  tearDownAll(() {
    for (final Directory d in <Directory>[project, symbolsDirectory]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Map<String, String> inherited() => <String, String>{
        for (final String key in <String>['PATH', 'HOME', 'PUB_CACHE', 'TMPDIR'])
          if (Platform.environment[key] != null) key: Platform.environment[key]!,
      };

  Future<Map<String, Object?>> probe(Map<String, String> environment) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
      includeParentEnvironment: false,
      environment: <String, String>{...inherited(), ...environment},
    ).timeout(const Duration(minutes: 3));
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run (exit ${result.exitCode}):\n${result.stdout}\n${result.stderr}');
    }
    return jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
  }

  int status(Map<String, Object?> r, String key) =>
      (r[key]! as Map<String, Object?>)['status']! as int;

  test('uploads are authenticated, checked and kept, and the crash endpoint '
      'reads reports with them', () async {
    final String buildId = RegExp(r"build_id: '([0-9a-f]+)'").firstMatch(stack)!.group(1)!;
    final Map<String, Object?> r = await probe(<String, String>{
      'DARTVEL_SYMBOLS_TOKEN': token,
      'DARTVEL_SYMBOLS_DIR': symbolsDirectory.path,
      'PROBE_BUILD_ID': buildId,
    });

    expect(status(r, 'wrongToken'), 401);
    expect(status(r, 'noToken'), 401);
    expect(status(r, 'badChecksum'), 422);
    expect(status(r, 'traversal'), 400);
    expect(status(r, 'mapping'), 200);
    expect(status(r, 'symbols'), 200);
    expect(status(r, 'manifest'), 200);
    // On disk, per release, and nothing outside it.
    expect(File(p.join(symbolsDirectory.path, '2.0.0', 'mapping.txt')).existsSync(), isTrue);
    expect(File(p.join(symbolsDirectory.path, 'x')).existsSync(), isFalse);

    final Map<String, Object?> reports = r['reports']! as Map<String, Object?>;
    // Java: R8's names are the source's.
    final Map<String, Object?> jvm = reports['j1']! as Map<String, Object?>;
    expect(jvm['symbolicated'], true);
    expect(jvm['errorType'], 'com.example.shop.PaymentGateway');
    final List<Object?> jvmFrames = jvm['frames']! as List<Object?>;
    expect((jvmFrames.first! as Map)['function'], 'charge');
    expect((jvmFrames.first! as Map)['uri'], 'jvm:com.example.shop.PaymentGateway');
    expect((jvmFrames.first! as Map)['line'], 21);

    // Dart: the snapshot's offsets are the source's lines.
    final Map<String, Object?> dart = reports['d1']! as Map<String, Object?>;
    expect(dart['symbolicated'], true);
    expect(jsonEncode(dart['frames']), contains('Checkout.pay'));
    expect(jsonEncode(dart['frames']), contains('crash.dart'));

    // 1.0.0 uploaded nothing, and 2.0.0's mapping is not applied to it.
    final Map<String, Object?> other = reports['o1']! as Map<String, Object?>;
    expect(other['symbolicated'], false);
    expect(other['errorType'], 'a.b');
  });

  test('with no token configured the endpoint does not exist', () async {
    final Map<String, Object?> r = await probe(<String, String>{
      'DARTVEL_SYMBOLS_DIR': symbolsDirectory.path,
      'PROBE_BUILD_ID': 'x',
    });
    expect(status(r, 'mapping'), 404);
    expect(status(r, 'wrongToken'), 404);
  });
}
