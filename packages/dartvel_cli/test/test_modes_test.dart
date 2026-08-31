// `dartvel test native` in a project that has no native tests.
//
// _pathForMode fell back to the first candidate when nothing matched, so the
// command ran `flutter test test/native` against a directory that does not
// exist. The developer gets a tool error about a missing path instead of
// being told there are no tests of that kind and where they would go.
//
// The other half is what the exit code should be. Failing is wrong -- a
// project with no native code has no native tests and that is not a defect --
// but passing silently, with no output, is how "dartvel test accessibility"
// becomes a green tick that checked nothing.
import 'dart:io';

import 'package:dartvel_cli/src/commands/test_command.dart';
import 'package:test/test.dart';

Directory project({List<String> dirs = const <String>[]}) {
  final Directory root = Directory.systemTemp.createTempSync('dv_testmode_');
  addTearDown(() => root.deleteSync(recursive: true));
  File('${root.path}/pubspec.yaml').writeAsStringSync(
    'name: app\nenvironment:\n  sdk: ">=3.12.0 <4.0.0"\n',
  );
  for (final String dir in dirs) {
    Directory('${root.path}/$dir').createSync(recursive: true);
  }
  return root;
}

DartvelTestPlan plan(String mode, Directory root) =>
    DartvelTestPlan.forMode(mode: mode, root: root);

void main() {
  group('finding the tests for a mode', () {
    test('it uses the directory that exists', () {
      final Directory root = project(dirs: <String>['test/native']);
      expect(plan('native', root).path, 'test/native');
      expect(plan('native', root).found, isTrue);
    });

    test('it accepts any of the conventional names', () {
      expect(plan('accessibility', project(dirs: <String>['test/a11y'])).path,
          'test/a11y');
      expect(plan('e2e', project(dirs: <String>['integration_test'])).path,
          'integration_test');
      expect(plan('golden', project(dirs: <String>['test/goldens'])).path,
          'test/goldens');
    });

    test('nothing there means nothing to run, not a made-up path', () {
      // The bug: it returned test/native and the command failed on a missing
      // directory, which reads as a broken tool.
      final DartvelTestPlan found = plan('native', project());
      expect(found.found, isFalse);
      expect(found.path, isNull);
    });

    test('it says where it looked', () {
      // So the answer to "where do I put them" is in the message rather than
      // in the source.
      final DartvelTestPlan found = plan('accessibility', project());
      expect(found.searched, contains('test/accessibility'));
      expect(found.searched, contains('test/a11y'));
    });

    test('an empty run is not a failure', () {
      // A project with no native code has no native tests, and that is not a
      // defect to fail a pipeline over.
      expect(plan('native', project()).isFailure, isFalse);
    });

    test('but it does not pass silently', () {
      // A green tick that checked nothing is worse than a clear "no tests".
      final DartvelTestPlan found = plan('native', project());
      expect(found.message, isNotNull);
      expect(found.message, contains('native'));
    });

    test('unit falls back to the whole suite', () {
      final Directory root = project(dirs: <String>['test']);
      expect(plan('unit', root).found, isTrue);
    });

    test('release prefers its own directory and falls back to the suite', () {
      expect(plan('release', project(dirs: <String>['test/release'])).path,
          'test/release');
      expect(plan('release', project(dirs: <String>['test'])).path, 'test');
    });
  });

  group('the invocation', () {
    test('a found mode runs the tests', () {
      final Directory root = project(dirs: <String>['test/native']);
      final DartvelTestInvocation invocation = DartvelTestInvocation.resolve(
        mode: 'native',
        forceFlutter: false,
        forceDart: true,
        watch: false,
        reporter: null,
        totalShards: null,
        shardIndex: null,
        isolate: false,
        updateGoldens: false,
        forwardedArgs: const <String>[],
        root: root,
      );
      expect(invocation.arguments, contains('test/native'));
    });

    test('a mode with nothing to run does not invent a path', () {
      // Which is what made the command fail on a directory that was never
      // there.
      final DartvelTestInvocation invocation = DartvelTestInvocation.resolve(
        mode: 'native',
        forceFlutter: false,
        forceDart: true,
        watch: false,
        reporter: null,
        totalShards: null,
        shardIndex: null,
        isolate: false,
        updateGoldens: false,
        forwardedArgs: const <String>[],
        root: project(),
      );
      expect(invocation.arguments, isNot(contains('test/native')));
    });
  });
}
