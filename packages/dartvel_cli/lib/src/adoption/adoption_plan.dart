/// What `dartvel init` would do to a project that already exists, and whether
/// it can.
///
/// Adoption says `init` adds the dependency and the `dartvel:` key and nothing
/// else. So the plan is one file's worth of insertions, computed as text
/// rather than by re-emitting YAML: a pubspec re-serialized from its parsed
/// form is equal as data and has lost every comment, every blank line and the
/// team's key order, which is a diff nobody would accept from a tool they were
/// only trying out.
///
/// The plan is built without writing anything, shown, and then applied by
/// [dvApplyAdoption] in one rename -- or not at all.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import '../build/sdk_floor.dart';
import '../templates/project_templates.dart';

/// How one compatibility check came out.
///
/// [unchecked] is its own outcome, not a pass: a report that folds "could not
/// tell" into "compatible" tells a team they can adopt when nobody looked.
enum DVAdoptionOutcome { ok, blocked, unchecked }

/// One line of the compatibility report.
class DVAdoptionCheck {
  const DVAdoptionCheck(this.subject, this.outcome, this.detail);

  /// What was checked: `environment.sdk`, or a package name.
  final String subject;
  final DVAdoptionOutcome outcome;
  final String detail;
}

/// The direct dependencies of the packages `init` adds, as their pubspecs
/// declare them.
///
/// Held here rather than read at run time because an installed CLI has no
/// sibling package directories to read; the adoption test compares this
/// table with the pubspecs, so it cannot drift from them silently.
const Map<String, Map<String, String>> dvDartvelDependencyConstraints =
    <String, Map<String, String>>{
  'dartvel_core': <String, String>{
    'meta': '^1.12.0',
    'async': '^2.13.1',
    'crypto': '^3.0.7',
    'http': '^1.6.0',
    'ffi': '^2.1.0',
    'mime': '^1.0.4',
    'http_parser': '^4.0.2',
    'shelf_multipart': '^1.0.0',
    'sqlite3': '^2.9.4',
    'drift': '^2.14.0',
    'pointycastle': '^4.0.0',
    'xml': '^6.5.0',
    'hooks': '^0.20.1',
    'code_assets': '^0.19.7',
  },
  'dartvel_flutter': <String, String>{
    'path': '^1.9.0',
    'web': '^1.0.0',
    'seo': '^0.0.10',
    'go_router': '^14.2.0',
    'mix': '^2.2.0-beta.5',
    'flutter_riverpod': '^2.5.1',
    'ffi': '^2.1.0',
    'meta': '^1.15.0',
    'dartvel_core': '^0.5.0',
    'jni': '^1.0.3',
    'dbus': '^0.7.15',
  },
};

/// The plan for one project.
class DVAdoptionPlan {
  const DVAdoptionPlan._({
    required this.root,
    this.refusal,
    this.original,
    this.edited,
    this.isFlutter = false,
    this.alreadyInitialized = false,
    this.addedDependencies = const <String>[],
    this.checks = const <DVAdoptionCheck>[],
    this.mapping = const <String, String>{},
    this.mappingReasons = const <String>[],
    this.coexistence = const <String>[],
  });

  final String root;

  /// Why `init` will not touch this project at all, or null.
  final String? refusal;

  /// The pubspec as it was read, byte for byte. [dvApplyAdoption] refuses
  /// when the file on disk no longer matches it.
  final String? original;

  /// The pubspec after the insertions, or null when there is nothing to
  /// write.
  final String? edited;

  final bool isFlutter;
  final bool alreadyInitialized;

  /// Package names the edit adds under `dependencies:`.
  final List<String> addedDependencies;

  final List<DVAdoptionCheck> checks;

  /// The `dartvel:` path keys written, and the value inferred for each.
  final Map<String, String> mapping;

  /// Why a mapping is not the default, naming the file in the way.
  final List<String> mappingReasons;

  /// What the project already uses and what adopting means for it.
  final List<String> coexistence;

  bool get blocked =>
      refusal != null ||
      checks.any((DVAdoptionCheck c) => c.outcome == DVAdoptionOutcome.blocked);

  bool get fullyChecked => !checks
      .any((DVAdoptionCheck c) => c.outcome == DVAdoptionOutcome.unchecked);

