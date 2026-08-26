import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../build/engine_build.dart';
import '../utils/logger.dart';

/// `dartvel engine plan|verify` — building an engine for an architecture
/// Google does not publish, and proving that is what came out.
///
/// The workflow used to hold the architecture mapping itself, in a shell
/// expression that named the requested arch in the artifact filename and
/// ignored it everywhere else. A request for 32-bit ARM built x86-64 and
/// uploaded it under an arm name. Keeping the mapping here means the run and
/// the test suite read the same source.
class EngineCommand extends Command<void> {
  @override
  final String name = 'engine';

  @override
  final String description =
      'Resolve and verify a from-source Flutter engine build.';

  EngineCommand() {
    addSubcommand(_PlanCommand());
    addSubcommand(_VerifyCommand());
  }
}

EngineArch _parseArch(String value) => EngineArch.values.firstWhere(
      (EngineArch a) => a.gnName == value,
      orElse: () => throw UsageException(
          'Unknown architecture "$value".',
          'Expected one of: ${EngineArch.values.map((EngineArch a) => a.gnName).join(', ')}'),
    );

EngineMode _parseMode(String value) => EngineMode.values.firstWhere(
      (EngineMode m) => m.name == value,
      orElse: () => throw UsageException(
          'Unknown mode "$value".',
          'Expected one of: ${EngineMode.values.map((EngineMode m) => m.name).join(', ')}'),
    );

void _addTargetOptions(ArgParser parser) {
  parser
    ..addOption('arch',
        help: 'Architecture to build for.',
        allowed: EngineArch.values.map((EngineArch a) => a.gnName).toList(),
        defaultsTo: 'x64')
    ..addOption('mode',
        help: 'Engine runtime mode.',
        allowed: EngineMode.values.map((EngineMode m) => m.name).toList(),
        defaultsTo: 'release');
}

class _PlanCommand extends Command<void> {
  @override
  final String name = 'plan';

  @override
  final String description =
      'Print the build a given architecture and mode resolves to.';

  @override
  String get invocation => 'dartvel engine plan --arch arm --mode release';

  _PlanCommand() {
    _addTargetOptions(argParser);
    argParser.addOption('src-root',
        help: 'Absolute path to engine/src, so paths handed to gn resolve.');
    argParser.addFlag('github-output',
        negatable: false,
        help: 'Emit key=value lines for \$GITHUB_OUTPUT instead of prose.');
  }

  @override
  void run() {
    final plan = engineBuildPlan(
      arch: _parseArch(argResults!['arch'] as String),
      mode: _parseMode(argResults!['mode'] as String),
      srcRoot: argResults!['src-root'] as String?,
    );

    if (argResults!['github-output'] as bool) {
      final out = StringBuffer()
        ..writeln('uses-host-config=${plan.usesHostConfig}')
        ..writeln('out-dir=${plan.outDirectory}')
        ..writeln('gn-args=${plan.gnArgs.join(' ')}')
        ..writeln('sysroot-arch=${plan.sysrootArch ?? ''}')
        ..writeln('engine-path=${plan.enginePath}')
        ..writeln('gen-snapshot-path=${plan.genSnapshotPath}')
        ..writeln('et-config=host_${plan.mode.name}');
      stdout.write(out.toString());
      return;
    }

    Logger.log(plan.usesHostConfig
        ? 'Host build: et build -c host_${plan.mode.name}'
        : 'Cross build: tools/gn ${plan.gnArgs.join(' ')}');
    Logger.log('  output           ${plan.outDirectory}');
    Logger.log('  engine           ${plan.enginePath}');
    Logger.log('  gen_snapshot     ${plan.genSnapshotPath}');
    Logger.log('  sysroot          ${plan.sysrootArch ?? '(host)'}');
    Logger.log('  expect engine    ${plan.expectedEngineMachine.name}');
    Logger.log('  expect snapshot  ${plan.expectedGenSnapshotMachine.name}');
  }
}

class _VerifyCommand extends Command<void> {
  @override
  final String name = 'verify';

  @override
  final String description =
      'Fail unless the built engine is actually the requested architecture.';

  @override
  String get invocation =>
      'dartvel engine verify <dir> --arch arm --mode release';

  _VerifyCommand() {
    _addTargetOptions(argParser);
  }

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('Give the directory holding the artifacts.', invocation);
    }
    final plan = engineBuildPlan(
      arch: _parseArch(argResults!['arch'] as String),
      mode: _parseMode(argResults!['mode'] as String),
    );

    final failures = <String>[];
    await _check(
      directory: rest.first,
      file: 'libflutter_engine.so',
      expected: plan.expectedEngineMachine,
      failures: failures,
    );
    await _check(
      directory: rest.first,
      file: 'gen_snapshot',
      expected: plan.expectedGenSnapshotMachine,
      failures: failures,
    );

    if (failures.isNotEmpty) {
      for (final failure in failures) {
        Logger.error(failure);
      }
      throw Exception(
          'The build did not produce a ${plan.arch.gnName} engine. '
          'A job that uploads this has published a mislabelled artifact.');
    }
    Logger.log(
        'Verified ${plan.arch.gnName} ${plan.mode.name} engine artifacts.');
  }

  Future<void> _check({
    required String directory,
    required String file,
    required ElfMachine expected,
    required List<String> failures,
  }) async {
    final handle = File('$directory/$file');
    if (!handle.existsSync()) {
      failures.add('$file is missing from $directory.');
      return;
    }
    final raf = await handle.open();
    final header = await raf.read(64);
    await raf.close();
    final actual = readElfMachine(header);
    if (actual != expected) {
      failures.add('$file is ${actual?.name ?? 'not a recognised ELF'}, '
          'expected ${expected.name}.');
      return;
    }
    Logger.log('$file: ${actual!.name}');
  }
}
