/// What `dartvel upgrade --plan` reports: what moving a project to this CLI's
/// Dartvel release would change, area by area, without changing anything.
///
/// The target is the running CLI's release. The CLI knows its own floors, the
/// constraints it writes and the rewrites it carries; it does not know another
/// release's, so a project is planned against the CLI it is being run with,
/// and `dartvel update` is how a newer target is fetched.
///
/// Every area the specification says an upgrade preserves is listed. One this
/// plan cannot check says so as `unchecked`, which is never a pass: a plan that
/// folds "could not tell" into "unchanged" tells a team they can upgrade when
/// nobody looked.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVProtocolLock;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import '../adoption/adoption_plan.dart';
import '../build/sdk_floor.dart';
import '../generators/generate_check.dart';
import '../graph/module_mounts.dart';
import '../module_trust/module_trust.dart' show dvResolvePackageRoot;
import '../templates/project_templates.dart';
import 'code_migrations.dart';

enum DVUpgradeOutcome {
  /// Checked, and the upgrade does not touch it.
  unchanged,

  /// Checked, and the upgrade changes it in the way [DVUpgradeItem.detail]
  /// says.
  changes,

  /// Checked, and the upgrade cannot happen until this is resolved.
  blocked,

  /// Not checked. The detail says why.
  unchecked,
}

/// One line of the plan.
class DVUpgradeItem {
  const DVUpgradeItem(this.area, this.subject, this.outcome, this.detail);

  /// `toolchain`, `dependencies`, `source`, `generated`, `protocol`,
  /// `database`, `modules`, `plugins` or `deployment`.
  final String area;
  final String subject;
  final DVUpgradeOutcome outcome;
  final String detail;
}

/// The installed Dart and Flutter, where they could be read.
class DVToolchainVersions {
  const DVToolchainVersions({this.dart, this.flutter});

  final String? dart;
  final String? flutter;

  @override
  bool operator ==(Object other) =>
      other is DVToolchainVersions &&
      other.dart == dart &&
      other.flutter == flutter;

  @override
  int get hashCode => Object.hash(dart, flutter);

  @override
  String toString() => 'DVToolchainVersions(dart: $dart, flutter: $flutter)';
}

typedef DVToolchainProbe = Future<DVToolchainVersions> Function();
typedef DVGeneratedCheck = Future<DVGenerateCheckResult> Function(String root);

class DVUpgradePlan {
  const DVUpgradePlan({
    required this.current,
    required this.target,
    required this.items,
  });

  /// The Dartvel the project is on, as resolved or declared, or null.
  final String? current;
  final String target;
  final List<DVUpgradeItem> items;

  bool get blocked =>
      items.any((DVUpgradeItem i) => i.outcome == DVUpgradeOutcome.blocked);

  String render() {
    final StringBuffer out = StringBuffer()
      ..writeln(
        'Upgrade plan: Dartvel ${current ?? '(version unknown)'} → '
        '$target (this CLI). Nothing has been changed.',
      );
    String? area;
    for (final DVUpgradeItem item in items) {
      if (item.area != area) {
        area = item.area;
        out
          ..writeln()
          ..writeln(area);
      }
      out.writeln('  [${item.outcome.name}] ${item.subject}: ${item.detail}');
    }
    final Map<DVUpgradeOutcome, int> counts = <DVUpgradeOutcome, int>{
      for (final DVUpgradeOutcome o in DVUpgradeOutcome.values)
        o: items.where((DVUpgradeItem i) => i.outcome == o).length,
    };
    out
      ..writeln()
      ..writeln(
        '${counts[DVUpgradeOutcome.blocked]} blocked, '
        '${counts[DVUpgradeOutcome.changes]} to change, '
        '${counts[DVUpgradeOutcome.unchanged]} unchanged, '
        '${counts[DVUpgradeOutcome.unchecked]} not checked.',
      );
    return out.toString();
  }
}

