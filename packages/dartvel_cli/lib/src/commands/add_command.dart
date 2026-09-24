/// `dartvel add <source>`: resolve a capability source into a module.
///
/// One installation verb, and what comes back is always a module. This is the
/// first rung: a source that is **already a Dartvel project** is mounted
/// directly, because generating a wrapper around a module that is already a
/// module adds a layer whose only function is to be walked through.
///
/// Every other scheme -- `maven:`, `cargo:`, `swift:`, `npm:`, `openapi:` and
/// the rest -- is specified in *Module Sources* and not built. Each says so
/// and changes nothing, rather than writing a mount that resolves to nothing:
/// a half-done install leaves a project that no longer builds, which is worse
/// than one that never started.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../utils/logger.dart';

/// Thrown when `dartvel add` will not do what was asked.
///
/// Its own type rather than a UsageException, because the command was used
/// correctly and the answer is still no: an id already mounted, a path that
/// is not a Dartvel project, a scheme nothing resolves yet.
class DVAddRefused implements Exception {
  const DVAddRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What a source resolved to, before anything is written.
class DVAddPlan {
  const DVAddPlan({
    required this.id,
    required this.path,
    required this.mount,
    required this.packageName,
  });

  /// What the parent will know it by: `DV.Modules.<id>`.
  final String id;

  /// Where the module's project is, relative to the parent.
  final String path;

  /// Where the parent will serve it.
  final String mount;

  /// The module project's package name.
  final String packageName;

  /// What `--dry-run` prints, and what is done otherwise.
  ///
  /// Printed before anything is written whether or not `--dry-run` was
  /// passed: a command that changes five things about a project without
  /// showing them first is a command teams learn not to run.
  List<String> get lines => <String>[
        'module   $id',
        'from     $path  (a Dartvel project, mounted directly)',
        'mount    $mount',
        'package  $packageName',
        'writes   pubspec.yaml: dartvel.modules.$id',
      ];
}

class AddCommand extends Command<void> {
  /// [root] is the project to add to; the working directory when null, which
  /// is what the CLI passes.
  AddCommand({this.root}) {
    argParser
      ..addOption('as', help: 'The id the parent knows the module by.')
      ..addOption('mount', help: 'Where the parent serves it.')
      ..addFlag('dry-run',
          negatable: false,
          help: 'Print the installation plan and change nothing.');
  }

  final String? root;

  @override
  final String name = 'add';

  @override
  String get description =>
      'Resolve a capability source into a module the parent mounts.';

  @override
  String get invocation => 'dartvel add <source> [--as <id>] [--dry-run]';

  @override
  Future<void> run() async {
    final List<String> rest = argResults?.rest ?? const <String>[];
    if (rest.length != 1) {
      throw UsageException('dartvel add takes one source.', usage);
    }
    final String target = root ?? Directory.current.path;
    final DVAddPlan plan = planFor(target, rest.single,
        id: argResults?['as'] as String?,
        mount: argResults?['mount'] as String?);

    for (final String line in plan.lines) {
      Logger.log('  $line');
    }
    if (argResults?['dry-run'] == true) {
      Logger.log('Nothing was written. Run it without --dry-run to mount it.');
      return;
    }
    _mount(target, plan);
    Logger.log('Mounted ${plan.id} at ${plan.mount}. '
        'Run dartvel routes to regenerate the client.');
  }

  /// What [source] resolves to, or the reason it does not.
  static DVAddPlan planFor(
    String root,
    String source, {
    String? id,
    String? mount,
  }) {
    final int colon = source.indexOf(':');
    // A Windows drive letter is not a scheme, and neither is a bare path.
    if (colon > 1) {
      final String scheme = source.substring(0, colon);
      throw DVAddRefused(
        '$scheme: sources are specified in Module Sources and are not built '
        'yet, so nothing was written. What works today is a Dartvel project: '
        'a path beside this one.',
      );
    }

    final Directory dir = Directory(p.join(root, source));
    if (!dir.existsSync()) {
      throw DVAddRefused('There is no directory at $source.');
    }
    final File pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw DVAddRefused('$source has no pubspec.yaml, so it is not a Dart '
          'package and cannot be a module.');
    }

