// The generated server entry walks the boot sequence of Application Entry.
//
// NEW_SPEC.md: "a `server` exits non-zero with the phase that failed", and
// reports DV-RUN-004 naming it. Before this a @DVBoot function that threw in
// a web process left an unhandled exception and a stack trace, and nothing
// said which part of start-up had stopped -- the line a deploy's health gate
// and the person reading its log both need.
//
// This generates a real backend and runs its generated `main` as a process,
// asserting on the exit code and what it printed. The control is the same
// binary booting when nothing throws.
@Timeout(Duration(minutes: 15))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<int> freePort() async {
  final ServerSocket socket =
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final int port = socket.port;
  await socket.close();
  return port;
}

void main() {
  late Directory project;

  setUpAll(() async {
    final Uri cli = (await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/src/generators/routes_generator.dart'),
    ))!;
    final String packages = p.dirname(
      p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))),
    );
    project = Directory.systemTemp.createTempSync('dv_server_entry_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: entry_probe
version: 1.0.0
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
  backendPort: ${await freePort()}
  run:
    shutdownGrace: 2s
''');
    write('pubspec_overrides.yaml', '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
    write('lib/backend/functions/hello.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _hello() async => 'hello';
''');
    write('lib/backend/functions/slow.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _slow() async {
  await Future<void>.delayed(const Duration(seconds: 1));
  return 'finished';
}
''');
    write('lib/backend/functions/slower.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _slower() async {
  await Future<void>.delayed(const Duration(seconds: 60));
  return 'never';
}
''');
    write('lib/boot.dart', '''
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;

@DVBoot()
void _first(DVBoot boot) {}

@DVBoot()
void _second(DVBoot boot) {
  if (Platform.environment['PROBE_BOOT_FAIL'] == '1') {
    throw StateError('the payment key is missing');
  }
}
''');

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
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  Map<String, String> inherited() => <String, String>{
        for (final String key in <String>['PATH', 'HOME', 'PUB_CACHE', 'TMPDIR'])
          if (Platform.environment[key] != null)
            key: Platform.environment[key]!,
      };

  /// The generated server entry, run in this VM's executable so a signal
  /// sent to the process reaches the server itself.
  Future<Process> server(Map<String, String> environment) async {
    final Process process = await Process.start(
      Platform.resolvedExecutable,
      <String>['.dart_tool/dartvel_server.dart'],
      workingDirectory: project.path,
      includeParentEnvironment: false,
      environment: <String, String>{...inherited(), ...environment},
    );
    addTearDown(() => process.kill(ProcessSignal.sigkill));
    return process;
  }

  test('a @DVBoot function that throws exits non-zero naming phase 4 '
      '(DV-RUN-004)', () async {
    final Process process = await server(<String, String>{
      'PROBE_BOOT_FAIL': '1',
      'DARTVEL_PORT': '${await freePort()}',
    });
    final Future<String> out = process.stdout.transform(utf8.decoder).join();
    final Future<String> err = process.stderr.transform(utf8.decoder).join();
    final int code =
        await process.exitCode.timeout(const Duration(minutes: 3));
    final String printed = '${await out}\n${await err}';
    expect(code, 70, reason: printed);
    expect(await err, contains('DV-RUN-004'));
    expect(await err, contains('phase 4, boot functions'));
    expect(await err, contains('@DVBoot function 2'));
    expect(await err, contains('the payment key is missing'));
    expect(await out, isNot(contains('listening')));
  });

  test('the same entry boots and serves when nothing throws', () async {
    final Process process = await server(<String, String>{
      'DARTVEL_PORT': '${await freePort()}',
    });
    final Completer<void> listening = Completer<void>();
    final StringBuffer printed = StringBuffer();
    process.stdout.transform(utf8.decoder).listen((String chunk) {
      printed.write(chunk);
      if (printed.toString().contains('listening') && !listening.isCompleted) {
        listening.complete();
      }
    });
    process.stderr.transform(utf8.decoder).listen(printed.write);
    await listening.future.timeout(const Duration(minutes: 3),
        onTimeout: () => fail('the server did not start:\n$printed'));
    expect(printed.toString(), isNot(contains('DV-RUN-004')));
  });

  /// Starts the server and waits for it to accept.
  Future<({Process process, StringBuffer printed, int port})> started() async {
    final int port = await freePort();
    final Process process =
        await server(<String, String>{'DARTVEL_PORT': '$port'});
    final Completer<void> listening = Completer<void>();
    final StringBuffer printed = StringBuffer();
    process.stdout.transform(utf8.decoder).listen((String chunk) {
      printed.write(chunk);
      if (printed.toString().contains('listening') && !listening.isCompleted) {
        listening.complete();
      }
    });
    process.stderr.transform(utf8.decoder).listen(printed.write);
    await listening.future.timeout(const Duration(minutes: 3),
        onTimeout: () => fail('the server did not start:\n$printed'));
    return (process: process, printed: printed, port: port);
  }

  Future<({int status, String body})> get(int port, String path) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientResponse response =
          await (await client.getUrl(Uri.parse('http://127.0.0.1:$port$path')))
              .close();
      return (
        status: response.statusCode,
        body: await response.transform(utf8.decoder).join(),
      );
    } finally {
      client.close(force: true);
    }
  }

  // Phase 8: "SIGTERM/SIGINT move to shuttingDown: stop accepting, drain
  // in-flight requests up to a declared grace, flush, exit 0." Before this
  // the server never listened for a signal, so a deploy's stop was the
  // default action -- the process killed with whatever it was answering.
  for (final ProcessSignal signal in <ProcessSignal>[
    ProcessSignal.sigterm,
    ProcessSignal.sigint,
  ]) {
    test('${signal.name} stops the server cleanly and exits 0', () async {
      final r = await started();
      expect((await get(r.port, '/api/hello')).status, 200);
      r.process.kill(signal);
      final int code = await r.process.exitCode
          .timeout(const Duration(seconds: 30), onTimeout: () => -1);
      expect(code, 0, reason: '${r.printed}');
      expect(r.printed.toString(), contains('shutting down'));
      expect(r.printed.toString(), contains('dartvel backend stopped'));
    });
  }

  // "Stop accepting, drain in-flight requests up to a declared grace":
  // a request being answered when the signal arrives is finished, one that
  // arrives during the drain is refused rather than started, and the grace
  // (dartvel.run.shutdownGrace, 2s in this project) bounds the wait.
  Future<Object?> settle(Future<({int status, String body})> request) =>
      request.then<Object?>((v) => v, onError: (Object e) => e);

  test('a request in flight when SIGTERM arrives is answered before exit',
      () async {
    final r = await started();
    final Future<Object?> slow = settle(get(r.port, '/api/slow'));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    r.process.kill(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Arrived during the drain: refused, not started.
    final Object? late = await settle(get(r.port, '/api/hello'));
    final Object? answered = await slow;
    final int code = await r.process.exitCode
        .timeout(const Duration(seconds: 30), onTimeout: () => -1);
    expect(answered, isA<({int status, String body})>(), reason: '${r.printed}');
    answered as ({int status, String body});
    expect(answered.status, 200);
    expect(answered.body, contains('finished'));
    if (late is ({int status, String body})) {
      expect(late.status, 503);
    } else {
      expect(late, isA<IOException>());
    }
    expect(code, 0, reason: '${r.printed}');
  });

  test('the drain waits no longer than the declared grace', () async {
    final r = await started();
    final Future<Object?> slower = settle(get(r.port, '/api/slower'));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final Stopwatch clock = Stopwatch()..start();
    r.process.kill(ProcessSignal.sigterm);
    final int code = await r.process.exitCode
        .timeout(const Duration(seconds: 40), onTimeout: () => -1);
    expect(code, 0, reason: '${r.printed}');
    expect(clock.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 1500)));
    expect(clock.elapsed, lessThan(const Duration(milliseconds: 4500)));
    await slower;
  });

  test('a second signal exits at once, without waiting for the drain',
      () async {
    final r = await started();
    final Future<Object?> slower = settle(get(r.port, '/api/slower'));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    r.process.kill(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final Stopwatch clock = Stopwatch()..start();
    r.process.kill(ProcessSignal.sigterm);
    final int code = await r.process.exitCode
        .timeout(const Duration(seconds: 30), onTimeout: () => -1);
    expect(code, 128 + 15, reason: '${r.printed}');
    expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    await slower;
  });
}