const List<String> _dartvelPackages = <String>[
  'dartvel_core',
  'dartvel_flutter',
  'dartvel_shelf',
  'dartvel_cli',
];

/// Plans the upgrade of the project at [root], writing nothing.
Future<DVUpgradePlan> dvPlanUpgrade(
  String root, {
  DVToolchainProbe? probe,
  DVGeneratedCheck? generatedCheck,
}) async {
  final String pubspecText = File(
    p.join(root, 'pubspec.yaml'),
  ).readAsStringSync();
  final Object? parsed = loadYaml(pubspecText);
  final YamlMap pubspec = parsed is YamlMap ? parsed : YamlMap();
  final bool flutter = _isFlutter(pubspec);
  final Map<String, String> locked = _lockedVersions(root);
  final List<DVUpgradeItem> items = <DVUpgradeItem>[];

  // toolchain
  items.add(
    _fromAdoption(
      'toolchain',
      dvSdkConstraintCheck(pubspec),
      blockedHint: 'set it to ">=$dvDartFloor <4.0.0"',
    ),
  );
  final DVToolchainVersions installed =
      await (probe ?? () => dvProbeToolchain(flutter: flutter))();
  items.add(
    _installed('installed Dart', installed.dart, dvDartFloor, 'dart --version'),
  );
  if (flutter) {
    items.add(
      _installed(
        'installed Flutter',
        installed.flutter,
        dvFlutterFloor,
        'flutter --version',
      ),
    );
  }

  // dependencies
  for (final String name in _dartvelPackages) {
    final DVUpgradeItem? item = _dartvelPackage(pubspec, locked, name);
    if (item != null) items.add(item);
  }
  if (_declaration(pubspec, 'dartvel_generator') != null) {
    items.add(
      const DVUpgradeItem(
        'dependencies',
        'dartvel_generator',
        DVUpgradeOutcome.changes,
        'its build_runner builders are retired and removed in 2.0.0; the CLI '
            'generates the whole client, so remove it, and remove build_runner '
            'too unless another package\'s builders use it',
      ),
    );
  }
  final List<String> wanted = <String>[
    'dartvel_core',
    if (flutter || _declaration(pubspec, 'dartvel_flutter') != null)
      'dartvel_flutter',
  ];
  for (final DVAdoptionCheck check in dvSharedDependencyChecks(
    pubspec,
    wanted,
  )) {
    items.add(_fromAdoption('dependencies', check));
  }

  // source
  final DVCodeMigrationPlan migration = dvPlanCodeMigration(root);
  if (migration.isEmpty) {
    items.add(
      DVUpgradeItem(
        'source',
        'deprecated names',
        DVUpgradeOutcome.unchanged,
        'none of the ${dvCodeMigrationRules.length} names migrate-code rewrites '
            'is used',
      ),
    );
  } else {
    final String byRule =
        (migration.countsByRule.entries.toList()..sort(
              (MapEntry<String, int> a, MapEntry<String, int> b) =>
                  a.key.compareTo(b.key),
            ))
            .map((MapEntry<String, int> e) => '${e.key} ${e.value}')
            .join(', ');
    items.add(
      DVUpgradeItem(
        'source',
        'deprecated names',
        DVUpgradeOutcome.changes,
        '${migration.rewriteCount} '
            '${migration.rewriteCount == 1 ? 'rewrite' : 'rewrites'} ($byRule) in '
            '${migration.files.keys.join(', ')}; run '
            '`dartvel migrate-code` to see each line and '
            '`dartvel migrate-code --apply` to write them',
      ),
    );
  }

  // generated
  items.add(await _generated(root, generatedCheck ?? dvGenerateCheck));

  // protocol
  items.add(_protocol(root));

  // database, plugins, deployment
  items
    ..add(
      const DVUpgradeItem(
        'database',
        'database',
        DVUpgradeOutcome.unchecked,
        'the plan carries no list of schema changes between Dartvel releases '
            'to compare; `dartvel db migrate --plan` classifies the pending '
            'changes to this project\'s own models',
      ),
    )
    ..addAll(_modules(root, locked))
    ..add(
      const DVUpgradeItem(
        'plugins',
        'plugins',
        DVUpgradeOutcome.unchecked,
        'plugins declare no Dartvel version range the plan can read',
      ),
    )
    ..add(
      const DVUpgradeItem(
        'deployment',
        'deployment',
        DVUpgradeOutcome.unchecked,
        'the plan cannot see what a deployed environment runs; after upgrading, '
            '`dartvel compatibility-check --against <environment>` holds the '
            'build against its clients',
      ),
    );

  final String? current =
      locked['dartvel_core'] ??
      _constraintText(_declaration(pubspec, 'dartvel_core'));
  return DVUpgradePlan(
    current: current,
    target: dartvelPackageVersion,
    items: items,
  );
}