  /// `blocked`, `compatible`, or `compatible as far as checked (N unchecked)`
  /// -- never plain `compatible` while anything went unchecked.
  String get verdict {
    if (blocked) return 'blocked';
    final int unchecked = checks
        .where((DVAdoptionCheck c) => c.outcome == DVAdoptionOutcome.unchecked)
        .length;
    if (unchecked == 0) return 'compatible';
    return 'compatible as far as checked ($unchecked unchecked)';
  }

  /// The report and the diff, as `init` prints them.
  String render() {
    final StringBuffer out = StringBuffer();
    out.writeln('dartvel init: ${p.join(root, 'pubspec.yaml')}');
    if (refusal != null) {
      out.writeln('');
      out.writeln(refusal);
      return out.toString();
    }
    if (alreadyInitialized) {
      out.writeln('');
      out.writeln('This project already has a `dartvel:` key. Nothing to add.');
      return out.toString();
    }

    out.writeln('  project: ${isFlutter ? 'Flutter application' : 'Dart package (no Flutter SDK dependency)'}');
    out.writeln('');
    out.writeln('Compatibility: $verdict');
    for (final DVAdoptionCheck check in checks) {
      final String mark = switch (check.outcome) {
        DVAdoptionOutcome.ok => 'ok       ',
        DVAdoptionOutcome.blocked => 'BLOCKED  ',
        DVAdoptionOutcome.unchecked => 'unchecked',
      };
      out.writeln('  $mark ${check.subject}: ${check.detail}');
    }

    if (mappingReasons.isNotEmpty) {
      out.writeln('');
      out.writeln('Layout (nothing is moved):');
      for (final String reason in mappingReasons) {
        out.writeln('  $reason');
      }
    }

    if (coexistence.isNotEmpty) {
      out.writeln('');
      out.writeln('Already in this project:');
      for (final String line in coexistence) {
        out.writeln('  $line');
      }
    }

    out.writeln('');
    out.writeln('DV-ADOPT-001: multi-tenancy scopes Dartvel-managed models only '
        'in this project. Existing queries are never tenant-filtered.');

    if (edited != null && original != null) {
      out.writeln('');
      out.writeln('Changes to pubspec.yaml (insertions only):');
      out.write(_insertionDiff(original!, edited!));
    }
    return out.toString();
  }
}

/// The outcome of [dvApplyAdoption].
class DVAdoptionApplyResult {
  const DVAdoptionApplyResult({required this.written, required this.message});

  final bool written;
  final String message;
}

/// Plans adoption of the project at [root] without writing anything.
///
/// [localPackagesDir] is where the Dartvel packages sit when the CLI runs from
/// the monorepo; the dependencies are then path dependencies, as `create`
/// writes them.
DVAdoptionPlan dvPlanAdoption(String root, {String? localPackagesDir}) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    return DVAdoptionPlan._(
      root: root,
      refusal: 'No pubspec.yaml here. `dartvel init` adds Dartvel to a project '
          'that already exists; `dartvel create` makes a new one.',
    );
  }

  final String source = pubspec.readAsStringSync();
  final Object? loaded;
  try {
    loaded = loadYaml(source);
  } on YamlException catch (error) {
    return DVAdoptionPlan._(
      root: root,
      original: source,
      refusal: 'pubspec.yaml does not parse, so nothing can be added to it '
          'safely: ${error.message}',
    );
  }
  if (loaded is! YamlMap) {
    return DVAdoptionPlan._(
      root: root,
      original: source,
      refusal: 'pubspec.yaml is not a YAML map.',
    );
  }

  if (loaded.containsKey('dartvel')) {
    return DVAdoptionPlan._(
      root: root,
      original: source,
      alreadyInitialized: true,
    );
  }

  final bool isFlutter = _isFlutter(loaded);
  final List<String> wanted = <String>[
    'dartvel_core',
    if (isFlutter) 'dartvel_flutter',
  ];

  final YamlMap dependencies =
      loaded['dependencies'] is YamlMap ? loaded['dependencies'] as YamlMap : YamlMap();
  final List<String> toAdd = wanted
      .where((String name) => !dependencies.containsKey(name))
      .toList(growable: false);

  final List<DVAdoptionCheck> checks = <DVAdoptionCheck>[
    _sdkCheck(loaded),
    ..._dartvelDeclaredChecks(loaded, wanted),
    ..._sharedDependencyChecks(loaded, wanted),
  ];

  final (Map<String, String> mapping, List<String> reasons) =
      _inferMapping(root);

  final String eol = source.contains('\r\n') ? '\r\n' : '\n';
  final String? edit = _insert(
    source: source,
    eol: eol,
    dependencies: <String>[
      for (final String name in toAdd)
        localPackagesDir == null
            ? '$name: ^$dartvelPackageVersion'
            : '$name:\n  path: ${p.posix.join(localPackagesDir.replaceAll(r'\', '/'), name)}',
    ],
    dartvelKey: <String>[
      '# Written by `dartvel init`. The paths map this project\'s layout;',
      '# nothing was moved. See the Adoption section of the specification.',
      'dartvel:',
      for (final MapEntry<String, String> entry in mapping.entries)
        '  ${entry.key}: ${entry.value}',
    ],
  );
  if (edit == null) {
    return DVAdoptionPlan._(
      root: root,
      original: source,
      refusal: 'The `dependencies:` entry in pubspec.yaml is not a block map '
          '(a flow map such as `dependencies: {...}`, or a value on the same '
          'line). `dartvel init` only inserts lines and will not rewrite it. '
          'Write it as a block map, or add ${wanted.join(' and ')} and a '
          '`dartvel:` key by hand.',
    );
  }

  final String? unsafe = _verifyInsertionOnly(source, edit, loaded, toAdd);
  if (unsafe != null) {
    return DVAdoptionPlan._(
      root: root,
      original: source,
      refusal: 'The edit could not be proven to only add lines, so nothing '
          'will be written: $unsafe',
    );
  }

  return DVAdoptionPlan._(
    root: root,
    original: source,
    edited: edit,
    isFlutter: isFlutter,
    addedDependencies: toAdd,
    checks: checks,
    mapping: mapping,
    mappingReasons: reasons,
    coexistence: _coexistence(loaded),
  );
}

