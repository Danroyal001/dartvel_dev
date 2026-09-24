/// `dartvel add <source>`: resolve a capability source into a module.
///
/// One installation verb, and what comes back is always a module.
///
/// Two rungs are built. A source that is **already a Dartvel project** is
/// mounted directly, because generating a wrapper around a module that is
/// already a module adds a layer whose only function is to be walked
/// through. A **described API** -- a local OpenAPI document -- is generated
/// into a pure Dart module and mounted: no foreign runtime, no artifact and
/// no binding, which is what makes it the cheapest rung to build first.
///
/// Every other scheme -- `maven:`, `cargo:`, `swift:`, `npm:` and the rest --
/// is specified in *Module Sources* and not built. Each says so and changes
/// nothing, rather than writing a mount that resolves to nothing: a half-done
/// install leaves a project that no longer builds, which is worse than one
/// that never started.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../modules/graphql_module.dart';
import '../modules/openapi_module.dart';
import '../modules/source_detection.dart';
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
    this.generated,
    this.from,
  });

  /// What the parent will know it by: `DV.Modules.<id>`.
  final String id;

  /// Where the module's project is, relative to the parent.
  final String path;

  /// Where the parent will serve it.
  final String mount;

  /// The module project's package name.
  final String packageName;

  /// The package to write, for a source that is generated into one, or null
  /// for a project that is mounted where it already is.
  ///
  /// Held on the plan rather than generated while writing, so `--dry-run`
  /// reports what would be written having actually produced it: a plan that
  /// described a generation that then failed would be worse than no plan.
  final DVGeneratedModule? generated;

  /// Where a generated module came from, for the line that says so.
  final String? from;

  /// What `--dry-run` prints, and what is done otherwise.
  ///
  /// Printed before anything is written whether or not `--dry-run` was
  /// passed: a command that changes five things about a project without
  /// showing them first is a command teams learn not to run.
  List<String> get lines {
    final DVGeneratedModule? module = generated;
    if (module == null) {
      return <String>[
        'module   $id',
        'from     $path  (a Dartvel project, mounted directly)',
        'mount    $mount',
        'package  $packageName',
        'writes   pubspec.yaml: dartvel.modules.$id',
      ];
    }
    return <String>[
      'module   $id',
      'from     $from  (a described API, generated into a pure Dart module)',
      'mount    $mount',
      'package  $packageName',
      'host     ${module.host}, declared in the generated pubspec',
      for (final String file in module.files.keys) 'writes   $path/$file',
      'writes   pubspec.yaml: dartvel.modules.$id',
    ];
  }
}

class AddCommand extends Command<void> {
  /// [root] is the project to add to; the working directory when null, which
  /// is what the CLI passes.
  AddCommand({this.root}) {
    argParser
      ..addOption('as', help: 'The id the parent knows the module by.')
      ..addOption('mount', help: 'Where the parent serves it.')
      ..addOption('url',
          help: 'The endpoint a described API is called at. Required for a '
              'GraphQL schema, which names no server of its own.')
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
        mount: argResults?['mount'] as String?,
        url: argResults?['url'] as String?);

    for (final String line in plan.lines) {
      Logger.log('  $line');
    }
    if (argResults?['dry-run'] == true) {
      Logger.log('Nothing was written. Run it without --dry-run to mount it.');
      return;
    }
    _write(target, plan);
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
    String? url,
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
    // What is there decides what this is, and the answer is reported whether
    // or not it is one this can install: a refusal that names a Cargo.toml is
    // a refusal somebody can act on.
    final DVDetectedSource found = dvDetectSource(dir.path);
    switch (found.kind) {
      case DVSourceKind.missing:
        throw DVAddRefused('There is no directory at $source.');
      case DVSourceKind.dartPackage:
        throw DVAddRefused(
          '$source is a Dart package and not a Dartvel project: '
          '${found.reason}',
        );
      case DVSourceKind.unknown:
        throw DVAddRefused('${found.code}: $source is not a source Dartvel '
            'can read. ${found.reason}');
      case DVSourceKind.dartvel:
        break;
      case DVSourceKind.describedApi:
        return _describedApiPlan(root, source, dir,
            id: id, mount: mount, url: url);
      case DVSourceKind.apple:
      case DVSourceKind.jvm:
      case DVSourceKind.rust:
      case DVSourceKind.c:
      case DVSourceKind.wasm:
      case DVSourceKind.npm:
        throw DVAddRefused(
          '$source is ${found.kind.name}, reached by ${found.mechanism}. '
          'Generating a module from one is specified in Module Sources and '
          'is not built, so nothing was written. What works today is a '
          'source that is already a Dartvel project, or an OpenAPI document.',
        );
    }

    final Object? doc = _yamlOf(File(p.join(dir.path, 'pubspec.yaml')));
    if (doc is! Map) {
      throw DVAddRefused('$source/pubspec.yaml is not a map.');
    }
    final Map<Object?, Object?> dartvel =
        (doc['dartvel']! as Map).cast<Object?, Object?>();
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