/// Reads the installed toolchain: `flutter --version --machine` for a Flutter
/// project, which names both, else `dart --version`.
Future<DVToolchainVersions> dvProbeToolchain({required bool flutter}) async {
  Future<String?> run(String exe, List<String> args) async {
    try {
      final ProcessResult result = await Process.run(
        exe,
        args,
        runInShell: Platform.isWindows,
      );
      if (result.exitCode != 0) return null;
      return '${result.stdout}\n${result.stderr}';
    } on Object {
      return null;
    }
  }

  final DVToolchainVersions fromFlutter = flutter
      ? dvParseToolchainVersions(
          flutterMachine: await run('flutter', <String>[
            '--version',
            '--machine',
          ]),
        )
      : const DVToolchainVersions();
  if (fromFlutter.dart != null) return fromFlutter;
  final DVToolchainVersions fromDart = dvParseToolchainVersions(
    dartVersion: await run('dart', <String>['--version']),
  );
  return DVToolchainVersions(dart: fromDart.dart, flutter: fromFlutter.flutter);
}

/// The versions in `flutter --version --machine` or `dart --version` output.
DVToolchainVersions dvParseToolchainVersions({
  String? flutterMachine,
  String? dartVersion,
}) {
  String? dart;
  String? flutter;
  if (flutterMachine != null) {
    final int start = flutterMachine.indexOf('{');
    final int end = flutterMachine.lastIndexOf('}');
    if (start != -1 && end > start) {
      try {
        final Object? json = jsonDecode(
          flutterMachine.substring(start, end + 1),
        );
        if (json is Map) {
          if (json['frameworkVersion'] is String) {
            flutter = json['frameworkVersion'] as String;
          }
          if (json['dartSdkVersion'] is String) {
            dart = (json['dartSdkVersion'] as String).split(' ').first;
          }
        }
      } on FormatException {
        // Unreadable, so unchecked.
      }
    }
  }
  if (dartVersion != null) {
    final RegExpMatch? match = RegExp(
      r'Dart SDK version:\s*(\S+)',
    ).firstMatch(dartVersion);
    dart ??= match?.group(1);
  }
  return DVToolchainVersions(dart: dart, flutter: flutter);
}

DVUpgradeItem _fromAdoption(
  String area,
  DVAdoptionCheck check, {
  String? blockedHint,
}) => DVUpgradeItem(
  area,
  check.subject,
  switch (check.outcome) {
    DVAdoptionOutcome.ok => DVUpgradeOutcome.unchanged,
    DVAdoptionOutcome.blocked => DVUpgradeOutcome.blocked,
    DVAdoptionOutcome.unchecked => DVUpgradeOutcome.unchecked,
  },
  check.outcome == DVAdoptionOutcome.blocked && blockedHint != null
      ? '${check.detail}; $blockedHint'
      : check.detail,
);

