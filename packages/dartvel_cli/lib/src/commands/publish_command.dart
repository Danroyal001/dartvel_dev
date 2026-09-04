/// `dartvel publish <store>`: the application to a store, or the reason not.
///
/// Host support first, then the tooling, then the work -- the build
/// toolchain rule, and here it matters more than usual: the work is an
/// upload of a binary that took minutes to produce, and a credential that
/// was never declared is discovered after all of it.
///
/// `--dry-run` prints the command instead of running it, which is how
/// somebody sees what Dartvel would do to their store account before it does
/// it.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import '../publish/publish_plan.dart';
import '../utils/logger.dart';

typedef PublishProcessRun = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool runInShell,
});

class PublishCommand extends Command<void> {
  PublishCommand({PublishProcessRun? processRun})
      : _processRun = processRun ?? _defaultRun {
    argParser
      ..addFlag('dry-run',
          defaultsTo: false,
          negatable: false,
          help: 'Print the command that would run, and run nothing.')
      ..addOption('artifact',
          help: 'The file to upload, when it is not where the build puts it.');
  }

  static Future<ProcessResult> _defaultRun(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
  }) =>
      Process.run(executable, arguments,
          workingDirectory: workingDirectory, runInShell: runInShell);

  final PublishProcessRun _processRun;

  @override
  final String name = 'publish';

  @override
  String get description =>
      'Publish a built application to a store (${dvPublishStores.join(', ')}).';

  @override
  String get invocation => 'dartvel publish <store>';

  @override
  Future<void> run() async {
    final List<String> rest = argResults?.rest ?? const <String>[];
    if (rest.isEmpty) {
      Logger.log('❌ Name a store: ${dvPublishStores.join(', ')}.');
      exitCode = 64; // EX_USAGE
      return;
    }

    final String store = rest.first;
    final String root = Directory.current.path;
    final DVPublishPlan plan = dvPublishPlan(
      store: store,
      root: root,
      host: Platform.isMacOS
          ? 'macos'
          : Platform.isWindows
              ? 'windows'
              : 'linux',
    );

    if (!plan.ok) {
      Logger.log('❌ Cannot publish to $store:');
      for (final String problem in plan.problems) {
        Logger.log('   $problem');
      }
      exitCode = 78; // EX_CONFIG
      return;
    }

    final String artifact = argResults?['artifact'] as String? ?? plan.artifact;
    // Before the tooling check, because a missing artifact is the project's
    // own business and says to build first; a missing tool is the machine's.
    if (!File(artifact).existsSync()) {
      Logger.log('❌ There is nothing at $artifact to publish.');
      Logger.log('   Build it first, or pass --artifact.');
      exitCode = 66; // EX_NOINPUT
      return;
    }

    final List<String> arguments = <String>[
      for (final String argument in plan.arguments)
        if (argument == plan.artifact) artifact else argument,
    ];

    if (argResults?['dry-run'] == true) {
      Logger.log('${plan.executable} ${arguments.join(' ')}');
      return;
    }

    if (!_isOnPath(plan.toolchain)) {
      Logger.log('❌ ${plan.toolchain} is not installed, and publishing to '
          '$store is done with it.');
      Logger.log('   Install it and run this again; Dartvel will not fetch a '
          'store toolchain unattended.');
      exitCode = 69; // EX_UNAVAILABLE
      return;
    }

    Logger.log('🚀 Publishing to $store...');
    final ProcessResult result = await _processRun(
      plan.executable,
      arguments,
      workingDirectory: root,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      Logger.log('❌ ${plan.executable} exited ${result.exitCode}');
      final String error = '${result.stderr}'.trim();
      if (error.isNotEmpty) Logger.log(error);
      exitCode = result.exitCode;
      return;
    }
    Logger.log('✅ Published to $store.');
  }

  static bool _isOnPath(String executable) {
    final ProcessResult result = Process.runSync(
      Platform.isWindows ? 'where' : 'which',
      <String>[executable],
      runInShell: true,
    );
    return result.exitCode == 0;
  }
}