  /// The plan for a local OpenAPI document.
  ///
  /// The whole package is generated here, before anything is written, so a
  /// document the generator refuses refuses the command rather than leaving
  /// half a package and a mount pointing at it.
  static DVAddPlan _describedApiPlan(
    String root,
    String source,
    Directory dir, {
    String? id,
    String? mount,
    String? url,
  }) {
    final File? document = _describedApiDocumentIn(dir);
    if (document == null) {
      throw DVAddRefused(
        '$source holds a described API this cannot read yet. OpenAPI and '
        'GraphQL are built; a .proto is specified in Module Sources and is '
        'not, so nothing was written.',
      );
    }

    final String resolved = id ?? _idFromDocumentName(dir);
    final Map<Object?, Object?> mounted = _modulesOf(root);
    if (mounted.containsKey(resolved)) {
      throw DVAddRefused(
        'dartvel.modules.$resolved is already mounted. Repointing it would '
        'change what every DV.Modules.$resolved call reaches, so nothing was '
        'written: remove it first, or pass --as with another id.',
      );
    }

    final bool isGraphQl = const <String>{'.graphql', '.graphqls', '.gql'}
        .contains(p.extension(document.path).toLowerCase());
    if (isGraphQl && (url == null || url.isEmpty)) {
      throw DVAddRefused(
        '${p.relative(document.path, from: root)} is a GraphQL schema, and a '
        'schema names no server of its own. Pass --url with the endpoint to '
        'post to, such as --url https://api.vendor.com/graphql.',
      );
    }

    final DVGeneratedModule module;
    try {
      module = isGraphQl
          ? dvGenerateGraphQlModule(
              schema: document.readAsStringSync(),
              moduleId: resolved,
              url: url!,
            )
          : dvGenerateDescribedApiModule(
              document: _documentIn(document),
              moduleId: resolved,
              baseUrl: url,
            );
    } on DVDescribedApiRefused catch (error) {
      throw DVAddRefused(
        '${p.relative(document.path, from: root)}: ${error.message}',
      );
    }

    final String path = p.join('modules', module.packageName);
    final Directory into = Directory(p.join(root, path));
    if (into.existsSync()) {
      throw DVAddRefused(
        '$path is already there, and generating over it would take whatever '
        'is in it with no way back. Delete it first, or pass --as with '
        'another id.',
      );
    }

    return DVAddPlan(
      id: resolved,
      path: path.replaceAll('\\', '/'),
      mount: mount ?? '/$resolved',
      packageName: module.packageName,
      generated: module,
      from: p.relative(document.path, from: root).replaceAll('\\', '/'),
    );
  }

  /// The document in [dir], or null when what is there is a described API
  /// this does not read.
  ///
  /// OpenAPI first, because a project holding both is one whose HTTP surface
  /// is the one to generate against: a schema beside it is usually the
  /// service's own, not the one a client calls.
  static File? _describedApiDocumentIn(Directory dir) {
    final RegExp openApi =
        RegExp(r'^openapi\.(json|ya?ml)$', caseSensitive: false);
    final RegExp graphQl =
        RegExp(r'\.(graphqls?|gql)$', caseSensitive: false);
    File? schema;
    for (final FileSystemEntity entity in dir.listSync()) {
      if (entity is! File) continue;
      final String name = p.basename(entity.path);
      if (openApi.hasMatch(name)) return entity;
      if (schema == null && graphQl.hasMatch(name)) schema = entity;
    }
    return schema;
  }

  /// The document, decoded. JSON is YAML, so one reader answers both, but a
  /// .json file is decoded as JSON: the YAML reader is the slower path and
  /// its error messages are about YAML.
  static Map<String, Object?> _documentIn(File file) {
    final String text = file.readAsStringSync();
    final Object? decoded = p.extension(file.path).toLowerCase() == '.json'
        ? jsonDecode(text)
        : loadYaml(text);
    if (decoded is! Map) {
      throw DVAddRefused('${p.basename(file.path)} is not a document: it '
          'reads as ${decoded.runtimeType}.');
    }
    // A YAML map is not a Map<String, Object?>, and its nested maps are not
    // either, so it is walked rather than cast.
    return _plain(decoded)! as Map<String, Object?>;
  }

  static Object? _plain(Object? value) => switch (value) {
        final Map<Object?, Object?> map => <String, Object?>{
            for (final MapEntry<Object?, Object?> e in map.entries)
              '${e.key}': _plain(e.value),
          },
        final List<Object?> list => <Object?>[for (final Object? e in list) _plain(e)],
        _ => value,
      };

  /// The id for a document nobody named with --as: the directory's own name,
  /// in the spelling DV.Modules.<id> wants.
  static String _idFromDocumentName(Directory dir) {
    final List<String> parts = p
        .basename(dir.path)
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      throw const DVAddRefused('This directory\'s name is not a module id. '
          'Pass --as.');
    }
    final StringBuffer out = StringBuffer(parts.first.toLowerCase());
    for (final String part in parts.skip(1)) {
      out.write(part[0].toUpperCase());
      out.write(part.substring(1).toLowerCase());
    }
    return out.toString();
  }

  /// Writes a generated module's package, for a plan that has one.
  ///
  /// Whole files, into a directory the plan has already established is not
  /// there: nothing here overwrites anything.
  static void _write(String root, DVAddPlan plan) {
    final DVGeneratedModule? module = plan.generated;
    if (module == null) return;
    for (final MapEntry<String, String> file in module.files.entries) {
      final File out = File(p.join(root, plan.path, file.key));
      out.parent.createSync(recursive: true);
      out.writeAsStringSync(file.value);
    }
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