    final Object? doc = _yamlOf(pubspec);
    if (doc is! Map) {
      throw DVAddRefused('$source/pubspec.yaml is not a map.');
    }
    final Object? dartvel = doc['dartvel'];
    if (dartvel is! Map) {
      throw DVAddRefused(
        '$source is a Dart package and not a Dartvel project: its '
        'pubspec.yaml declares no dartvel: section. A package that is not a '
        'module is an ordinary dependency -- dart pub add it.',
      );
    }

    final Object? module = dartvel['module'];
    final String packageName = '${doc['name'] ?? ''}';
    final String resolved = id ??
        (module is Map && module['id'] is String
            ? '${module['id']}'
            : packageName);
    if (resolved.isEmpty) {
      throw DVAddRefused('$source names neither a package nor a module id, '
          'so there is nothing to call it. Pass --as.');
    }

    final Map<Object?, Object?> mounted = _modulesOf(root);
    if (mounted.containsKey(resolved)) {
      throw DVAddRefused(
        'dartvel.modules.$resolved is already mounted. Repointing it would '
        'change what every DV.Modules.$resolved call reaches, so nothing was '
        'written: remove it first, or pass --as with another id.',
      );
    }

    return DVAddPlan(
      id: resolved,
      path: p.relative(dir.path, from: root).replaceAll('\\', '/'),
      mount: mount ?? '/$resolved',
      packageName: packageName,
    );
  }

  /// Appends the mount to `dartvel.modules`, creating the key if it is the
  /// parent's first module.
  ///
  /// Appended as text rather than re-serialised from a parsed document,
  /// because a pubspec is a file a person wrote: round-tripping it through a
  /// YAML writer would reformat every line they did not ask about and lose
  /// every comment they left.
  static void _mount(String root, DVAddPlan plan) {
    final File file = File(p.join(root, 'pubspec.yaml'));
    final String text = file.readAsStringSync();
    final String entry = '    ${plan.id}:\n'
        '      source:\n'
        '        path: ${plan.path}\n'
        '      mount: ${plan.mount}\n';

    final RegExp modulesKey = RegExp(r'^  modules:\s*$', multiLine: true);
    final RegExpMatch? existing = modulesKey.firstMatch(text);
    if (existing != null) {
      file.writeAsStringSync(
        '${text.substring(0, existing.end)}\n$entry'
        '${text.substring(existing.end).replaceFirst('\n', '')}',
      );
      return;
    }

    final RegExp dartvelKey = RegExp(r'^dartvel:\s*$', multiLine: true);
    final RegExpMatch? dartvel = dartvelKey.firstMatch(text);
    if (dartvel == null) {
      file.writeAsStringSync(
        '${text.trimRight()}\n\ndartvel:\n  modules:\n$entry',
      );
      return;
    }
    file.writeAsStringSync(
      '${text.substring(0, dartvel.end)}\n  modules:\n$entry'
      '${text.substring(dartvel.end).replaceFirst('\n', '')}',
    );
  }

  static Map<Object?, Object?> _modulesOf(String root) {
    final Object? doc = _yamlOf(File(p.join(root, 'pubspec.yaml')));
    if (doc is! Map) return const <Object?, Object?>{};
    final Object? dartvel = doc['dartvel'];
    if (dartvel is! Map) return const <Object?, Object?>{};
    final Object? modules = dartvel['modules'];
    return modules is Map ? modules : const <Object?, Object?>{};
  }

  static Object? _yamlOf(File file) {
    try {
      return loadYaml(file.readAsStringSync());
    } on Object {
      return null;
    }
  }
}
