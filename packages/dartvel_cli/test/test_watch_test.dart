// `dartvel test --watch` reruns tests when files change.
//
// It used to forward --watch to `flutter test` or `dart test`, and neither
// accepts that flag, so the command failed at once with a usage error from
// the runner underneath.
import 'dart:async';
import 'dart:io';

import 'package:dartvel_cli/src/commands/test_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('dartvel_test_watch');
    Directory(p.join(temp.path, 'test')).createSync();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  DartvelTestInvocation resolve({required bool watch}) =>
      DartvelTestInvocation.resolve(
        mode: 'unit',
        forceFlutter: false,
        forceDart: false,
        watch: watch,
        reporter: 'compact',
        totalShards: null,
        shardIndex: null,
        isolate: false,
        updateGoldens: false,
        forwardedArgs: const <String>[],
        root: temp,
      );

  test('the runner is never handed a --watch flag it does not accept', () {
    expect(resolve(watch: true).arguments, isNot(contains('--watch')));
  });

  test('retargeting replaces the mode path and keeps every other argument',
      () {
    final DartvelTestInvocation retargeted =
        resolve(watch: true).retarget(<String>['test/a_test.dart']);
    expect(retargeted.executable, 'dart');
    expect(retargeted.arguments, <String>[
      'test',
      'test/a_test.dart',
      '--reporter',
      'compact',
    ]);
  });

  group('targets for a batch of changes', () {
    List<String>? targets(List<String> changed) => DartvelTestWatch.targetsFor(
          changed.map((String c) => p.join(temp.path, c)),
          root: temp.path,
          suitePath: 'test',
        );

    test('a changed test file reruns only that file', () {
      File(p.join(temp.path, 'test', 'a_test.dart')).writeAsStringSync('');
      expect(targets(<String>['test/a_test.dart']), <String>['test/a_test.dart']);
    });

    test('a changed source file reruns the whole suite', () {
      expect(
        targets(<String>['test/a_test.dart', 'lib/src/thing.dart']),
        <String>['test'],
      );
    });

    test('files that are not Dart, and generated output, rerun nothing', () {
      expect(targets(<String>['README.md']), isNull);
      expect(targets(<String>['.dart_tool/x.dart']), isNull);
      expect(targets(<String>['build/web/main.dart']), isNull);
    });

    test('a deleted test file is not handed to the runner', () {
      // The file does not exist on disk in this temp project, but a real one
      // that was just deleted is the same shape: the runner fails on a
      // missing path. Only test files that exist are targeted.
      File(p.join(temp.path, 'test', 'kept_test.dart')).writeAsStringSync('');
      expect(
        targets(<String>['test/kept_test.dart', 'test/gone_test.dart']),
        <String>['test/kept_test.dart'],
      );
      expect(targets(<String>['test/gone_test.dart']), isNull);
    });
  });

  test('runs once, then again for each settled batch, never overlapping',
      () async {
    File(p.join(temp.path, 'test', 'a_test.dart')).writeAsStringSync('');
    final StreamController<String> changes = StreamController<String>();
    final List<List<String>> runs = <List<String>>[];
    int running = 0;
    int maxRunning = 0;

    final Future<void> done = DartvelTestWatch(
      root: temp.path,
      suitePath: 'test',
      debounce: const Duration(milliseconds: 20),
    ).run(changes.stream, (List<String> targets) async {
      running++;
      maxRunning = running > maxRunning ? running : maxRunning;
      runs.add(targets);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      running--;
    });

    await Future<void>.delayed(const Duration(milliseconds: 5));
    changes.add(p.join(temp.path, 'test', 'a_test.dart'));
    changes.add(p.join(temp.path, 'test', 'a_test.dart'));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    changes.add(p.join(temp.path, 'lib', 'b.dart'));
    changes.add(p.join(temp.path, 'notes.txt'));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await changes.close();
    await done;

    expect(runs, <List<String>>[
      <String>['test'],
      <String>['test/a_test.dart'],
      <String>['test'],
    ]);
    expect(maxRunning, 1);
  });
}
