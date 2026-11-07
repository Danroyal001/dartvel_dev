// `dartvel build web` with `dartvel.web.renderer` set, end to end with
// Flutter faked: the pubspec value reaches `flutter build web` as --wasm, and
// a value the build does not know stops it before anything is generated.
import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory _project(String renderer) {
  final Directory temp = Directory.systemTemp.createTempSync('dv_web_renderer_');
  File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync('''
name: renderer_app
environment:
  sdk: '>=3.13.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
dartvel:
  web:
    renderer: $renderer
''');
  Directory(p.join(temp.path, 'lib')).createSync(recursive: true);
  File(p.join(temp.path, 'lib', 'main.dart')).writeAsStringSync('void main() {}');
  Directory(p.join(temp.path, 'web')).createSync();
  File(p.join(temp.path, 'web', 'index.html')).writeAsStringSync(
      '<!DOCTYPE html><html><head><meta charset="UTF-8"></head>'
      '<body><script src="flutter_bootstrap.js" async></script></body></html>');
  return temp;
}

final List<String> _ran = <String>[];
int _exit = 0;

Future<List<List<String>>> _build(Directory root) async {
  final List<List<String>> started = <List<String>>[];
  _ran.clear();
  final BuildCommand command = BuildCommand(
    root: root.path,
    preflight: (String platform, {bool? autoInstall}) async => true,
    hasBuildRunner: (String root) => false,
    processRun: (String executable, List<String> arguments,
            {String? workingDirectory, bool runInShell = false}) async {
      _ran.add('$executable ${arguments.join(' ')}');
      return ProcessResult(0, 0, '', '');
    },
    processStart: (String executable, List<String> arguments,
        {String? workingDirectory,
        Map<String, String>? environment,
        bool runInShell = false}) async {
      if (executable == 'flutter') started.add(arguments);
      // Flutter "fails", so nothing after the compile runs: only what it
      // was asked to do is under test.
      return _FakeProcess();
    },
  );
  final int previous = exitCode;
  try {
    await (CommandRunner<void>('dartvel', 'test')..addCommand(command))
        .run(<String>['build', 'web', '--no-cache']);
    _exit = exitCode;
  } finally {
    exitCode = previous;
  }
  return started;
}

void main() {
  test('dartvel.web.renderer: wasm builds with --wasm', () async {
    final Directory root = _project('wasm');
    addTearDown(() => root.deleteSync(recursive: true));
    final List<List<String>> started = await _build(root);
    final List<String> build = started.singleWhere(
        (List<String> args) => args.take(2).join(' ') == 'build web');
    expect(build, contains('--wasm'));
  });

  test('the default renderer builds without it', () async {
    final Directory root = _project('canvaskit');
    addTearDown(() => root.deleteSync(recursive: true));
    final List<List<String>> started = await _build(root);
    final List<String> build = started.singleWhere(
        (List<String> args) => args.take(2).join(' ') == 'build web');
    expect(build, isNot(contains('--wasm')));
  });

  test('a renderer it does not know is refused before anything is generated', () async {
    final Directory root = _project('skwasm');
    addTearDown(() => root.deleteSync(recursive: true));
    final List<List<String>> started = await _build(root);
    expect(started, isEmpty);
    expect(_exit, 1);
    expect(_ran.where((String run) => run.contains('routes')), isEmpty);
  });
}

class _FakeProcess implements Process {
  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();
  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();
  @override
  IOSink get stdin => IOSink(_FakeStreamConsumer());
  @override
  Future<int> get exitCode => Future<int>.value(1);
  @override
  int get pid => 1234;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

class _FakeStreamConsumer implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) async {}
  @override
  Future<void> close() async {}
}