DVUpgradeItem _installed(
  String subject,
  String? version,
  String floor,
  String command,
) {
  if (version == null) {
    return DVUpgradeItem(
      'toolchain',
      subject,
      DVUpgradeOutcome.unchecked,
      '`$command` could not be run or read',
    );
  }
  final Version parsed;
  try {
    parsed = Version.parse(version);
  } on FormatException {
    return DVUpgradeItem(
      'toolchain',
      subject,
      DVUpgradeOutcome.unchecked,
      '"$version" is not a version this plan can compare',
    );
  }
  // A prerelease of the floor is what a beta channel ships before it, and
  // counts as the floor: the stable release is not what decides a dev build.
  final Version floorVersion = Version.parse(floor);
  final Version comparable = Version(parsed.major, parsed.minor, parsed.patch);
  if (comparable < floorVersion) {
    return DVUpgradeItem(
      'toolchain',
      subject,
      DVUpgradeOutcome.blocked,
      '$version is older than the $floor Dartvel $dartvelPackageVersion '
          'needs; upgrade it first',
    );
  }
  return DVUpgradeItem(
    'toolchain',
    subject,
    DVUpgradeOutcome.unchanged,
    '$version meets $floor',
  );
}

DVUpgradeItem? _dartvelPackage(
  YamlMap pubspec,
  Map<String, String> locked,
  String name,
) {
  final Object? declared = _declaration(pubspec, name);
  if (declared == null) return null;
  final String targetText = name == 'dartvel_shelf'
      ? dartvelShelfVersion
      : dartvelPackageVersion;
  final Version target = Version.parse(targetText);
  if (declared is _Override) {
    return DVUpgradeItem(
      'dependencies',
      name,
      DVUpgradeOutcome.unchecked,
      'overridden in dependency_overrides, which bypasses constraint '
          'solving; set the override to $targetText by hand',
    );
  }
  final String? text = _constraintText(declared);
  if (text == null) {
    return DVUpgradeItem(
      'dependencies',
      name,
      DVUpgradeOutcome.unchecked,
      'declared from a path, git or SDK source, which has no version to '
          'compare with $targetText',
    );
  }
  final VersionConstraint constraint;
  try {
    constraint = VersionConstraint.parse(text);
  } on FormatException {
    return DVUpgradeItem(
      'dependencies',
      name,
      DVUpgradeOutcome.unchecked,
      '"$text" is not a constraint this plan can read',
    );
  }

  Version? resolved;
  try {
    resolved = locked[name] == null ? null : Version.parse(locked[name]!);
  } on FormatException {
    resolved = null;
  }
  final bool newer =
      (resolved != null && resolved > target) ||
      (!constraint.allows(target) &&
          constraint is VersionRange &&
          constraint.min != null &&
          constraint.min! > target);
  if (newer) {
    return DVUpgradeItem(
      'dependencies',
      name,
      DVUpgradeOutcome.blocked,
      'the project is on ${resolved ?? text}, newer than this CLI\'s '
          '$targetText; run `dartvel update` and plan again rather than moving '
          'backwards',
    );
  }
  if (!constraint.allows(target)) {
    return DVUpgradeItem(
      'dependencies',
      name,
      DVUpgradeOutcome.changes,
      'constraint "$text" excludes $targetText; change it to ^$targetText '
          'and run pub upgrade',
    );
  }
  if (resolved == target) {
    return DVUpgradeItem(
      'dependencies',
      name,
      DVUpgradeOutcome.unchanged,
      '"$text" resolves to $targetText already',
    );
  }
  return DVUpgradeItem(
    'dependencies',
    name,
    DVUpgradeOutcome.changes,
    '"$text" admits $targetText; `pub upgrade $name` moves it from '
        '${resolved ?? 'an unresolved version (no pubspec.lock entry)'} to '
        '$targetText',
  );
}