/// Applies [plan]: one write to a temporary file beside the pubspec, then a
/// rename over it. A failure before the rename leaves the original untouched;
/// the rename itself is atomic on the same filesystem.
///
/// Refuses when the plan is blocked, when there is nothing to write, and when
/// the pubspec on disk is no longer the one the plan was computed from -- the
/// plan the developer approved was a diff against that file, not this one.
DVAdoptionApplyResult dvApplyAdoption(DVAdoptionPlan plan) {
  if (plan.refusal != null) {
    return DVAdoptionApplyResult(written: false, message: plan.refusal!);
  }
  if (plan.alreadyInitialized || plan.edited == null) {
    return const DVAdoptionApplyResult(
      written: false,
      message: 'Nothing to add.',
    );
  }
  if (plan.blocked) {
    return const DVAdoptionApplyResult(
      written: false,
      message: 'The compatibility report has blocking items; nothing was '
          'written.',
    );
  }

  final File pubspec = File(p.join(plan.root, 'pubspec.yaml'));
  final String current;
  try {
    current = pubspec.readAsStringSync();
  } on FileSystemException catch (error) {
    return DVAdoptionApplyResult(
      written: false,
      message: 'Could not re-read pubspec.yaml: ${error.message}',
    );
  }
  if (current != plan.original) {
    return const DVAdoptionApplyResult(
      written: false,
      message: 'pubspec.yaml changed after the plan was made; nothing was '
          'written. Run `dartvel init` again to see a plan against the file '
          'as it is now.',
    );
  }

  final File temp = File(p.join(plan.root, '.pubspec.yaml.dartvel-init'));
  try {
    temp.writeAsStringSync(plan.edited!, flush: true);
    temp.renameSync(pubspec.path);
  } on FileSystemException catch (error) {
    try {
      if (temp.existsSync()) temp.deleteSync();
    } on FileSystemException {
      // Reported below; the original is intact either way.
    }
    return DVAdoptionApplyResult(
      written: false,
      message: 'Could not write pubspec.yaml (${error.message}); the original '
          'is unchanged.',
    );
  }
  return const DVAdoptionApplyResult(
    written: true,
    message: 'pubspec.yaml updated. Run `flutter pub get` (or `dart pub get`), '
        'then `dartvel routes`.',
  );
}

bool _isFlutter(YamlMap pubspec) {
  final Object? deps = pubspec['dependencies'];
  if (deps is YamlMap) {
    final Object? flutter = deps['flutter'];
    if (flutter is YamlMap && flutter['sdk'] == 'flutter') return true;
  }
  return pubspec['flutter'] is YamlMap;
}

