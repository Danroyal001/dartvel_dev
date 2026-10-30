/// `dartvel upgrade --apply`: carry out the project plan `--plan` shows.
///
/// The plan listed what a project had to change and left every change to the
/// developer. Applying is the plan's own mechanical changes and nothing else:
/// the SDK constraint raised to the floor, each Dartvel package's constraint
/// moved to this CLI's release, the deprecated names `migrate-code` rewrites,
/// then pub resolution and the generator. A third-party constraint the target
/// cannot accept, an installed toolchain below the floor, a project newer
/// than this CLI and a module pinned elsewhere are decisions, not edits, so
/// any of them refuses the whole apply before a byte is written.
///
/// It never upgrades the CLI: `dartvel upgrade` with no flag does that, and
/// one command doing both would be two changes nobody reviewed together.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import '../adoption/adoption_plan.dart';
import '../build/sdk_floor.dart';
import '../generators/routes_generator.dart' as routes;
import '../templates/project_templates.dart';
import 'code_migrations.dart';
import 'upgrade_plan.dart';

/// Runs `pub upgrade` for [packages] in the project.
typedef DVPubUpgrade = Future<void> Function(List<String> packages);

/// Applies the upgrade plan for [root]. 0 when it was applied or there was
/// nothing to apply; 1 when it was refused, with nothing written.
Future<int> dvApplyUpgrade(
  String root, {
  required void Function(String) out,
  DVToolchainProbe? probe,
  DVGeneratedCheck? generatedCheck,
  DVPubUpgrade? pubUpgrade,
  Future<void> Function()? generate,
  Future<void> Function()? beforeWrite,
}) async {
  final File pubspecFile = File(p.join(root, 'pubspec.yaml'));
  final String original = pubspecFile.readAsStringSync();
  final DVUpgradePlan plan = await dvPlanUpgrade(
    root,
    probe: probe,
    generatedCheck: generatedCheck,
  );

  // The SDK constraint is the one blocked line that is an edit: the plan
  // names the value it has to be.
  final List<DVUpgradeItem> blockers = <DVUpgradeItem>[
    for (final DVUpgradeItem item in plan.items)
      if (item.outcome == DVUpgradeOutcome.blocked &&
          !(item.area == 'toolchain' && item.subject == 'environment.sdk'))
        item,
  ];
  if (blockers.isNotEmpty) {
    out(plan.render().trimRight());
    out('');
    out('Not applied: ${blockers.length} blocked '
        '(${blockers.map((DVUpgradeItem i) => i.subject).join(', ')}). '
        'Nothing was written.');
    return 1;
  }

  final Object? parsed = loadYaml(original);
  final YamlMap pubspec = parsed is YamlMap ? parsed : YamlMap();
  final List<(SourceRange, String)> edits = <(SourceRange, String)>[];

  if (dvSdkConstraintCheck(pubspec).outcome == DVAdoptionOutcome.blocked) {
    final Object? environment = pubspec.nodes['environment'];
    final YamlNode? sdk =
        environment is YamlMap ? environment.nodes['sdk'] : null;
    if (sdk == null) {
      out('Not applied: pubspec.yaml has no environment.sdk to raise. '
          'Nothing was written.');
      return 1;
    }
    edits.add((_range(sdk), '">=$dvDartFloor <4.0.0"'));
  }

  final List<String> resolvable = <String>[];
  for (final String section in <String>['dependencies', 'dev_dependencies']) {
    final Object? block = pubspec.nodes[section];
    if (block is! YamlMap) continue;
    for (final String name in _dartvelPackages) {
      final YamlNode? node = block.nodes[name];
      if (node is! YamlScalar || node.value is! String) continue;
      resolvable.add(name);
      final String target =
          name == 'dartvel_shelf' ? dartvelShelfVersion : dartvelPackageVersion;
      final VersionConstraint constraint;
      try {
        constraint = VersionConstraint.parse(node.value as String);
      } on FormatException {
        continue;
      }
      if (!constraint.allows(Version.parse(target))) {
        edits.add((_range(node), '^$target'));
      }
    }
  }

  final DVCodeMigrationPlan migration = dvPlanCodeMigration(root);
  final bool staleGenerated = plan.items.any((DVUpgradeItem i) =>
      i.area == 'generated' && i.outcome == DVUpgradeOutcome.changes);
  if (edits.isEmpty && migration.isEmpty && !staleGenerated) {
    out('Nothing to apply: the project is on Dartvel $dartvelPackageVersion.');
    return 0;
  }

  await beforeWrite?.call();

  // Checked before anything is written, so a file that moved under the plan
  // leaves the whole project as it was rather than half upgraded.
  if (pubspecFile.readAsStringSync() != original) {
    out('Not applied: pubspec.yaml changed since the plan was made. '
        'Nothing was written.');
    return 1;
  }
  final DVCodeMigrationApplyResult rewritten = dvApplyCodeMigration(migration);
  if (!rewritten.applied) {
    out('Not applied: ${rewritten.message}');
    return 1;
  }
  if (edits.isNotEmpty) {
    String text = original;
    // Back to front, so an earlier edit does not move a later one's offsets.
    edits.sort(((SourceRange, String) a, (SourceRange, String) b) =>
        b.$1.start.compareTo(a.$1.start));
    for (final (SourceRange range, String value) in edits) {
      text = text.replaceRange(range.start, range.end, value);
    }
    final File staged = File('${pubspecFile.path}.dartvel-upgrade')
      ..writeAsStringSync(text, flush: true);
    staged.renameSync(pubspecFile.path);
  }
  out('Applied: ${edits.length} pubspec '
      '${edits.length == 1 ? 'constraint' : 'constraints'}, '
      '${migration.rewriteCount} source '
      '${migration.rewriteCount == 1 ? 'rewrite' : 'rewrites'}.');

  if (edits.isNotEmpty && resolvable.isNotEmpty) {
    await (pubUpgrade ?? (List<String> packages) => _pubUpgrade(root, packages))(
      resolvable,
    );
  }
  await (generate ?? () => routes.generate(root_: root))();
  out('Generated. Run your tests, then `dartvel compatibility-check` before '
      'deploying.');
  return 0;
}

const List<String> _dartvelPackages = <String>[
  'dartvel_core',
  'dartvel_flutter',
  'dartvel_shelf',
  'dartvel_cli',
];

typedef SourceRange = ({int start, int end});

SourceRange _range(YamlNode node) =>
    (start: node.span.start.offset, end: node.span.end.offset);

Future<void> _pubUpgrade(String root, List<String> packages) async {
  final String pubspec = File(p.join(root, 'pubspec.yaml')).readAsStringSync();
  final bool flutter =
      RegExp(r'^\s*sdk:\s*flutter\s*$', multiLine: true).hasMatch(pubspec);
  final ProcessResult result = await Process.run(
    flutter ? 'flutter' : 'dart',
    <String>['pub', 'upgrade', ...packages],
    workingDirectory: root,
  );
  if (result.exitCode != 0) {
    throw StateError(
      'pub upgrade ${packages.join(' ')} failed; the pubspec is already '
      'upgraded, so fix resolution and run it again:\n${result.stderr}',
    );
  }
}
