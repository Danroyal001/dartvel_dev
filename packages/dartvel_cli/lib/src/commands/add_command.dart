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
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:args/command_runner.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVModuleEnvironment, DVModuleOutcome;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../module_trust/module_lock.dart';
import '../modules/described_api.dart';
import '../modules/foreign/apple_module.dart';
import '../modules/foreign/apple_surface.dart';
import '../modules/foreign/dart_package_module.dart';
import '../modules/foreign/dart_surface.dart';
import '../modules/foreign/ffi_module.dart';
import '../modules/foreign/ffi_surface.dart';
import '../modules/foreign/jvm_module.dart';
import '../modules/foreign/jvm_surface.dart';
import '../modules/foreign/module_writer.dart';
import '../modules/foreign/npm_module.dart';
import '../modules/foreign/npm_surface.dart';
import '../modules/foreign/resolver.dart';
import '../modules/foreign/wasm_module.dart';
import '../modules/graphql_module.dart';
import '../modules/openapi_module.dart';
import '../modules/source_detection.dart';
import '../utils/logger.dart';
import 'version_command.dart' show dartvelCliVersion;

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
    this.pin,
    this.outcomes = const <String>[],
  });

  /// The lock entry a foreign source is pinned by, written with the module.
  final DVModulePin? pin;

  /// Each operation and what it does in each environment, for the plan.
  final List<String> outcomes;

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
        'writes   pubspec.yaml: dependencies.$packageName, '
            'dartvel.modules.$id',
      ];
    }
    if (pin != null) {
      return <String>[
        'module   $id',
        'from     ${pin!.source}  (${pin!.resolvedFrom})',
        'digest   sha256 ${pin!.sourceDigest}',
        'mount    $mount',
        'package  $packageName',
        ...outcomes,
        for (final String file in module.files.keys) 'writes   $path/$file',
        'writes   pubspec.yaml: dependencies.$packageName, '
            'dartvel.modules.$id',
        'writes   $dvModuleLockFile: $packageName',
      ];
    }
    return <String>[
      'module   $id',
      'from     $from  (a described API, generated into a pure Dart module)',
      'mount    $mount',
      'package  $packageName',
      'host     ${module.host}, declared in the generated pubspec',
      for (final String file in module.files.keys) 'writes   $path/$file',
      'writes   pubspec.yaml: dependencies.$packageName, '
          'dartvel.modules.$id',
    ];
  }
}