DVAdoptionCheck _sdkCheck(YamlMap pubspec) {
  final Object? environment = pubspec['environment'];
  final Object? sdk = environment is YamlMap ? environment['sdk'] : null;
  final VersionConstraint dartvel =
      VersionConstraint.parse('>=$dvDartFloor <4.0.0');
  if (sdk is! String) {
    return const DVAdoptionCheck(
      'environment.sdk',
      DVAdoptionOutcome.unchecked,
      'no SDK constraint is declared, so whether this project admits Dart '
          '>=$dvDartFloor could not be checked',
    );
  }
  final VersionConstraint declared;
  try {
    declared = VersionConstraint.parse(sdk);
  } on FormatException {
    return DVAdoptionCheck(
      'environment.sdk',
      DVAdoptionOutcome.unchecked,
      '"$sdk" is not a constraint this check can read',
    );
  }
  if (declared.intersect(dartvel).isEmpty) {
    return DVAdoptionCheck(
      'environment.sdk',
      DVAdoptionOutcome.blocked,
      '"$sdk" excludes every Dart Dartvel runs on (>=$dvDartFloor <4.0.0); '
          'raise the constraint first',
    );
  }
  return DVAdoptionCheck(
    'environment.sdk',
    DVAdoptionOutcome.ok,
    '"$sdk" admits Dart >=$dvDartFloor',
  );
}

/// A Dartvel package the project already declares, at a version the CLI does
/// not write.
Iterable<DVAdoptionCheck> _dartvelDeclaredChecks(
  YamlMap pubspec,
  List<String> wanted,
) sync* {
  final VersionConstraint current =
      VersionConstraint.parse('^$dartvelPackageVersion');
  for (final String name in wanted) {
    final Object? spec = _declaration(pubspec, name);
    if (spec == null) continue;
    yield _compare(name, spec, current, 'this CLI writes');
  }
}

/// Packages the project declares that a Dartvel package depends on too.
Iterable<DVAdoptionCheck> _sharedDependencyChecks(
  YamlMap pubspec,
  List<String> wanted,
) sync* {
  final Map<String, (VersionConstraint, String)> required =
      <String, (VersionConstraint, String)>{};
  for (final String package in wanted) {
    dvDartvelDependencyConstraints[package]!
        .forEach((String name, String constraint) {
      if (wanted.contains(name)) return;
      final VersionConstraint parsed = VersionConstraint.parse(constraint);
      final (VersionConstraint, String)? existing = required[name];
      required[name] = existing == null
          ? (parsed, '$package requires $constraint')
          : (
              existing.$1.intersect(parsed),
              '${existing.$2}, $package requires $constraint'
            );
    });
  }
  final List<String> names = required.keys.toList()..sort();
  for (final String name in names) {
    final Object? spec = _declaration(pubspec, name);
    if (spec == null) continue;
    final (VersionConstraint constraint, String why) = required[name]!;
    DVAdoptionCheck check = _compare(name, spec, constraint, why);
    if (name == 'mix' && check.outcome == DVAdoptionOutcome.blocked) {
      check = DVAdoptionCheck(
        name,
        DVAdoptionOutcome.blocked,
        '${check.detail}. dartvel_mix is a drop-in replacement still named '
            '`mix`: change this one dependency to a version in that range and '
            'no import changes',
      );
    }
    yield check;
  }
}

/// The project's declaration of [name]: an override if there is one, since
/// that is what pub resolves, else the dependency or dev dependency.
Object? _declaration(YamlMap pubspec, String name) {
  for (final String section in <String>[
    'dependency_overrides',
    'dependencies',
    'dev_dependencies',
  ]) {
    final Object? block = pubspec[section];
    if (block is YamlMap && block.containsKey(name)) {
      final Object? value = block[name];
      return section == 'dependency_overrides'
          ? _Override(value)
          : (value ?? 'any');
    }
  }
  return null;
}

class _Override {
  const _Override(this.value);
  final Object? value;
}

