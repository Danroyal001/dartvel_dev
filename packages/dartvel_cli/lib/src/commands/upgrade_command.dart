import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../graph/module_mounts.dart';
import '../templates/project_templates.dart';
import '../upgrade/project_upgrade.dart';
import '../upgrade/upgrade_plan.dart';
import 'update_command.dart';

/// Upgrade the CLI transactionally; --plan keeps project planning read-only;
/// --project moves the project's Dartvel packages to this CLI's release.
class UpgradeCommand extends Command<void> {
  UpgradeCommand() {
    argParser
      ..addFlag(
        'plan',
        negatable: false,
        help:
            'Report what the upgrade changes across the toolchain, '
            'dependencies, source, generated code, protocol, database, modules, '
            'plugins and deployment. Writes nothing.',
      )
      ..addFlag(
        'project',
        negatable: false,
        help:
            'Move the Dartvel packages in this project\'s pubspec.yaml (and '
            'its local modules) to this CLI\'s release, then resolve them. '
            'This is how a project on 0.13.x moves to 3.47 and later, which '
            '`pub upgrade` alone cannot do.',
      );
  }

  @override
  final String name = 'upgrade';

  @override
  final String description =
      'Upgrade the CLI, plan a project upgrade with --plan, or move a '
      'project to this CLI\'s release with --project.';

  @override
  String get invocation => 'dartvel upgrade [--plan | --project]';

  @override
  Future<void> run() async {
    final int code = await dvRunUpgrade(
      Directory.current.path,
      plan: argResults!['plan'] as bool,
      project: argResults!['project'] as bool,
      out: stdout.writeln,
    );
    if (code != 0) exitCode = code;
  }
}

/// Resolves the project in [directory] after its constraints moved: null when
/// it resolved, otherwise what the resolver said.
typedef DVProjectResolve =
    Future<String?> Function(String directory, {required bool flutter});

/// The body of `dartvel upgrade`: 0 when the plan has nothing blocked or the
/// project moved, 1 when it was blocked or refused.
Future<int> dvRunUpgrade(
  String root, {
  required bool plan,
  required void Function(String) out,
  bool project = false,
  Future<void> Function()? selfUpgrade,
  DVToolchainProbe? probe,
  DVGeneratedCheck? generatedCheck,
  DVProjectResolve? resolve,
}) async {
  if (plan && project) {
    out('Choose one of --plan and --project: the plan writes nothing.');
    return 1;
  }
  if (project) {
    return _upgradeProject(root, out: out, resolve: resolve ?? _pubGet);
  }
  if (!plan) {
    if (selfUpgrade != null) {
      await selfUpgrade();
    } else {
      final runner = CommandRunner<void>('dartvel', 'Dartvel CLI')
        ..addCommand(UpdateCommand());
      await runner.run(['update']);
    }
    return 0;
  }
  if (!File(p.join(root, 'pubspec.yaml')).existsSync()) {
    out('No pubspec.yaml here. Run upgrade --plan from the root of a project.');
    return 1;
  }
  final DVUpgradePlan result = await dvPlanUpgrade(
    root,
    probe: probe,
    generatedCheck: generatedCheck,
  );
  out(result.render().trimRight());
  return result.blocked ? 1 : 0;
}

Future<int> _upgradeProject(
  String root, {
  required void Function(String) out,
  required DVProjectResolve resolve,
}) async {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    out(
      'No pubspec.yaml here. Run upgrade --project from the root of a '
      'project.',
    );
    return 1;
  }

  // The project's own pubspec first, then each module whose source is a
  // folder of this project: a module left on the old line stops the parent
  // resolving with it mounted.
  final List<File> files = <File>[pubspec];
  try {
    for (final DVModuleMount mount in dvDiscoverModuleMounts(root)) {
      if (mount.deployment == DVModuleDeployment.federated) continue;
      if (mount.fromPackage || mount.sourcePath.isEmpty) continue;
      final String moduleRoot = p.normalize(p.join(root, mount.sourcePath));
      if (!p.isWithin(root, moduleRoot)) continue;
      final File modulePubspec = File(p.join(moduleRoot, 'pubspec.yaml'));
      if (modulePubspec.existsSync() &&
          !files.any((File f) => p.equals(f.path, modulePubspec.path))) {
        files.add(modulePubspec);
      }
    }
  } on Object catch (e) {
    out('dartvel.modules could not be read, so no module was moved: $e');
  }

  final Map<File, String> before = <File, String>{};
  final Map<File, DVProjectUpgrade> upgrades = <File, DVProjectUpgrade>{};
  for (final File file in files) {
    final String text = file.readAsStringSync();
    before[file] = text;
    upgrades[file] = dvUpgradeProjectPubspec(text);
  }

  String label(File file) =>
      p.relative(file.path, from: root).replaceAll(r'\', '/');

  final List<String> blocked = <String>[
    for (final MapEntry<File, DVProjectUpgrade> e in upgrades.entries)
      for (final String reason in e.value.blocked) '${label(e.key)}: $reason',
  ];
  if (blocked.isNotEmpty) {
    out('Nothing was changed.');
    blocked.forEach(out);
    return 1;
  }

  out('Moving this project to Dartvel $dartvelPackageVersion (this CLI).');
  bool changed = false;
  for (final MapEntry<File, DVProjectUpgrade> e in upgrades.entries) {
    final DVProjectUpgrade upgrade = e.value;
    if (upgrade.moved.isEmpty && upgrade.left.isEmpty) continue;
    out('');
    out(label(e.key));
    for (final DVConstraintMove move in upgrade.moved) {
      out('  ${move.package} ${move.from} → ${move.to}');
    }
    for (final DVConstraintLeft left in upgrade.left) {
      out('  ${left.package} left as it is: ${left.reason}');
    }
    if (upgrade.moved.isNotEmpty) {
      e.key.writeAsStringSync(upgrade.pubspec);
      changed = true;
    }
  }
  if (!changed) {
    out('');
    out(
      'Every Dartvel constraint already admits $dartvelPackageVersion. '
      'Nothing was changed.',
    );
    return 0;
  }

  final String? refusal = await resolve(
    root,
    flutter: _usesFlutter(before[pubspec]!),
  );
  if (refusal != null) {
    before.forEach((File file, String text) => file.writeAsStringSync(text));
    out('');
    out('The packages did not resolve, so every file was put back:');
    out(refusal.trimRight());
    return 1;
  }
  out('');
  out(
    'Resolved. Run `dartvel upgrade --plan` for what else this release '
    'changes, then build and test.',
  );
  return 0;
}

bool _usesFlutter(String pubspecText) {
  try {
    final Object? doc = loadYaml(pubspecText);
    if (doc is! YamlMap) return false;
    final Object? deps = doc['dependencies'];
    if (deps is YamlMap) {
      final Object? flutter = deps['flutter'];
      if (flutter is YamlMap && flutter['sdk'] == 'flutter') return true;
    }
    return doc['flutter'] is YamlMap;
  } on Object {
    return false;
  }
}

Future<String?> _pubGet(String directory, {required bool flutter}) async {
  final String tool = flutter ? 'flutter' : 'dart';
  final ProcessResult result;
  try {
    result = await Process.run(
      tool,
      <String>['pub', 'get'],
      workingDirectory: directory,
      runInShell: Platform.isWindows,
    );
  } on ProcessException catch (e) {
    return '`$tool pub get` could not be run: ${e.message}';
  }
  if (result.exitCode == 0) return null;
  final String said = '${result.stderr}'.trim().isEmpty
      ? '${result.stdout}'
      : '${result.stderr}';
  return '`$tool pub get` failed:\n$said';
}
