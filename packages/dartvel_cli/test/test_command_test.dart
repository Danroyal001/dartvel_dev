import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/test_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('TestCommand', () {
    late Directory previous;
    late Directory temp;
    late CommandRunner<void> runner;

    setUp(() {
      previous = Directory.current;
      temp = Directory.systemTemp.createTempSync('dartvel_test_command');
      Directory.current = temp;
      runner = CommandRunner<void>('dartvel', 'Test runner')
        ..addCommand(TestCommand());
    });

    tearDown(() {
      Directory.current = previous;
      temp.deleteSync(recursive: true);
    });

    test('resolves unit tests to dart test by default', () async {
      Directory(p.join(temp.path, 'test')).createSync();
      final invocation = DartvelTestInvocation.resolve(
        mode: 'unit',
        forceFlutter: false,
        forceDart: false,
        watch: false,
        reporter: 'compact',
        totalShards: null,
        shardIndex: null,
        isolate: false,
        updateGoldens: false,
        forwardedArgs: const <String>[],
        root: temp,
      );

      expect(invocation.executable, 'dart');
      expect(invocation.arguments, <String>[
        'test',
        'test',
        '--reporter',
        'compact',
      ]);
    });

    test('resolves e2e tests to integration_test when present', () {
      Directory(p.join(temp.path, 'integration_test')).createSync();
      final invocation = DartvelTestInvocation.resolve(
        mode: 'e2e',
        forceFlutter: true,
        forceDart: false,
        watch: false,
        reporter: null,
        totalShards: null,
        shardIndex: null,
        isolate: false,
        updateGoldens: false,
        forwardedArgs: const <String>['--plain-name', 'smoke'],
        root: temp,
      );

      expect(invocation.executable, 'flutter');
      expect(invocation.arguments, <String>[
        'test',
        'integration_test',
        '--plain-name',
        'smoke',
      ]);
    });

    test('dry-run command accepts golden mode', () async {
      await runner.run(<String>[
        'test',
        'golden',
        '--flutter',
        '--dry-run',
      ]);
    });

    test('resolves golden update flag for snapshot refreshes', () {
      File(p.join(temp.path, 'test', 'golden_test.dart'))
          .createSync(recursive: true);
      final invocation = DartvelTestInvocation.resolve(
        mode: 'golden',
        forceFlutter: true,
        forceDart: false,
        watch: false,
        reporter: null,
        totalShards: null,
        shardIndex: null,
        isolate: false,
        updateGoldens: true,
        forwardedArgs: const <String>[],
        root: temp,
      );

      expect(invocation.arguments, <String>[
        'test',
        'test/golden_test.dart',
        '--update-goldens',
      ]);
    });

    test('resolves native tests to generated native binding checks', () {
      Directory(p.join(temp.path, 'test', 'native'))
          .createSync(recursive: true);
      final invocation = DartvelTestInvocation.resolve(
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
        root: temp,
      );

      expect(invocation.executable, 'dart');
      expect(invocation.arguments, <String>['test', 'test/native']);
    });

    test('resolves accessibility tests to semantics checks', () {
      File(p.join(temp.path, 'test', 'accessibility_test.dart'))
          .createSync(recursive: true);
      final invocation = DartvelTestInvocation.resolve(
        mode: 'accessibility',
        forceFlutter: true,
        forceDart: false,
        watch: false,
        reporter: null,
        totalShards: null,
        shardIndex: null,
        isolate: false,
        updateGoldens: false,
        forwardedArgs: const <String>[],
        root: temp,
      );

      expect(invocation.executable, 'flutter');
      expect(
        invocation.arguments,
        <String>['test', 'test/accessibility_test.dart'],
      );
    });

    test('release mode prefers release gate tests', () {
      File(p.join(temp.path, 'test', 'release_test.dart'))
          .createSync(recursive: true);
      final invocation = DartvelTestInvocation.resolve(
        mode: 'release',
        forceFlutter: false,
        forceDart: false,
        watch: false,
        reporter: null,
        totalShards: null,
        shardIndex: null,
        isolate: false,
        updateGoldens: false,
        forwardedArgs: const <String>[],
        root: temp,
      );

      expect(invocation.arguments, <String>['test', 'test/release_test.dart']);
    });

    test('resolves shard and isolation flags for CI', () {
      Directory(p.join(temp.path, 'test')).createSync();
      final invocation = DartvelTestInvocation.resolve(
        mode: 'unit',
        forceFlutter: false,
        forceDart: true,
        watch: false,
        reporter: null,
        totalShards: 4,
        shardIndex: 2,
        isolate: true,
        updateGoldens: false,
        forwardedArgs: const <String>[],
        root: temp,
      );

      expect(invocation.arguments, <String>[
        'test',
        'test',
        '--total-shards',
        '4',
        '--shard-index',
        '2',
        '--concurrency',
        '1',
      ]);
    });

    test('rejects incomplete shard options', () {
      expect(
        () => DartvelTestInvocation.resolve(
          mode: 'unit',
          forceFlutter: false,
          forceDart: true,
          watch: false,
          reporter: null,
          totalShards: 2,
          shardIndex: null,
          isolate: false,
          updateGoldens: false,
          forwardedArgs: const <String>[],
          root: temp,
        ),
        throwsArgumentError,
      );
    });

    test('dry-run command accepts accessibility mode', () async {
      await runner.run(<String>[
        'test',
        'accessibility',
        '--flutter',
        '--dry-run',
      ]);
    });
  });

  group('a mode with nothing to run', () {
    // `dartvel test golden` looks for test/golden, test/goldens or
    // test/golden_test.dart, and this repository has none of them. What it
    // does then is worth pinning, because the harmful answer -- leaving the
    // path off, which makes the runner take the whole suite -- would report
    // success for golden tests that do not exist.
    //
    // It used to resolve to its first candidate, so the runner failed on a
    // path that is not there. That was pinned here as the lesser of two bad
    // answers, both of which it was stuck between: invent a path and fail
    // confusingly, or drop the path and pass vacuously.
    //
    // There is now a third answer. The command reports that the mode has no
    // tests, says where it looked, and returns without running anything --
    // so the assertions below check the property that actually mattered:
    // neither a made-up path nor the whole suite standing in for the mode.
    late Directory previous;
    late Directory temp;

    setUp(() {
      previous = Directory.current;
      temp = Directory.systemTemp.createTempSync('dartvel_test_missing_mode');
      Directory.current = temp;
      Directory(p.join(temp.path, 'test')).createSync();
    });

    tearDown(() {
      Directory.current = previous;
      temp.deleteSync(recursive: true);
    });

    DartvelTestInvocation resolve(String mode) => DartvelTestInvocation.resolve(
          mode: mode,
          forceFlutter: false,
          forceDart: false,
          watch: false,
          reporter: null,
          totalShards: null,
          shardIndex: null,
          isolate: false,
          updateGoldens: false,
          forwardedArgs: const <String>[],
          root: temp,
        );

    for (final MapEntry<String, String> mode in <String, String>{
      'golden': 'test/golden',
      'e2e': 'test/e2e',
      'native': 'test/native',
      'accessibility': 'test/accessibility',
    }.entries) {
      test('${mode.key} neither invents a path nor takes the whole suite',
          () {
        // Not the candidate directory: running against one that is not there
        // fails on a missing path, which reads as a broken tool.
        expect(resolve(mode.key).arguments, isNot(contains(mode.value)));
        // The only bare "test" should be the subcommand. A second one would
        // be the whole suite standing in for the mode, which is the answer
        // that reports success for tests that do not exist.
        expect(
          resolve(mode.key).arguments.where((String a) => a == 'test'),
          hasLength(1),
        );
      });

      test('${mode.key} says so, and says where it looked', () {
        final DartvelTestPlan plan =
            DartvelTestPlan.forMode(mode: mode.key, root: temp);
        expect(plan.found, isFalse);
        expect(plan.message, contains(mode.key));
        expect(plan.searched, contains(mode.value));
        // Not a failure: a project with no native code has no native tests.
        expect(plan.isFailure, isFalse);
      });
    }

    test('unit runs the suite, because that is what it is', () {
      expect(resolve('unit').arguments, <String>['test', 'test']);
    });

    test('a mode with its directory present resolves to it', () {
      Directory(p.join(temp.path, 'test', 'golden')).createSync();

      expect(resolve('golden').arguments, contains('test/golden'));
    });
  });
}
