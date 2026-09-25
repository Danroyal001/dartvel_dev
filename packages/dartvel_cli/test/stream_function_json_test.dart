// A backend function returning a Stream of objects, read by the generated
// client.
//
// The generated server wrote each event as `data: ${e.toString()}`. A
// string survived that, which is what the streaming example returns, and an
// object did not: a Stream<Tick> went out as "Instance of 'Tick'", which the
// client cannot decode, and a string with a newline in it went out as two
// data lines the client read as two events. This generates a real backend and
// a real client, serves the one in a child process and reads it with the
// other under `flutter test`, asserting on what the client receives.
@Timeout(Duration(minutes: 20))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _tick = '''
class Tick {
  const Tick(this.n, this.label);

  final int n;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{'n': n, 'label': label};

  static Tick fromJson(Object? json) {
    final Map<String, Object?> map = json! as Map<String, Object?>;
    return Tick(map['n']! as int, map['label']! as String);
  }
}
''';

const String _ticksFunction = '''
import 'package:dartvel_core/dartvel.dart';

import '../../shared/tick.dart';

@DVBackendFunction()
Stream<Tick> _ticks() async* {
  yield const Tick(1, 'one');
  yield const Tick(2, 'two\\nlines');
}
''';

const String _wordsFunction = '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Stream<String> _words() async* {
  yield 'plain';
  yield 'first\\nsecond';
  yield '42';
}
''';

const String _serve = r'''
import 'dart:io';

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

Future<void> main() async {
  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  stdout.writeln('PORT ${handle.port}');
  await ProcessSignal.sigterm.watch().first;
  await handle.stop();
  exit(0);
}
''';

const String _read = r'''
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_probe/dartvel_client/dartvel_client.dart';
import 'package:stream_probe/shared/tick.dart';

void main() {
  test('read', () async {
    final List<Tick> gotTicks = await ticks(fromJson: Tick.fromJson).toList();
    final List<String> gotWords = await words().toList();
    print('PROBE ${jsonEncode(<String, Object?>{
      'ticks': <Object?>[for (final Tick t in gotTicks) t.toJson()],
      'words': gotWords,
    })}');
  });
}
''';

const String _indexPage = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => const DVText('Home');
''';

Future<String> repoRoot() async {
  final Uri? lib = await Isolate.resolvePackageUri(
    Uri.parse('package:dartvel_cli/dartvel_cli.dart'),
  );
  return p.normalize(p.join(p.dirname(lib!.toFilePath()), '..', '..', '..'));
}

void write(String path, String contents) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(contents);
}

void main() {
  late Directory project;
  late Map<String, Object?> received;

  setUpAll(() async {
    final String root = await repoRoot();
    project = await Directory.systemTemp.createTemp('dartvel_stream_json_');
    write(p.join(project.path, 'lib', 'pages', 'index.page.dart'), _indexPage);
    write(p.join(project.path, 'lib', 'shared', 'tick.dart'), _tick);
    write(p.join(project.path, 'lib', 'backend', 'functions', 'ticks.get.dart'),
        _ticksFunction);
    write(p.join(project.path, 'lib', 'backend', 'functions', 'words.get.dart'),
        _wordsFunction);
    write(p.join(project.path, 'bin', 'serve.dart'), _serve);
    write(p.join(project.path, 'test', 'read_test.dart'), _read);
    write(p.join(project.path, 'pubspec.yaml'), '''
name: stream_probe
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  flutter:
    sdk: flutter
  dartvel_core:
    path: ${p.join(root, 'packages', 'dartvel_core')}
  dartvel_flutter:
    path: ${p.join(root, 'packages', 'dartvel_flutter')}
  dartvel_shelf:
    path: ${p.join(root, 'packages', 'dartvel_shelf')}
dev_dependencies:
  flutter_test:
    sdk: flutter
dartvel:
  backendHost: 127.0.0.1
''');
    write(p.join(project.path, 'pubspec_overrides.yaml'), '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(root, 'packages', 'dartvel_core')}
  dartvel_flutter:
    path: ${p.join(root, 'packages', 'dartvel_flutter')}
  dartvel_shelf:
    path: ${p.join(root, 'packages', 'dartvel_shelf')}
''');
    await routes.generate(root_: project.path);
    final ProcessResult resolved = await Process.run(
      'flutter',
      <String>['pub', 'get'],
      workingDirectory: project.path,
    );
    if (resolved.exitCode != 0) {
      throw StateError('flutter pub get failed:\n${resolved.stderr}');
    }

    final Process server = await Process.start(
      Platform.resolvedExecutable,
      <String>['run', 'bin/serve.dart'],
      workingDirectory: project.path,
    );
    final StringBuffer serverOutput = StringBuffer();
    server.stderr.transform(utf8.decoder).listen(serverOutput.write);
    try {
      // Read to the end rather than to the port line: the server logs every
      // request to stdout, and a pipe nobody reads fails its next write.
      final Completer<String> started = Completer<String>();
      server.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((String l) {
        if (l.startsWith('PORT ') && !started.isCompleted) started.complete(l);
      });
      final String portLine = await started.future
          .timeout(const Duration(minutes: 5), onTimeout: () {
        throw StateError('the backend did not start:\n$serverOutput');
      });
      final int port = int.parse(portLine.substring('PORT '.length));
      final ProcessResult result = await Process.run(
        'flutter',
        <String>[
          'test',
          'test/read_test.dart',
          '--dart-define=DARTVEL_BACKEND_URL=http://127.0.0.1:$port',
        ],
        workingDirectory: project.path,
      ).timeout(const Duration(minutes: 8));
      final String? line = const LineSplitter()
          .convert('${result.stdout}')
          .map((String l) => l.trim())
          .where((String l) => l.startsWith('PROBE '))
          .firstOrNull;
      if (result.exitCode != 0 || line == null) {
        fail('the client did not read the streams (exit ${result.exitCode}):\n'
            '${result.stdout}\n${result.stderr}\nserver:\n$serverOutput');
      }
      received =
          jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
    } finally {
      server.kill(ProcessSignal.sigterm);
      await server.exitCode.timeout(const Duration(seconds: 20),
          onTimeout: () {
        server.kill(ProcessSignal.sigkill);
        return -1;
      });
    }
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  test('a stream of objects arrives as the objects, one event each', () {
    expect(received['ticks'], <Object?>[
      <String, Object?>{'n': 1, 'label': 'one'},
      <String, Object?>{'n': 2, 'label': 'two\nlines'},
    ]);
  });

  test('a stream of strings still arrives as the strings, newlines kept', () {
    expect(received['words'], <Object?>['plain', 'first\nsecond', '42']);
  });
}
