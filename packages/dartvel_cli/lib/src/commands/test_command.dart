import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../utils/logger.dart';

class TestCommand extends Command<void> {
  @override
  final String name = 'test';

  @override
  String get description => 'Run Dartvel tests.';

  /// [root] is the project; null reads the working directory when the command
  /// runs. A test passes its own, because that directory is one value shared
  /// by every suite in the process.
  TestCommand({this._root}) {
    argParser
      ..addFlag(
        'flutter',
        defaultsTo: false,
        help: 'Force flutter test instead of dart test.',
      )
      ..addFlag(
        'dart',
        defaultsTo: false,
        help: 'Force dart test instead of flutter test.',
      )
      ..addFlag(
        'watch',
        defaultsTo: false,
        help: 'Run the tests, then rerun them whenever a Dart file in the '
            'project changes: a changed test file reruns that file, any other '
            'change reruns the suite.',
      )
      ..addFlag(
        'dry-run',
        defaultsTo: false,
        help: 'Print the resolved test command without executing it.',
      )
      ..addOption(
        'total-shards',
        help: 'Total number of CI shards running this test suite.',
      )
      ..addOption(
        'shard-index',
        help: 'Zero-based index of this CI shard.',
      )
      ..addFlag(
        'isolate',
        defaultsTo: false,
        help:
            'Run tests with per-file isolation by forcing single concurrency.',
      )
      ..addFlag(
        'update-goldens',
        defaultsTo: false,
        help: 'Update golden snapshot files for golden UI tests.',
      )
      ..addOption(
        'reporter',
        help: 'Pass a reporter to the selected test runner.',
      );
  }

  final String? _root;

  @override
  Future<void> run() async {
    final Directory root = Directory(_root ?? Directory.current.path);
    final rest = argResults?.rest ?? const <String>[];
    final mode = rest.isEmpty ? 'unit' : rest.first;
    if (!const <String>{
      'unit',
      'e2e',
      'golden',
      'native',
      'accessibility',
      'release',
    }.contains(mode)) {
      throw UsageException(
        'Unknown test mode "$mode". Use unit, e2e, golden, native, accessibility, or release.',
        usage,
      );
    }
    final forwarded = rest.skip(rest.isEmpty ? 0 : 1).toList(growable: false);

    // Reported before anything runs. Without this the command either failed
    // on a directory that was never there or, once that was fixed, ran the
    // whole suite under the name of a mode that has no tests -- and a green
    // tick that checked nothing is worse than a clear "no tests".
    final plan = DartvelTestPlan.forMode(mode: mode, root: root);
    if (!plan.found && mode != 'unit') {
      Logger.log(plan.message!);
      // Not a failure: a project with no native code has no native tests, and
      // that is not a defect to fail a pipeline over.
      return;
    }

    final invocation = DartvelTestInvocation.resolve(
      mode: mode,
      forceFlutter: argResults?['flutter'] == true,
      forceDart: argResults?['dart'] == true,
      watch: argResults?['watch'] == true,
      reporter: argResults?['reporter'] as String?,
      totalShards: _optionalPositiveInt('total-shards'),
      shardIndex: _optionalNonNegativeInt('shard-index'),
      isolate: argResults?['isolate'] == true,
      updateGoldens: argResults?['update-goldens'] == true,
      forwardedArgs: forwarded,
      root: root,
    );
    if (argResults?['dry-run'] == true) {
      stdout.writeln(invocation.printable);
      return;
    }
    if (argResults?['watch'] == true) {
      await _watch(root, invocation, plan.path ?? 'test');
      return;
    }
    final process = await Process.start(
      invocation.executable,
      invocation.arguments,
      // The resolved arguments are relative to the project, so the runner is
      // started in it rather than wherever this process happens to be.
      workingDirectory: root.path,
      runInShell: false,
    );
    await stdout.addStream(process.stdout);
    await stderr.addStream(process.stderr);
    final code = await process.exitCode;
    if (code != 0) {
      exitCode = code;
    }
  }

