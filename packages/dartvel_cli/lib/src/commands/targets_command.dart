import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../build/build_target.dart';
import '../build/runtime_packages.dart';
import '../build/target_packages.dart';
import '../utils/build_runner.dart' show hasPubDependency;
import '../utils/logger.dart';
import 'build_command.dart' show buildPlatformArguments;

/// Where the paid targets package lives until it has a hosted repository.
const String dvTargetsProGitUrl =
    'https://github.com/Danroyal001/dartvel_enterprise.git';

/// The package's directory inside [dvTargetsProGitUrl].
const String dvTargetsProGitPath = 'packages/dartvel_targets_pro';

/// The paid runtimes package's directory inside [dvTargetsProGitUrl].
const String dvRuntimesProGitPath = 'packages/dartvel_runtimes_pro';

typedef TargetsProcessRun = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

/// `dartvel targets`: what this install can build, and adding the paid
/// targets package to a project.
class TargetsCommand extends Command<void> {
  TargetsCommand({this.root, TargetsProcessRun? processRun})
      : _processRun = processRun ?? _run {
    // `add` is read from the arguments rather than registered as a
    // subcommand: a command with subcommands cannot run on its own, and
    // `dartvel targets` alone is the listing.
    argParser
      ..addOption('path',
          help: 'With add: a local checkout of the package, instead of the '
              'git repository (for development). For `add pro`, the runtimes '
              'package is taken from beside it.')
      ..addOption('git-url',
          defaultsTo: dvTargetsProGitUrl,
          help: 'With add: the repository the package is fetched from.')
      ..addOption('git-ref', help: 'With add: a branch, tag or commit to pin.');
  }

  @override
  String get invocation => 'dartvel targets [add pro|runtimes]';

  /// The project; the working directory when null.
  final String? root;
  final TargetsProcessRun _processRun;

  static Future<ProcessResult> _run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) =>
      Process.run(executable, arguments,
          workingDirectory: workingDirectory, runInShell: true);

  String get _root => root ?? Directory.current.path;

  @override
  final String name = 'targets';

  @override
  final String description =
      'List the build targets this install can build, and add the paid '
      'packages: dartvel targets add pro (targets and runtimes) or '
      'dartvel targets add runtimes (runtimes only).';

  @override
  Future<void> run() async {
    final List<String> rest = argResults?.rest ?? const <String>[];
    if (rest.isNotEmpty) {
      if (rest.first != 'add') {
        Logger.log('❌ Unknown: dartvel targets ${rest.join(' ')}. '
            'Run dartvel targets, or dartvel targets add pro.');
        exitCode = 64; // EX_USAGE
        return;
      }
      await _add(rest.skip(1).toList());
      return;
    }
    final String project = _root;
    final List<DVTargetPackage> packages = dvTargetPackages(project);
    Logger.log('Free targets (built by this CLI):');
    Logger.log('  ${buildPlatformArguments.where((String t) => t != 'all').join(', ')}');
    Logger.log('');
    Logger.log('Paid targets (any Dartvel Cloud plan; dartvel build <target> '
        '--cloud builds them without installing anything):');
    for (final MapEntry<String, String> target in dvPaidTargets.entries) {
      final DVTargetPackage? provider = <DVTargetPackage?>[
        for (final DVTargetPackage package in packages)
          if (package.targets.contains(target.key)) package,
        null,
      ].first;
      final String status = DVBuildTargets.lookup(target.key) != null
          ? 'available'
          : provider != null
              ? 'available through ${provider.name}'
              : 'not installed';
      Logger.log('  ${target.key.padRight(18)} ${target.value} [$status]');
    }
    for (final DVBuildTarget target in DVBuildTargets.all) {
      if (dvPaidTargets.containsKey(target.name)) continue;
      Logger.log('  ${target.name.padRight(18)} ${target.summary} [available]');
    }
    if (packages.isEmpty) {
      Logger.log('');
      Logger.log('To build paid targets on this machine: dartvel targets add pro');
    }
  }

  Future<void> _add(List<String> rest) async {
    if (rest.length != 1 || (rest.single != 'pro' && rest.single != 'runtimes')) {
      Logger.log('❌ Name the package to add: dartvel targets add pro, or '
          'dartvel targets add runtimes');
      exitCode = 64; // EX_USAGE
      return;
    }
    final String project = _root;
    if (!File('$project/pubspec.yaml').existsSync()) {
      Logger.log('❌ No pubspec.yaml here. Run this in a Dartvel project.');
      exitCode = 66; // EX_NOINPUT
      return;
    }
    final String? path = argResults?['path'] as String?;
    final String? ref = argResults?['git-ref'] as String?;
    final bool targets = rest.single == 'pro';
    // With --path: the checkout of the package being added, and for `pro` the
    // runtimes package is its sibling.
    Map<String, Object?> sourceOf(String gitPath) => path != null
        ? <String, Object?>{
            'path': gitPath == dvRuntimesProGitPath && targets
                ? '$path/../dartvel_runtimes_pro'
                : path,
          }
        : <String, Object?>{
            'git': <String, Object?>{
              'url': argResults?['git-url'] as String,
              'path': gitPath,
              if (ref != null) 'ref': ref,
            },
          };
    final String tool =
        hasPubDependency(project, 'flutter') ? 'flutter' : 'dart';
    final List<String> arguments = <String>[
      'pub',
      'add',
      // The build targets run in the CLI, so they are a dev dependency; the
      // runtimes run inside the application and its server, so they are not.
      if (targets) 'dev:$dvTargetsProPackage:${jsonEncode(sourceOf(dvTargetsProGitPath))}',
      '$dvRuntimesProPackage:${jsonEncode(sourceOf(dvRuntimesProGitPath))}',
    ];
    Logger.log('   $tool ${arguments.join(' ')}');
    final ProcessResult result = await _processRun(tool, arguments,
        workingDirectory: project);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      Logger.log('❌ The paid packages could not be added. Fetching them '
          'needs read access to its repository, which comes with a Dartvel '
          'Cloud plan; check that git can reach $dvTargetsProGitUrl.');
      exitCode = result.exitCode;
      return;
    }
    Logger.log('✅ ${targets ? '$dvTargetsProPackage and ' : ''}'
        '$dvRuntimesProPackage added. `dartvel targets` lists what they '
        'provide; `dartvel build <target>` builds one.');
  }
}