Future<DVUpgradeItem> _generated(String root, DVGeneratedCheck check) async {
  const String subject = 'generated output';
  if (!Directory(p.join(root, 'lib', 'dartvel_client')).existsSync()) {
    return const DVUpgradeItem(
      'generated',
      subject,
      DVUpgradeOutcome.unchecked,
      'there is no lib/dartvel_client to compare with; this CLI generates '
          'it from scratch on the next build',
    );
  }
  final DVGenerateCheckResult result;
  try {
    result = await check(root);
  } on Object catch (e) {
    return DVUpgradeItem(
      'generated',
      subject,
      DVUpgradeOutcome.unchecked,
      'this CLI\'s generator did not finish on a copy of the project: $e',
    );
  }
  if (result.stale.isEmpty && result.unstable.isEmpty) {
    return const DVUpgradeItem(
      'generated',
      subject,
      DVUpgradeOutcome.unchanged,
      'this CLI\'s generator writes the same bytes the project has',
    );
  }
  final List<String> lines = <String>[
    for (final String path in result.stale)
      result.lineChanges[path] == null
          ? path
          : '$path +${result.lineChanges[path]!.$1} '
                '-${result.lineChanges[path]!.$2}',
  ];
  const int shown = 20;
  final String listed = lines.length <= shown
      ? lines.join(', ')
      : '${lines.take(shown).join(', ')} and ${lines.length - shown} more';
  return DVUpgradeItem(
    'generated',
    subject,
    DVUpgradeOutcome.changes,
    '${result.stale.length} files change when regenerated (DV-GEN-003): '
        '$listed. `dartvel routes` writes them'
        '${result.unstable.isEmpty ? '' : '; ${result.unstable.length} came out '
                  'different between two runs on the same input (DV-GEN-002): '
                  '${result.unstable.join(', ')}'}',
  );
}

DVUpgradeItem _protocol(String root) {
  final File file = File(p.join(root, DVProtocolLock.fileName));
  if (!file.existsSync()) {
    return const DVUpgradeItem(
      'protocol',
      'protocol',
      DVUpgradeOutcome.unchecked,
      'no ${DVProtocolLock.fileName}, so the project has no recorded '
          'protocol to compare the upgrade with',
    );
  }
  final DVProtocolLock lock;
  try {
    lock = DVProtocolLock.decode(file.readAsStringSync());
  } on FormatException catch (e) {
    return DVUpgradeItem(
      'protocol',
      'protocol',
      DVUpgradeOutcome.blocked,
      '${DVProtocolLock.fileName} cannot be trusted: ${e.message}',
    );
  }
  return DVUpgradeItem(
    'protocol',
    'protocol',
    DVUpgradeOutcome.unchecked,
    'protocol ${lock.current?.protocol ?? '(none)'} is recorded, but '
        'nothing derives the contract from the project yet, so whether this '
        'upgrade moves it is not checked; run `dartvel compatibility-check` '
        'after upgrading',
  );
}