  /// Neither `flutter test` nor `dart test` has a watch mode, so the rerun
  /// loop is this command's own rather than a flag handed down.
  Future<void> _watch(
    Directory root,
    DartvelTestInvocation invocation,
    String suitePath,
  ) async {
    final StreamController<String> changes = StreamController<String>();
    final StreamSubscription<WatchEvent> events = DirectoryWatcher(root.path)
        .events
        .listen((WatchEvent event) => changes.add(event.path));
    final StreamSubscription<ProcessSignal> interrupt =
        ProcessSignal.sigint.watch().listen((_) => changes.close());
    Logger.log('Watching for changes. Press Ctrl+C to stop.');
    try {
      await DartvelTestWatch(root: root.path, suitePath: suitePath).run(
        changes.stream,
        (List<String> targets) async {
          final DartvelTestInvocation run = invocation.retarget(targets);
          Logger.log('\$ ${run.printable}');
          final Process process = await Process.start(
            run.executable,
            run.arguments,
            workingDirectory: root.path,
            mode: ProcessStartMode.inheritStdio,
          );
          final int code = await process.exitCode;
          exitCode = code;
          Logger.log(code == 0
              ? 'Passed. Watching for changes.'
              : 'Failed (exit $code). Watching for changes.');
        },
      );
    } finally {
      await events.cancel();
      await interrupt.cancel();
    }
  }

  int? _optionalPositiveInt(String name) {
    final raw = argResults?[name] as String?;
    if (raw == null || raw.trim().isEmpty) return null;
    final value = int.tryParse(raw);
    if (value == null || value < 1) {
      throw UsageException('$name must be a positive integer.', usage);
    }
    return value;
  }

  int? _optionalNonNegativeInt(String name) {
    final raw = argResults?[name] as String?;
    if (raw == null || raw.trim().isEmpty) return null;
    final value = int.tryParse(raw);
    if (value == null || value < 0) {
      throw UsageException('$name must be zero or greater.', usage);
    }
    return value;
  }
}


/// Where a test mode's tests live, and whether there are any.
///
/// Split out from the invocation because "there is nothing to run" is a real
/// answer that the command has to report, not an error and not a silent pass.
/// It used to fall back to the first candidate path, so `dartvel test native`
/// in a project with no native tests ran `flutter test test/native` against a
/// directory that does not exist -- the developer got a tool error about a
/// missing path rather than being told there are no tests of that kind.
class DartvelTestPlan {
  const DartvelTestPlan({
    required this.mode,
    required this.path,
    required this.searched,
  });

  final String mode;

  /// The path to run, or null when this mode has no tests in this project.
  final String? path;

  /// Every location that was looked in, so the answer to "where do I put
  /// them" is in the message rather than in the source.
  final List<String> searched;

  bool get found => path != null;

  /// Nothing to run is not a failure.
  ///
  /// A project with no native code has no native tests, and that is not a
  /// defect to fail a pipeline over. It must not pass silently either: a green
  /// tick that checked nothing is worse than a clear "no tests".
  bool get isFailure => false;

  String? get message => found
      ? null
      : 'No $mode tests in this project. Looked in: '
          '${searched.join(', ')}.';

  static DartvelTestPlan forMode({
    required String mode,
    required Directory root,
  }) {
    final List<String> candidates = _candidatesForMode(mode);
    for (final String candidate in candidates) {
      final String path = '${root.path}${Platform.pathSeparator}$candidate';
      if (File(path).existsSync() || Directory(path).existsSync()) {
        return DartvelTestPlan(
          mode: mode,
          path: candidate,
          searched: candidates,
        );
      }
    }
    return DartvelTestPlan(mode: mode, path: null, searched: candidates);
  }
}

List<String> _candidatesForMode(String mode) => switch (mode) {
      'e2e' => const <String>[
          'test/e2e',
          'test/e2e_test.dart',
          'integration_test',
        ],
      'golden' => const <String>[
          'test/golden',
          'test/goldens',
          'test/golden_test.dart',
        ],
      'native' => const <String>[
          'test/native',
          'test/native_test.dart',
          'test/ffi',
          'test/jni',
        ],
      'accessibility' => const <String>[
          'test/accessibility',
          'test/a11y',
          'test/accessibility_test.dart',
          'test/a11y_test.dart',
        ],
      'release' => const <String>[
          'test/release',
          'test/release_test.dart',
          'test/e2e',
          'test/e2e_test.dart',
          'integration_test',
          'test',
        ],
      _ => const <String>['test'],
    };

class DartvelTestInvocation {
  final String executable;
  final List<String> arguments;

  /// The test path the mode resolved to, or null when none was passed.
  final String? path;

  const DartvelTestInvocation({
    required this.executable,
    required this.arguments,
    this.path,
  });

  /// The same run over [targets] in place of the mode's path.
  DartvelTestInvocation retarget(List<String> targets) => DartvelTestInvocation(
        executable: executable,
        arguments: List<String>.unmodifiable(<String>[
          'test',
          ...targets,
          ...arguments.skip(path == null ? 1 : 2),
        ]),
        path: targets.length == 1 ? targets.single : null,
      );

  String get printable => <String>[executable, ...arguments].join(' ');