class AddCommand extends Command<void> {
  /// [root] is the project to add to; the working directory when null, which
  /// is what the CLI passes.
  AddCommand({this.root, this.fetcher = const DVSourceFetcher()}) {
    argParser
      ..addOption('elsewhere',
          allowed: <String>['unavailable', 'noop'],
          defaultsTo: 'unavailable',
          help: 'What an operation does in an environment the source cannot '
              'run in. Written into the module per operation.')
      ..addMultiOption('class',
          help: 'For a JVM library: a class whose static methods the module '
              'exposes, dotted. Repeat it for more than one.')
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

  /// The network, for a source that is fetched.
  final DVSourceFetcher fetcher;

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
    final String source = withScheme(target, rest.single);
    final DVAddPlan plan = isForeign(source)
        ? await planForeign(target, source,
            id: argResults?['as'] as String?,
            mount: argResults?['mount'] as String?,
            elsewhere: argResults?['elsewhere'] == 'noop'
                ? DVModuleOutcome.noop
                : DVModuleOutcome.unavailable,
            fetcher: fetcher,
            classes: (argResults?['class'] as List<String>?) ?? const <String>[])
        : planFor(target, source,
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
    _depend(target, plan);
    _mount(target, plan);
    _pin(target, plan);
    Logger.log('Mounted ${plan.id} at ${plan.mount}. '
        'Run dartvel routes to regenerate the client.');
  }

  /// The schemes a foreign source is resolved from here.
  static const List<String> foreignSchemes = <String>[
    'pub:',
    'git:',
    'path:',
    'npm:',
    'c:',
    'cargo:',
    'wasm:',
    'maven:',
    'jar:',
    'swift:',
    'pod:',
  ];

  /// Whether [source] names a foreign source this command generates a
  /// module from.
  static bool isForeign(String source) =>
      foreignSchemes.any((String scheme) => source.startsWith(scheme));

  /// A bare path whose contents are a native or npm source is added as the
  /// scheme it would have been given: what is there decides.
  static String withScheme(String root, String source) {
    if (isForeign(source) || source.contains(':')) return source;
    if (source.endsWith('.wasm') && File(p.join(root, source)).existsSync()) {
      return 'wasm:$source';
    }
    if (source.endsWith('.jar') && File(p.join(root, source)).existsSync()) {
      return 'jar:$source';
    }
    final DVDetectedSource found =
        dvDetectSource(p.join(root, source));
    return switch (found.kind) {
      DVSourceKind.rust => 'cargo:$source',
      DVSourceKind.c => 'c:$source',
      DVSourceKind.wasm => 'wasm:$source',
      DVSourceKind.apple => 'swift:$source',
      _ => source,
    };
  }

  /// The plan for a foreign source: resolved, fetched and verified, its
  /// surface read and its module generated, before anything in the project
  /// is written.
  ///
  /// The fetched source is kept under `.dartvel/sources/`, which is a cache:
  /// the pin is what is committed.
  static Future<DVAddPlan> planForeign(
    String root,
    String source, {
    String? id,
    String? mount,
    DVModuleOutcome elsewhere = DVModuleOutcome.unavailable,
    DVSourceFetcher fetcher = const DVSourceFetcher(),
    List<String> classes = const <String>[],
  }) async {
    final DVResolvedSource resolved;
    final DVForeignModuleSpec Function(String id) specFor;
    try {
      (resolved, specFor) =
          await _resolveForeign(root, source, elsewhere, fetcher,
              classes: classes);
    } on DVSourceUnresolved catch (e) {
      throw DVAddRefused(e.message);
    } on DVDartSurfaceRefused catch (e) {
      throw DVAddRefused(e.message);
    }

    // The package's own name, less an npm scope: @acme/text-kit is textKit.
    final String moduleId =
        id ?? dvCamel(resolved.name.replaceFirst(RegExp(r'^@[^/]+/'), ''));
    if (_modulesOf(root).containsKey(moduleId)) {
      throw DVAddRefused(
        'DV-MODULE-011: dartvel.modules.$moduleId is already mounted. '
        'Nothing was written: remove it first, or pass --as with another id.',
      );
    }
    final DVForeignModuleSpec spec = specFor(moduleId);
    final DVGeneratedModule module;
    try {
      module = dvWriteForeignModule(spec);
    } on DVModuleGenerationRefused catch (e) {
      throw DVAddRefused('$e');
    }
    final String path = p.join('modules', module.packageName);
    if (Directory(p.join(root, path)).existsSync()) {
      throw DVAddRefused(
        '$path is already there, and generating over it would take whatever '
        'is in it with no way back. Delete it first, or pass --as with '
        'another id.',
      );
    }
    return DVAddPlan(
      id: moduleId,
      path: path.replaceAll('\\', '/'),
      mount: mount ?? '/$moduleId',
      packageName: module.packageName,
      generated: module,
      from: resolved.descriptor,
      outcomes: <String>[
        for (final DVModuleOperation op in spec.operations)
          'op       ${op.name}: ${dvModuleEnvironments.map((DVModuleEnvironment e) => '${e.name} ${spec.outcomes[op.name]![e]!.name}').join(', ')}',
        for (final MapEntry<String, String> skip in spec.skipped.entries)
          'skips    ${skip.key}: ${skip.value}',
      ],
      pin: DVModulePin(
        package: module.packageName,
        version: resolved.version,
        capabilities: const <String>[],
        source: resolved.descriptor,
        sourceDigest: resolved.sourceDigest,
        wrapperHash: dvWrapperHash(module.files),
        generator: 'dartvel_cli $dartvelCliVersion',
        resolvedFrom: resolved.resolvedFrom,
        targets: const <String>['backend', 'native', 'web'],
      ),
    );
  }


  /// Stages 1 to 9 for one scheme: the fetched source, and how to make the
  /// module spec once its id is known.
  static Future<(DVResolvedSource, DVForeignModuleSpec Function(String))>
      _resolveForeign(String root, String source, DVModuleOutcome elsewhere,
          DVSourceFetcher fetcher,
          {List<String> classes = const <String>[]}) async {
    if (source.startsWith('swift:') || source.startsWith('pod:')) {
      if (source.startsWith('pod:')) {
        final DVResolvedPod pod =
            await dvResolvePod(root, source.substring(4), fetcher: fetcher);
        final bool swift = pod.files.any((String f) => f.endsWith('.swift'));
        final DVAppleSurface surface = swift
            ? dvScanSwiftSources(pod.source.directory, pod.source.name,
                pod.files.where((String f) => f.endsWith('.swift')).toList())
            : dvScanObjcHeaders(pod.source.directory, pod.source.name,
                files: pod.files);
        return (
          pod.source,
          (String id) => dvAppleModuleSpec(
                id: id,
                source: pod.source.descriptor,
                surface: surface,
                elsewhere: elsewhere,
              ),
        );
      }
      final String rest = source.substring(6);
      final DVResolvedSource resolved = rest.contains('://')
          ? await dvResolveGitTree(
              root,
              'swift',
              rest.contains('#') ? rest.substring(0, rest.lastIndexOf('#')) : rest,
              rest.contains('#') ? rest.substring(rest.lastIndexOf('#') + 1) : null,
              fetcher: fetcher)
          : dvResolveLocalSource(root, 'swift', rest);
      final DVAppleSurface surface = dvScanSwiftPackage(resolved.directory);
      return (
        DVResolvedSource(
          descriptor: resolved.descriptor,
          name: surface.name,
          version: resolved.version,
          directory: resolved.directory,
          sourceDigest: resolved.sourceDigest,
          resolvedFrom: resolved.resolvedFrom,
          dependency: '',
        ),
        (String id) => dvAppleModuleSpec(
              id: id,
              source: resolved.descriptor,
              surface: surface,
              elsewhere: elsewhere,
            ),
      );
    }
    if (source.startsWith('maven:') || source.startsWith('jar:')) {
      final bool maven = source.startsWith('maven:');
      final DVResolvedSource resolved = maven
          ? await dvResolveMaven(root, source.substring(6), fetcher: fetcher)
          : () {
              final String path = p.normalize(p.join(root, source.substring(4)));
              if (!File(path).existsSync()) {
                throw DVSourceUnresolved('There is no jar at ${source.substring(4)}.');
              }
              return DVResolvedSource(
                descriptor: 'jar:${p.relative(path, from: root).replaceAll('\\', '/')}',
                name: p.basenameWithoutExtension(path),
                version: '0.0.0',
                directory: path,
                sourceDigest: sha256.convert(File(path).readAsBytesSync()).toString(),
                resolvedFrom: path,
                dependency: '',
              );
            }();
      final DVJvmSurface surface = dvScanJar(resolved.directory, only: classes);
      final DVJvmArtifact artifact = maven
          ? DVMavenArtifact(resolved.dependency)
          : DVJarArtifact(p.basename(resolved.directory),
              File(resolved.directory).readAsBytesSync());
      return (
        resolved,
        (String id) => dvJvmModuleSpec(
              id: id,
              source: resolved.descriptor,
              surface: surface,
              artifact: artifact,
              elsewhere: elsewhere,
            ),
      );
    }
    if (source.startsWith('wasm:')) {
      final String rest = source.substring(5);
      final Uint8List bytes;
      final String where;
      if (rest.startsWith('https://')) {
        bytes = Uint8List.fromList(await fetcher.getBytes(Uri.parse(rest)));
        where = rest;
      } else {
        String path = p.normalize(p.join(root, rest));
        if (Directory(path).existsSync()) {
          final List<File> found = Directory(path)
              .listSync()
              .whereType<File>()
              .where((File f) => f.path.endsWith('.wasm'))
              .toList();
          if (found.length != 1) {
            throw DVSourceUnresolved('$rest holds ${found.length} .wasm '
                'files; name the one to add.');
          }
          path = found.single.path;
        }
        if (!File(path).existsSync()) {
          throw DVSourceUnresolved('There is no file at $rest.');
        }
        bytes = File(path).readAsBytesSync();
        where = path;
      }
      final String name = p.basenameWithoutExtension(where);
      final DVResolvedSource resolved = DVResolvedSource(
        descriptor: rest.startsWith('https://')
            ? 'wasm:$rest'
            : 'wasm:${p.relative(where, from: root).replaceAll('\\', '/')}',
        name: name,
        version: '0.0.0',
        directory: p.dirname(where),
        sourceDigest: sha256.convert(bytes).toString(),
        resolvedFrom: where,
        dependency: '',
      );
      final DVWasmSurface surface = dvScanWasm(bytes, name: name);
      return (
        resolved,
        (String id) => dvWasmModuleSpec(
              id: id,
              source: resolved.descriptor,
              bytes: bytes,
              surface: surface,
              elsewhere: elsewhere,
            ),
      );
    }
    if (source.startsWith('c:') || source.startsWith('cargo:')) {
      final bool rust = source.startsWith('cargo:');
      final String rest = source.substring(rust ? 6 : 2);
      final DVResolvedSource resolved =
          rust && !Directory(p.join(root, rest)).existsSync()
              ? await dvResolveCrate(root, rest, fetcher: fetcher)
              : dvResolveLocalSource(root, rust ? 'cargo' : 'c', rest);
      final DVFfiSurface surface =
          rust ? dvScanRust(resolved.directory) : dvScanC(resolved.directory);
      return (
        resolved,
        (String id) => dvFfiModuleSpec(
              id: id,
              source: resolved.descriptor,
              surface: surface,
              elsewhere: elsewhere,
            ),
      );
    }
    if (source.startsWith('npm:')) {
      final DVResolvedSource resolved =
          await dvResolveNpmSource(root, source.substring(4), fetcher: fetcher);
      final DVNpmSurface surface = dvScanNpmPackage(resolved.directory);
      final DVNpmBundles bundles = await dvBundleNpm(surface, fetcher: fetcher);
      return (
        resolved,
        (String id) => dvNpmModuleSpec(
              id: id,
              source: resolved.descriptor,
              surface: surface,
              bundles: bundles,
              elsewhere: elsewhere,
            ),
      );
    }
    final DVResolvedSource resolved = await dvResolveDartSource(
      root,
      source.startsWith('path:') ? source.substring(5) : source,
      fetcher: fetcher,
    );
    final DVDartSurface surface = dvScanDartPackage(resolved.directory);
    return (
      resolved,
      (String id) => dvDartPackageModuleSpec(
            id: id,
            source: resolved.descriptor,
            surface: surface,
            dependency: resolved.dependency,
            elsewhere: elsewhere,
          ),
    );
  }

  /// Writes the pin a foreign module was planned with into the lock.
  static void _pin(String root, DVAddPlan plan) {
    final DVModulePin? pin = plan.pin;
    if (pin == null) return;
    final DVModuleLock lock = DVModuleLock.read(root);
    DVModuleLock(<String, DVModulePin>{...lock.pins, pin.package: pin})
        .write(root);
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
          '${found.reason} To wrap it as a module anyway, add it as '
          'path:$source.',
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
      // A binary travels as base64 under its name plus .base64, and is
      // written as the bytes it stands for.
      final bool binary = file.key.endsWith('.base64');
      final File out = File(p.join(root, plan.path,
          binary ? file.key.substring(0, file.key.length - 7) : file.key));
      out.parent.createSync(recursive: true);
      if (binary) {
        out.writeAsBytesSync(base64Decode(file.value));
      } else {
        out.writeAsStringSync(file.value);
      }
    }
  }