DVAdoptionCheck _compare(
  String name,
  Object spec,
  VersionConstraint required,
  String why,
) {
  if (spec is _Override) {
    return DVAdoptionCheck(
      name,
      DVAdoptionOutcome.unchecked,
      'overridden in dependency_overrides, which bypasses constraint '
          'solving; whether Dartvel works against the override is not '
          'something this check can tell ($why)',
    );
  }
  String? text;
  if (spec is String) text = spec;
  if (spec is YamlMap && spec['version'] is String) {
    text = spec['version'] as String;
  }
  if (text == null) {
    return DVAdoptionCheck(
      name,
      DVAdoptionOutcome.unchecked,
      'declared from a path, git or SDK source, which has no version to '
          'compare ($why)',
    );
  }
  final VersionConstraint declared;
  try {
    declared = VersionConstraint.parse(text);
  } on FormatException {
    return DVAdoptionCheck(
      name,
      DVAdoptionOutcome.unchecked,
      '"$text" is not a constraint this check can read ($why)',
    );
  }
  if (declared.intersect(required).isEmpty) {
    return DVAdoptionCheck(
      name,
      DVAdoptionOutcome.blocked,
      '"$text" shares no version with Dartvel ($why)',
    );
  }
  return DVAdoptionCheck(name, DVAdoptionOutcome.ok, '"$text" ($why)');
}

/// The `dartvel:` path keys, defaulted unless something of the project's is
/// in the way.
///
/// The collisions are the files a generator would claim: every `.dart` file
/// under `<backendDir>/functions` is served as an endpoint whether or not it
/// is annotated, and every `*.page.dart` under `pagesDir` is a legacy page.
(Map<String, String>, List<String>) _inferMapping(String root) {
  final List<String> reasons = <String>[];

  String pagesDir = 'lib/pages';
  final String? pageCollision = _firstFile(
    p.join(root, 'lib', 'pages'),
    root,
    (String rel, String source) =>
        (rel.endsWith('.page.dart') ||
            p.basename(rel) == '_layout.dart' ||
            p.basename(rel) == '_guard.dart') &&
        !source.contains('@DVPage'),
  );
  if (pageCollision != null) {
    pagesDir = 'lib/dartvel/pages';
    reasons.add('pagesDir: $pagesDir, because $pageCollision would be read '
        'as a Dartvel page under lib/pages');
  }

  String backendDir = 'lib/backend';
  final String? functionCollision = _firstFile(
    p.join(root, 'lib', 'backend', 'functions'),
    root,
    (String rel, String source) => !source.contains('@DVBackendFunction'),
  );
  if (functionCollision != null) {
    backendDir = 'lib/dartvel/backend';
    reasons.add('backendDir: $backendDir, because every file under '
        'lib/backend/functions is served as an endpoint, and '
        '$functionCollision is this project\'s own code');
  }

  return (
    <String, String>{'pagesDir': pagesDir, 'backendDir': backendDir},
    reasons,
  );
}

