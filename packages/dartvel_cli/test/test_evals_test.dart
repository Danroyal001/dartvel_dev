// `dartvel test --evals`: AI evals are tests, and the command runs them.
//
// Testing says `dartvel test --evals` runs the golden tests AI Operations
// defines, scored and gated, and the command did not accept the flag at all.
// The evals live under test/evals, so the whole suite still runs them --- an
// eval that only runs when somebody remembers is not a gate --- and --evals
// runs only them. A project with no evals is told so rather than handed a
// green tick that checked nothing.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/test_command.dart';
import 'package:test/test.dart';

Directory project({List<String> dirs = const <String>[]}) {
  final Directory root = Directory.systemTemp.createTempSync('dv_evals_');
  addTearDown(() => root.deleteSync(recursive: true));
  File('${root.path}/pubspec.yaml').writeAsStringSync(
    'name: app\nenvironment:\n  sdk: ">=3.13.0 <4.0.0"\n',
  );
  for (final String dir in dirs) {
    Directory('${root.path}/$dir').createSync(recursive: true);
  }
  return root;
}

Future<String> dryRun(Directory root, List<String> args) async {
  final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
    ..addCommand(TestCommand(root: root.path));
  final StringBuffer out = StringBuffer();
  await IOOverrides.runZoned(
    () => runner.run(<String>['test', ...args, '--dry-run']),
    stdout: () => _Capture(out),
  );
  return out.toString();
}

void main() {
  test('--evals runs the evals and only the evals', () async {
    final Directory root = project(dirs: <String>['test/evals']);

    final String command = await dryRun(root, <String>['--evals']);

    expect(command.trim(), 'dart test test/evals');
  });

  test('the whole suite still runs them', () {
    // test/evals is under test, so `dartvel test` is a gate on them too.
    final Directory root = project(dirs: <String>['test/evals']);
    expect(DartvelTestPlan.forMode(mode: 'unit', root: root).path, 'test');
  });

  test('a single eval file is found too', () {
    final Directory root = project();
    File('${root.path}/test/evals_test.dart').createSync(recursive: true);
    expect(DartvelTestPlan.forMode(mode: 'evals', root: root).path,
        'test/evals_test.dart');
  });

  test('no evals is said, not run as the whole suite', () async {
    final Directory root = project(dirs: <String>['test']);

    final DartvelTestPlan plan =
        DartvelTestPlan.forMode(mode: 'evals', root: root);
    expect(plan.found, isFalse);
    expect(plan.message, contains('test/evals'));
    expect(await dryRun(root, <String>['--evals']), isNot(contains('dart test')));
  });

  test('--evals with another mode is refused', () async {
    final Directory root = project(dirs: <String>['test/evals']);
    expect(dryRun(root, <String>['golden', '--evals']),
        throwsA(isA<UsageException>()));
  });
}

class _Capture implements Stdout {
  _Capture(this._out);
  final StringBuffer _out;

  @override
  void writeln([Object? object = '']) => _out.writeln(object);

  @override
  void write(Object? object) => _out.write(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