List<DVUpgradeItem> _modules(String root, Map<String, String> locked) {
  final List<DVModuleMount> mounts;
  try {
    mounts = dvDiscoverModuleMounts(root);
  } on Object catch (e) {
    return <DVUpgradeItem>[
      DVUpgradeItem(
        'modules',
        'modules',
        DVUpgradeOutcome.unchecked,
        'dartvel.modules could not be read: $e',
      ),
    ];
  }
  final List<DVUpgradeItem> items = <DVUpgradeItem>[];
  for (final DVModuleMount mount in mounts) {
    final String subject = 'module ${mount.id}';
    if (mount.deployment == DVModuleDeployment.federated) {
      items.add(
        DVUpgradeItem(
          'modules',
          subject,
          DVUpgradeOutcome.unchecked,
          'federated, so it is built and deployed on its own Dartvel',
        ),
      );
      continue;
    }
    final String? moduleRoot = mount.fromPackage
        ? dvResolvePackageRoot(root, mount.packageName)
        : (mount.sourcePath.isEmpty ? null : p.join(root, mount.sourcePath));
    final File modulePubspec = File(p.join(moduleRoot ?? '', 'pubspec.yaml'));
    if (moduleRoot == null || !modulePubspec.existsSync()) {
      items.add(
        DVUpgradeItem(
          'modules',
          subject,
          DVUpgradeOutcome.unchecked,
          'its project could not be found to read',
        ),
      );
      continue;
    }
    final Object? doc = loadYaml(modulePubspec.readAsStringSync());
    final YamlMap yaml = doc is YamlMap ? doc : YamlMap();
    final List<String> blocked = <String>[];
    final List<String> unreadable = <String>[];
    final List<String> fine = <String>[];
    for (final String name in _dartvelPackages) {
      final Object? declared = _declaration(yaml, name);
      if (declared == null) continue;
      final String target = name == 'dartvel_shelf'
          ? dartvelShelfVersion
          : dartvelPackageVersion;
      final String? text = declared is _Override
          ? null
          : _constraintText(declared);
      VersionConstraint? constraint;
      try {
        constraint = text == null ? null : VersionConstraint.parse(text);
      } on FormatException {
        constraint = null;
      }
      if (constraint == null) {
        unreadable.add(name);
      } else if (constraint.allows(Version.parse(target))) {
        fine.add('$name "$text"');
      } else {
        blocked.add('$name "$text" excludes $target');
      }
    }
    if (blocked.isNotEmpty) {
      items.add(
        DVUpgradeItem(
          'modules',
          subject,
          DVUpgradeOutcome.blocked,
          '${blocked.join('; ')}; the module has to move first, or the parent '
              'cannot resolve with it mounted',
        ),
      );
    } else if (fine.isEmpty) {
      items.add(
        DVUpgradeItem(
          'modules',
          subject,
          DVUpgradeOutcome.unchecked,
          unreadable.isEmpty
              ? 'it declares no Dartvel package version to compare'
              : '${unreadable.join(', ')} come from a path, git or override, '
                    'which has no version to compare',
        ),
      );
    } else {
      items.add(
        DVUpgradeItem(
          'modules',
          subject,
          DVUpgradeOutcome.unchanged,
          '${fine.join(', ')} admits this release',
        ),
      );
    }
  }
  return items;
}

bool _isFlutter(YamlMap pubspec) {
  final Object? deps = pubspec['dependencies'];
  if (deps is YamlMap) {
    final Object? flutter = deps['flutter'];
    if (flutter is YamlMap && flutter['sdk'] == 'flutter') return true;
  }
  return pubspec['flutter'] is YamlMap;
}

class _Override {
  const _Override();
}

Object? _declaration(YamlMap pubspec, String name) {
  for (final String section in <String>[
    'dependency_overrides',
    'dependencies',
    'dev_dependencies',
  ]) {
    final Object? block = pubspec[section];
    if (block is YamlMap && block.containsKey(name)) {
      return section == 'dependency_overrides'
          ? const _Override()
          : (block[name] ?? 'any');
    }
  }
  return null;
}

String? _constraintText(Object? declared) {
  if (declared is String) return declared;
  if (declared is YamlMap && declared['version'] is String) {
    return declared['version'] as String;
  }
  return null;
}

Map<String, String> _lockedVersions(String root) {
  final File lock = File(p.join(root, 'pubspec.lock'));
  if (!lock.existsSync()) return const <String, String>{};
  try {
    final Object? doc = loadYaml(lock.readAsStringSync());
    final Object? packages = doc is YamlMap ? doc['packages'] : null;
    if (packages is! YamlMap) return const <String, String>{};
    return <String, String>{
      for (final MapEntry<Object?, Object?> e in packages.entries)
        if (e.value is YamlMap && (e.value! as YamlMap)['version'] is String)
          '${e.key}': (e.value! as YamlMap)['version'] as String,
    };
  } on Object {
    return const <String, String>{};
  }
}
