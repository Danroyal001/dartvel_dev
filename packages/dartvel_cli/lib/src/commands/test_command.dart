import 'dart:io';

import 'package:args/command_runner.dart';

class TestCommand extends Command<void> {
  @override
  final String name = 'test';

  @override
  String get description => 'Run Dartvel tests.';

  TestCommand() {
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
        help: 'Run tests in watch mode when supported by the selected runner.',
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

  @override
  Future<void> run() async {
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
      root: Directory.current,
    );
    if (argResults?['dry-run'] == true) {
      stdout.writeln(invocation.printable);
      return;
    }
    final process = await Process.start(
      invocation.executable,
      invocation.arguments,
      runInShell: false,
    );
    await stdout.addStream(process.stdout);
    await stderr.addStream(process.stderr);
    final code = await process.exitCode;
    if (code != 0) {
      exitCode = code;
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

class DartvelTestInvocation {
  final String executable;
  final List<String> arguments;

  const DartvelTestInvocation({
    required this.executable,
    required this.arguments,
  });

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
    if (watch) {
      args.add('--watch');
    }
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
    );
  }

  static bool _isFlutterProject(Directory root) {
    final pubspec = File('${root.path}${Platform.pathSeparator}pubspec.yaml');
    if (!pubspec.existsSync()) return false;
    final content = pubspec.readAsStringSync();
    return content.contains(RegExp(r'^\s*flutter\s*:', multiLine: true)) ||
        content.contains(RegExp(r'^\s*flutter_test\s*:', multiLine: true));
  }

  static String? _pathForMode(String mode, Directory root) {
    final candidates = switch (mode) {
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
    for (final candidate in candidates) {
      final path = '${root.path}${Platform.pathSeparator}$candidate';
      if (File(path).existsSync() || Directory(path).existsSync()) {
        return candidate;
      }
    }
    return mode == 'unit' ? null : candidates.first;
  }
}
