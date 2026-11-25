import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import '../graph/module_mounts.dart';
import '../module_trust/module_lock.dart';
import '../templates/project_templates.dart';
import '../upgrade/design_imports.dart';
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
typedef DVProjectResolve = Future<String?> Function(
  String directory, {
  required bool flutter,
});

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
  DVDesignFix? designFix,
}) async {
  if (plan && project) {
    out('Choose one of --plan and --project: the plan writes nothing.');
    return 1;
  }
  if (project) {
    return _upgradeProject(
      root,
      out: out,
      designFix: designFix ?? dvRunDesignFix,
      resolve:
          resolve ??
          (String directory, {required bool flutter}) => _pubUpgrade(
            directory,
            flutter: flutter,
            packages: _lockedDartvel(directory).keys.toList(),
          ),
    );
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
  required DVDesignFix designFix,
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
  // A module `dartvel add` generated is pinned byte for byte by its wrapper
  // hash in dartvel.module.lock. Editing its pubspec here would read as a
  // hand edit (DV-MODULE-016); regenerating it is what moves it.
  final Map<String, DVModulePin> pins = DVModuleLock.read(root).pins;
  final List<String> regenerate = <String>[];
  try {
    for (final DVModuleMount mount in dvDiscoverModuleMounts(root)) {
      if (mount.deployment == DVModuleDeployment.federated) continue;
      if (mount.fromPackage || mount.sourcePath.isEmpty) continue;
      if (pins[mount.packageName]?.wrapperHash != null) {
        regenerate.add(mount.id);
        continue;
      }
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
  for (final String id in regenerate) {
    out('');
    out(
      'module $id was generated by dartvel add and its lock pins every '
      'byte, so it is not edited here. Run `dartvel add --refresh $id` '
      'to regenerate it for this release.',
    );
  }
  // Flutter 3.50 deprecates flutter/material and flutter/cupertino for the
  // material_ui and cupertino_ui packages Dartvel now builds on. Each
  // package root (the project, each module) gets the packages it needs, and
  // its imports are rewritten once they resolve.
  final Map<File, Map<String, Set<String>>> designImports =
      <File, Map<String, Set<String>>>{};
  final Map<File, List<DVDesignLibrary>> designAdded =
      <File, List<DVDesignLibrary>>{};
  for (final File file in files) {
    final Map<String, Set<String>> found = dvFindDesignImports(file.parent.path);
    designImports[file] = found;
    final List<DVDesignLibrary> needed = dvDesignDependenciesNeeded(
      before[file]!,
      <String>{for (final Set<String> libraries in found.values) ...libraries},
    );
    if (needed.isNotEmpty) designAdded[file] = needed;
  }

  bool changed = false;
  for (final MapEntry<File, DVProjectUpgrade> e in upgrades.entries) {
    final DVProjectUpgrade upgrade = e.value;
    final List<DVDesignLibrary> added =
        designAdded[e.key] ?? const <DVDesignLibrary>[];
    if (upgrade.moved.isEmpty && upgrade.left.isEmpty && added.isEmpty) {
      continue;
    }
    out('');
    out(label(e.key));
    for (final DVConstraintMove move in upgrade.moved) {
      out('  ${move.package} ${move.from} → ${move.to}');
    }
    for (final DVDesignLibrary library in added) {
      out(
        '  ${library.package} ^${library.version} added: it replaces '
        '${library.deprecated}, which Flutter 3.50 deprecates',
      );
    }
    for (final DVConstraintLeft left in upgrade.left) {
      out('  ${left.package} left as it is: ${left.reason}');
    }
    if (upgrade.moved.isNotEmpty || added.isNotEmpty) {
      e.key.writeAsStringSync(dvAddDesignDependencies(upgrade.pubspec, added));
      changed = true;
    }
  }
  final List<File> toFix = <File>[
    for (final File file in files)
      if (designImports[file]!.isNotEmpty) file,
  ];
  // A constraint that admits the release does not move the lock: `^3.47.0`
  // admits 3.47.1, and pub keeps the 3.47.0 it already resolved. So the
  // lock is read too, and a Dartvel package resolved below this release is
  // upgraded to it.
  final List<String> behind = <String>[
    for (final MapEntry<String, Version> locked in _lockedDartvel(root).entries)
      if (locked.value < Version.parse(_releaseOf(locked.key)))
        '${locked.key} ${locked.value} → ${_releaseOf(locked.key)}',
  ];
  if (!changed && behind.isEmpty && toFix.isEmpty) {
    out('');
    out(
      'Every Dartvel constraint already admits $dartvelPackageVersion '
      'and resolves to it. Nothing was changed.',
    );
    return 0;
  }
  if (behind.isNotEmpty) {
    out('');
    out('pubspec.lock');
    for (final String line in behind) {
      out('  $line');
    }
  }

  if (changed || behind.isNotEmpty) {
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
  }

  // The imports, by Flutter's own fix, once the packages they move to
  // resolve. A module is resolved on its own first: the fix analyzes the
  // package it runs in.
  final List<String> unfixed = <String>[];
  for (final File file in toFix) {
    final String directory = file.parent.path;
    final String where = p.equals(directory, root) ? 'this project' : label(file);
    out('');
    out(
      'Moving the imports in $where to material_ui/cupertino_ui: '
      '`${dvDesignFixCommand.join(' ')}`',
    );
    if (!p.equals(directory, root)) {
      final String? refusal = await resolve(
        directory,
        flutter: _usesFlutter(file.readAsStringSync()),
      );
      if (refusal != null) {
        unfixed.add('$where did not resolve, so its imports were not moved:\n'
            '${refusal.trimRight()}');
        continue;
      }
    }
    final String? failure = await designFix(directory);
    if (failure != null) {
      unfixed.add('${failure.trimRight()}\nRun '
          '`${dvDesignFixCommand.join(' ')}` in $where once it is fixed.');
      continue;
    }
    final Map<String, Set<String>> left = dvFindDesignImports(directory);
    for (final MapEntry<String, Set<String>> e in left.entries) {
      final String path = p.equals(directory, root)
          ? e.key
          : '${p.relative(directory, from: root).replaceAll(r'\', '/')}/${e.key}';
      unfixed.add(
        '$path still names ${e.value.join(' and ')}; replace it with '
        '${e.value.map((String l) => dvDesignLibraries.firstWhere((DVDesignLibrary d) => d.deprecated == l).replacement).join(' and ')}',
      );
    }
  }
  if (unfixed.isNotEmpty) {
    out('');
    out(
      'The packages resolved, but not every import moved off Flutter\'s '
      'deprecated design libraries:',
    );
    unfixed.forEach(out);
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

String _releaseOf(String package) =>
    package == 'dartvel_shelf' ? dartvelShelfVersion : dartvelPackageVersion;

/// The released Dartvel packages pubspec.lock resolves, and to what.
Map<String, Version> _lockedDartvel(String root) {
  final File lock = File(p.join(root, 'pubspec.lock'));
  if (!lock.existsSync()) return const <String, Version>{};
  try {
    final Object? doc = loadYaml(lock.readAsStringSync());
    final Object? packages = doc is YamlMap ? doc['packages'] : null;
    if (packages is! YamlMap) return const <String, Version>{};
    return <String, Version>{
      for (final String name in dvReleasedPackages)
        if (packages[name] is YamlMap &&
            (packages[name] as YamlMap)['source'] == 'hosted' &&
            (packages[name] as YamlMap)['version'] is String)
          name: Version.parse((packages[name] as YamlMap)['version'] as String),
    };
  } on Object {
    return const <String, Version>{};
  }
}

/// `pub upgrade` of the Dartvel packages, which moves a lock that `pub get`
/// would keep; `pub get` when the lock names none.
Future<String?> _pubUpgrade(
  String directory, {
  required bool flutter,
  required List<String> packages,
}) async {
  final String tool = flutter ? 'flutter' : 'dart';
  final List<String> args = packages.isEmpty
      ? <String>['pub', 'get']
      : <String>['pub', 'upgrade', ...packages];
  final ProcessResult result;
  try {
    result = await Process.run(
      tool,
      args,
      workingDirectory: directory,
      runInShell: Platform.isWindows,
    );
  } on ProcessException catch (e) {
    return '`$tool ${args.join(' ')}` could not be run: ${e.message}';
  }
  if (result.exitCode == 0) return null;
  final String said = '${result.stderr}'.trim().isEmpty
      ? '${result.stdout}'
      : '${result.stderr}';
  return '`$tool ${args.join(' ')}` failed:\n$said';
}