  static DartvelTestInvocation resolve({
    required String mode,
    required bool forceFlutter,
    required bool forceDart,
    required bool watch,
    required String? reporter,
    required int? totalShards,
    required int? shardIndex,
    required bool isolate,
    required bool updateGoldens,
    required List<String> forwardedArgs,
    required Directory root,
  }) {
    if (forceFlutter && forceDart) {
      throw ArgumentError('Use either --flutter or --dart, not both.');
    }
    final useFlutter = forceFlutter || (!forceDart && _isFlutterProject(root));
    final executable = useFlutter ? 'flutter' : 'dart';
    final args = <String>['test'];
    final path = _pathForMode(mode, root);
    if (path != null) {
      args.add(path);
    }
    // [watch] is not forwarded: neither runner accepts --watch, and
    // `dartvel test` reruns through [DartvelTestWatch] instead.
    if (reporter != null && reporter.trim().isNotEmpty) {
      args.addAll(<String>['--reporter', reporter.trim()]);
    }
    if (totalShards != null || shardIndex != null) {
      if (totalShards == null || shardIndex == null) {
        throw ArgumentError('Use --total-shards and --shard-index together.');
      }
      if (shardIndex >= totalShards) {
        throw ArgumentError('shard-index must be less than total-shards.');
      }
      args.addAll(<String>[
        '--total-shards',
        '$totalShards',
        '--shard-index',
        '$shardIndex',
      ]);
    }
    if (isolate) {
      args.addAll(<String>['--concurrency', '1']);
    }
    if (updateGoldens) {
      args.add('--update-goldens');
    }
    args.addAll(forwardedArgs);
    return DartvelTestInvocation(
      executable: executable,
      arguments: List<String>.unmodifiable(args),
      path: path,
    );
  }

  static bool _isFlutterProject(Directory root) {
    final pubspec = File('${root.path}${Platform.pathSeparator}pubspec.yaml');
    if (!pubspec.existsSync()) return false;
    final content = pubspec.readAsStringSync();
    return content.contains(RegExp(r'^\s*flutter\s*:', multiLine: true)) ||
        content.contains(RegExp(r'^\s*flutter_test\s*:', multiLine: true));
  }

  static String? _pathForMode(String mode, Directory root) =>
      DartvelTestPlan.forMode(mode: mode, root: root).path;

}

/// The rerun loop behind `dartvel test --watch`.
///
/// Runs the suite once, then collects changed paths until they settle for
/// [debounce] and runs what they affect. Runs never overlap: a batch that
/// settles while tests are running waits for them.
class DartvelTestWatch {
  DartvelTestWatch({
    required this.root,
    required this.suitePath,
    this.debounce = const Duration(milliseconds: 300),
  });

  final String root;

  /// What a change to anything but a test file reruns.
  final String suitePath;

  final Duration debounce;

  static const Set<String> _ignored = <String>{'.dart_tool', 'build', '.git'};

  /// The paths to hand the runner for [changed], or null for nothing to run.
  ///
  /// Changed test files that still exist run on their own. Any other Dart
  /// source may be imported by any test, so it reruns the whole suite.
  static List<String>? targetsFor(
    Iterable<String> changed, {
    required String root,
    required String suitePath,
  }) {
    final Set<String> tests = <String>{};
    bool suite = false;
    for (final String path in changed) {
      final String relative = p.relative(path, from: root);
      if (!relative.endsWith('.dart')) continue;
      final List<String> parts = p.split(relative);
      if (parts.first == '..' || _ignored.contains(parts.first)) continue;
      if (relative.endsWith('_test.dart')) {
        if (File(p.join(root, relative)).existsSync()) {
          tests.add(p.posix.joinAll(parts));
        }
      } else {
        suite = true;
      }
    }
    if (suite) return <String>[suitePath];
    if (tests.isEmpty) return null;
    return tests.toList()..sort();
  }

  /// Runs until [changes] closes, then waits for the last run to finish.
  Future<void> run(
    Stream<String> changes,
    Future<void> Function(List<String> targets) runTests,
  ) async {
    Future<void> last = runTests(<String>[suitePath]);
    final Set<String> pending = <String>{};
    Timer? timer;

    void flush() {
      final List<String>? targets =
          targetsFor(pending, root: root, suitePath: suitePath);
      pending.clear();
      if (targets == null) return;
      last = last.then((_) => runTests(targets));
    }

    await for (final String path in changes) {
      pending.add(path);
      timer?.cancel();
      timer = Timer(debounce, flush);
    }
    if (timer?.isActive ?? false) {
      timer!.cancel();
      flush();
    }
    await last;
  }
}
