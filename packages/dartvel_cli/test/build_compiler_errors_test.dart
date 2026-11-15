// `dartvel build web` shows the compiler's own error when the app does not
// compile.
//
// A wasm build runs Flutter verbose and quietly: the log goes to a file and
// only Flutter's progress lines reach the console. The compiler's
// diagnostics -- `lib/x.dart:12:5: Error: Undefined name 'y'.` -- are not
// progress lines, and a failed build printed only the log's last 80 lines,
// which are the Flutter tool's own stack trace. So all a developer saw was
// "ProcessException ... exit code 254" (found deploying sigmadev.digital),
// and the error itself took `flutter build web --release -v` to find.
//
// Flutter is faked with the shape of a real failed verbose build: the
// diagnostic early, a long stack trace after it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory _project() {
  final Directory temp = Directory.systemTemp.createTempSync('dv_compile_error_');
  File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync('''
name: broken_app
environment:
  sdk: '>=3.13.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
dartvel:
  org: com.example
''');
  Directory(p.join(temp.path, 'lib')).createSync(recursive: true);
  File(p.join(temp.path, 'lib', 'main.dart')).writeAsStringSync('void main() {}');
  Directory(p.join(temp.path, 'web')).createSync();
  File(p.join(temp.path, 'web', 'index.html')).writeAsStringSync(
      '<!DOCTYPE html><html><head><meta charset="UTF-8"></head>'
      '<body><script src="flutter_bootstrap.js" async></script></body></html>');
  return temp;
}

/// A failed `flutter build web --wasm -v`, as Flutter prints it.
List<String> _failedVerboseBuild() => <String>[
      '[  +12 ms] Compiling lib/main.dart for the Web...',
      '[ +480 ms] executing: /flutter/bin/cache/dart-sdk/bin/dartaotruntime '
          '/flutter/bin/cache/dart-sdk/bin/snapshots/dart2wasm_product.snapshot '
          '--platform=/flutter/bin/cache/flutter_web_sdk/kernel/dart2wasm_platform.dill '
          'package:broken_app/main.dart /tmp/out/main.dart.wasm',
      '[+9120 ms] lib/dartvel_client/application.g.dart:31:51: Error: '
          "Undefined name 'ownedProTools'.",
      '  final tools = await ownedProTools();',
      '                      ^^^^^^^^^^^^^',
      '[   +3 ms] Target dart2wasm failed: ProcessException: Process exited '
          'abnormally with exit code 254:',
      for (int frame = 0; frame < 120; frame++)
        '           #$frame      _frame$frame (package:flutter_tools/src/build_system/targets/web.dart:${200 + frame}:7)',
      '[  +40 ms] Error: Failed to compile application for the Web.',
      '[   +2 ms] "flutter web" took 9,812ms.',
    ];

void main() {
  test('a wasm build that does not compile shows the compiler\'s error', () async {
    final Directory root = _project();
    addTearDown(() => root.deleteSync(recursive: true));
    final StringBuffer shown = StringBuffer();
    final _Capture out = _Capture(shown);
    final _Capture err = _Capture(shown);
    final int previous = exitCode;
    try {
      await IOOverrides.runZoned(
        () async {
          final BuildCommand command = BuildCommand(
            root: root.path,
            preflight: (String platform, {bool? autoInstall}) async => true,
            hasBuildRunner: (String root) => false,
            processRun: (String executable, List<String> arguments,
                    {String? workingDirectory, bool runInShell = false}) async =>
                ProcessResult(0, 0, '', ''),
            processStart: (String executable, List<String> arguments,
                    {String? workingDirectory,
                    Map<String, String>? environment,
                    bool runInShell = false}) async =>
                _FailingFlutter(_failedVerboseBuild()),
          );
          await (CommandRunner<void>('dartvel', 'test')..addCommand(command))
              .run(<String>['build', 'web', '--no-cache']);
        },
        stdout: () => out,
        stderr: () => err,
      );
    } finally {
      exitCode = previous;
    }
    final String text = shown.toString();
    // The build ran the failing path at all: an empty capture passes nothing.
    expect(text, contains('Target dart2wasm failed'));
    expect(
        text,
        contains("lib/dartvel_client/application.g.dart:31:51: Error: "
            "Undefined name 'ownedProTools'."));
    // With the line it points at, as the compiler printed it.
    expect(text, contains('final tools = await ownedProTools();'));
  });
}

class _FailingFlutter implements Process {
  _FailingFlutter(this.lines);
  final List<String> lines;

  @override
  Stream<List<int>> get stdout =>
      Stream<List<int>>.value(utf8.encode('${lines.join('\n')}\n'));
  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();
  @override
  IOSink get stdin => IOSink(_Discard());
  @override
  Future<int> get exitCode =>
      Future<int>.delayed(const Duration(milliseconds: 50), () => 1);
  @override
  int get pid => 4321;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

class _Discard implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) async {}
  @override
  Future<void> close() async {}
}

/// A stdout or stderr that keeps what is written to it.
class _Capture implements Stdout {
  _Capture(this.into);
  final StringBuffer into;

  @override
  void write(Object? object) => into.write(object);
  @override
  void writeln([Object? object = '']) => into.writeln(object);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      into.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => into.writeCharCode(charCode);
  @override
  void add(List<int> data) => into.write(utf8.decode(data, allowMalformed: true));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