  /// Adds the module's package to `dependencies`, creating the key if the
  /// pubspec has none.
  ///
  /// The mount alone is not enough: the generated client writes
  /// `import 'package:<name>/...'` for a mounted module's pages, and without
  /// the dependency that import does not resolve. A mount on its own leaves
  /// a project that no longer builds, which is the thing this command exists
  /// not to do.
  static void _depend(String root, DVAddPlan plan) {
    final File file = File(p.join(root, 'pubspec.yaml'));
    final String text = file.readAsStringSync();
    final Object? doc = _yamlOf(file);
    final Object? dependencies = doc is Map ? doc['dependencies'] : null;
    if (dependencies is Map && dependencies.containsKey(plan.packageName)) {
      return;
    }
    final String entry = '  ${plan.packageName}:\n'
        '    path: ${plan.path}\n';

    final RegExp key = RegExp(r'^dependencies:\s*$', multiLine: true);
    final RegExpMatch? existing = key.firstMatch(text);
    if (existing == null) {
      file.writeAsStringSync(
        '${text.trimRight()}\n\ndependencies:\n$entry',
      );
      return;
    }
    file.writeAsStringSync(
      '${text.substring(0, existing.end)}\n$entry'
      '${text.substring(existing.end).replaceFirst('\n', '')}',
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