String? _firstFile(
  String dir,
  String root,
  bool Function(String rel, String source) collides,
) {
  final Directory directory = Directory(dir);
  if (!directory.existsSync()) return null;
  final List<File> files = directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
  for (final File file in files) {
    final String rel = p.relative(file.path, from: root).replaceAll(r'\', '/');
    if (collides(rel, file.readAsStringSync())) return rel;
  }
  return null;
}

/// What the project already uses, and what adoption does about each -- only
/// statements that are true of the code as it stands.
List<String> _coexistence(YamlMap pubspec) {
  bool has(String name) => <String>['dependencies', 'dev_dependencies']
      .any((String s) => pubspec[s] is YamlMap && (pubspec[s] as YamlMap).containsKey(name));
  return <String>[
    if (has('go_router'))
      'go_router: your routes stay yours. `dartvel routes` fails with '
          'DV-ADOPT-002 when a GoRoute path is also a generated page route.',
    if (has('freezed') || has('json_serializable'))
      'freezed / json_serializable: those classes stay as they are. A class '
          'becomes a Dartvel model only when it is annotated, and annotating '
          'one that already has a generated serializer fails with DV-ADOPT-003.',
    if (has('build_runner'))
      'build_runner: kept for your own builders. Dartvel adds none; its '
          'generator is `dartvel routes`.',
    if (has('flutter_riverpod') || has('provider') || has('flutter_bloc') || has('bloc'))
      'state management: untouched. The signal/provider and stream bridges '
          'Adoption describes are not built yet.',
    if (has('drift') || has('isar') || has('sqflite'))
      'local database: untouched. Nothing reads its schema yet.',
    if (has('firebase_auth') || has('supabase_flutter') || has('supabase'))
      'identity provider: untouched. DVAuthProvider adapters for it are not '
          'built yet.',
  ];
}

/// [source] with [dependencies] inserted at the end of the `dependencies:`
/// block (or a new block appended) and [dartvelKey] appended, or null when
/// `dependencies:` is not a block map this can insert into.
String? _insert({
  required String source,
  required String eol,
  required List<String> dependencies,
  required List<String> dartvelKey,
}) {
  final List<String> lines = source.split('\n');
  // A trailing newline leaves one empty element; keep it as the final
  // terminator rather than a line.
  final bool endsWithNewline = source.endsWith('\n');
  if (endsWithNewline) lines.removeLast();
  String strip(String line) =>
      line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
  final String lineEnd = eol == '\r\n' ? '\r' : '';

  final List<String> out = List<String>.of(lines);
  if (dependencies.isNotEmpty) {
    final int header = lines.indexWhere(
        (String l) => RegExp(r'^dependencies\s*:').hasMatch(strip(l)));
    if (header == -1) {
      out.add('dependencies:$lineEnd');
      for (final String dep in dependencies) {
        for (final String part in dep.split('\n')) {
          out.add('  $part$lineEnd');
        }
      }
    } else {
      final String rest = strip(lines[header])
          .replaceFirst(RegExp(r'^dependencies\s*:'), '')
          .trim();
      if (rest.isNotEmpty && !rest.startsWith('#')) return null;

      String? indent;
      int last = header;
      for (int i = header + 1; i < lines.length; i += 1) {
        final String line = strip(lines[i]);
        if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
        final String lead = RegExp(r'^[ \t]*').firstMatch(line)!.group(0)!;
        if (lead.isEmpty) break;
        indent ??= lead;
        last = i;
      }
      indent ??= '  ';
      final List<String> inserted = <String>[
        for (final String dep in dependencies)
          for (final String part in dep.split('\n')) '$indent$part$lineEnd',
      ];
      out.insertAll(last + 1, inserted);
    }
  }

  if (out.isNotEmpty && strip(out.last).trim().isNotEmpty) {
    out.add(lineEnd);
  }
  for (final String line in dartvelKey) {
    out.add('$line$lineEnd');
  }
  return '${out.join('\n')}\n';
}

/// Null when [edited] is [original] plus insertions and nothing the project
/// declared has changed meaning; otherwise why not.
String? _verifyInsertionOnly(
  String original,
  String edited,
  YamlMap before,
  List<String> added,
) {
  final List<String> a = original.split('\n');
  final List<String> b = edited.split('\n');
  int at = 0;
  for (final String line in b) {
    if (at < a.length && line == a[at]) at += 1;
  }
  // A final empty element is the trailing newline, which may be supplied.
  if (at < a.length && !(at == a.length - 1 && a.last.isEmpty)) {
    return 'original line ${at + 1} would not survive';
  }
  final Object? after;
  try {
    after = loadYaml(edited);
  } on YamlException catch (error) {
    return 'the result does not parse (${error.message})';
  }
  if (after is! YamlMap || after['dartvel'] is! YamlMap) {
    return 'the result has no dartvel: map';
  }
  for (final Object? key in before.keys) {
    if (key == 'dependencies') continue;
    if (!_deepEquals(before[key], after[key])) return '$key would change';
  }
  final Object? beforeDeps = before['dependencies'];
  final Object? afterDeps = after['dependencies'];
  if (added.isNotEmpty && afterDeps is! YamlMap) {
    return 'dependencies would not be a map';
  }
  if (beforeDeps is YamlMap) {
    for (final Object? key in beforeDeps.keys) {
      if (!_deepEquals(beforeDeps[key], (afterDeps as YamlMap)[key])) {
        return 'dependency $key would change';
      }
    }
  }
  for (final String name in added) {
    if (!(afterDeps as YamlMap).containsKey(name)) {
      return '$name would not be added';
    }
  }
  return null;
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final Object? key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i += 1) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// The inserted lines of [edited], numbered as they will be in the file.
String _insertionDiff(String original, String edited) {
  final List<String> a = original.split('\n');
  final List<String> b = edited.split('\n');
  final StringBuffer out = StringBuffer();
  int at = 0;
  for (int i = 0; i < b.length; i += 1) {
    final String line = b[i];
    if (at < a.length && line == a[at]) {
      at += 1;
      continue;
    }
    if (i == b.length - 1 && line.isEmpty) continue;
    out.writeln('  +${(i + 1).toString().padLeft(4)} ${line.replaceAll('\r', '')}');
  }
  return out.toString();
}
