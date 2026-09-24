import 'dart:io';
import '../module_trust/module_lock.dart';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../generators/account_generator.dart';
import '../generators/annotation_args.dart';
import '../generators/route_utils.dart';
import 'module_mounts.dart';

/// A versioned description of what an application is made of.
///
/// The inspectors are eight questions about one artifact, so this is built
/// first and `--json` serializes it. Built the other way round each generator
/// would answer from its own rediscovery of the source, and the answers would
/// disagree at the edges.
///
/// [graphVersion] is a contract: a consumer that understands version 1 keeps
/// working, and a breaking change to the shape increments it rather than
/// quietly reshaping a field.
class DartvelProjectGraph {
  const DartvelProjectGraph({
    required this.models,
    required this.routes,
    required this.functions,
    required this.jobs,
    this.modules = const <DVGraphModule>[],
  });

  /// The shape version. See the class doc: this is a contract, not a stamp.
  ///
  /// Version 2 added the modules key. A consumer that understood version 1
  /// can tell that this file carries a key it has never seen.
  int get graphVersion => 2;

  /// Application nodes only. The backend generator also registers framework
  /// built-ins -- `/health`, `/openapi.json`, `/graphql` and its two siblings
  /// -- which are served but are not something the application declared, so
  /// they are not graph nodes. Verified against the example: 19 function files
  /// on disk, 19 in the graph, 24 routes registered.
  final List<DVGraphModel> models;
  final List<DVGraphRoute> routes;
  final List<DVGraphFunction> functions;
  final List<DVGraphJob> jobs;

  /// The modules this project mounts, including the ones the build could
  /// not mount. A declaration the build could not honour has to appear
  /// somewhere an operator looks; leaving it out is how an application ships
  /// without a section and nobody finds out until a customer does.
  final List<DVGraphModule> modules;

  /// Scans [root] and answers what it is made of.
  static Future<DartvelProjectGraph> build({
    required String root,
    required String pkgName,
  }) async {
    final List<File> files = _dartFiles(root);
    final List<DVGraphModel> models = <DVGraphModel>[];
    final List<DVGraphRoute> routes = <DVGraphRoute>[];
    final List<DVGraphFunction> functions = <DVGraphFunction>[];
    final List<DVGraphJob> jobs = <DVGraphJob>[];

    for (final File file in files) {
      final String source = file.readAsStringSync();
      final String rel =
          p.relative(file.path, from: root).replaceAll('\\', '/');

      models.addAll(_modelsIn(source, rel));
      jobs.addAll(_jobsIn(source, rel));
      if (rel.contains('/backend/functions/')) {
        functions.addAll(_functionsIn(source, rel));
      } else {
        routes.addAll(_routesIn(source, rel));
      }
    }

    routes.addAll(_accountRoutesIn(root));
    routes.addAll(_moduleRoutesIn(root));
    final List<DVGraphModule> modules = _modulesIn(root);

    // Ordered so two builds of one project diff cleanly.
    models.sort((DVGraphModel a, DVGraphModel b) => a.name.compareTo(b.name));
    routes.sort((DVGraphRoute a, DVGraphRoute b) => a.path.compareTo(b.path));
    functions
        .sort((DVGraphFunction a, DVGraphFunction b) => a.path.compareTo(b.path));
    jobs.sort((DVGraphJob a, DVGraphJob b) => a.name.compareTo(b.name));

    return DartvelProjectGraph(
      models: models,
      routes: routes,
      functions: functions,
      jobs: jobs,
      modules: modules,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'graphVersion': graphVersion,
        'models': models.map((DVGraphModel m) => m.toJson()).toList(),
        'routes': routes.map((DVGraphRoute r) => r.toJson()).toList(),
        'functions': functions.map((DVGraphFunction f) => f.toJson()).toList(),
        'jobs': jobs.map((DVGraphJob j) => j.toJson()).toList(),
        'modules': modules.map((DVGraphModule m) => m.toJson()).toList(),
      };

  static List<File> _dartFiles(String root) {
    final Directory lib = Directory(p.join(root, 'lib'));
    if (!lib.existsSync()) return const <File>[];
    return lib
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        // Generated output is derived from the graph's own inputs; reading it
        // back would double every node.
        .where((File f) => !f.path.contains('dartvel_client'))
        .where((File f) => !f.path.endsWith('.g.dart'))
        .toList()
      ..sort((File a, File b) => a.path.compareTo(b.path));
  }

  static final RegExp _modelPattern = RegExp(
    r'@DVModel\s*\([^)]*\)\s*(?:@pragma\([^)]*\)\s*)*class\s+([A-Za-z0-9_]+)\b',
    dotAll: true,
  );

  static final RegExp _jobPattern = RegExp(
    r'@DVJob\s*\(([^)]*)\)\s*(?:@pragma\([^)]*\)\s*)*class\s+([A-Za-z0-9_]+)\b',
    dotAll: true,
  );

  static List<DVGraphModel> _modelsIn(String source, String rel) {
    final List<DVGraphModel> found = <DVGraphModel>[];
    // Blanked annotation arguments, because `[^)]*` stops at the first
    // close parenthesis and a string argument can contain one. The model
    // generator masks the same way, and a model this misses while the
    // generator finds it is a table in the database with no row here.
    for (final Match match
        in _modelPattern.allMatches(dvMaskAnnotationArgs(source, 'DVModel'))) {
      final String declared = match.group(1)!;
      final int bodyStart = source.indexOf('{', match.end - 1);
      if (bodyStart == -1) continue;
      final int bodyEnd = _matchingBrace(source, bodyStart);
      final String body = source.substring(bodyStart, bodyEnd);
      found.add(
        DVGraphModel(
          name: _publicName(declared),
          source: '$rel:${_lineOf(source, match.start)}',
          fields: _fieldsIn(body),
        ),
      );
    }
    return found;
  }

  /// A field and the whole annotation stack above it.
  ///
  /// The stack, not one annotation directly above the `final`: the model
  /// generator already skips other annotations standing between a field
  /// annotation and its declaration, and a graph that required
  /// `@DVModel.sensitiveField()` to be last, with empty parentheses, described
  /// `@DVModel.sensitiveField(encrypted: true)` -- and any sensitive field
  /// with a searchable one under it -- as an ordinary field, to `inspect`, to
  /// an agent over MCP and to the documentation site alike.
  static final RegExp _fieldPattern = RegExp(
    r'((?:@[A-Za-z_][A-Za-z0-9_.]*\s*(?:\([^)]*\))?\s*)*)'
    r'final\s+([A-Za-z0-9_<>, ?]+?)\s+([A-Za-z0-9_]+)\s*;',
  );

  static final RegExp _sensitiveAnnotation =
      RegExp(r'@(?:DVModel\.sensitiveField|DVSensitiveModelField)\s*\(');

  static List<DVGraphField> _fieldsIn(String body) {
    return _fieldPattern
        .allMatches(body)
        .map(
          (Match m) => DVGraphField(
            name: m.group(3)!,
            type: m.group(2)!.trim(),
            sensitive: _sensitiveAnnotation.hasMatch(m.group(1) ?? ''),
          ),
        )
        .toList(growable: false);
  }

  static List<DVGraphJob> _jobsIn(String source, String rel) {
    final List<DVGraphJob> found = <DVGraphJob>[];
    for (final Match match in _jobPattern.allMatches(source)) {
      final String args = match.group(1) ?? '';
      final Match? queue =
          RegExp("queue\\s*:\\s*'([^']*)'").firstMatch(args);
      found.add(
        DVGraphJob(
          name: _publicName(match.group(2)!),
          queue: queue?.group(1) ?? 'default',
          source: '$rel:${_lineOf(source, match.start)}',
        ),
      );
    }
    return found;
  }

  static final RegExp _pagePattern = RegExp(
    r'@DVPage\s*\([^)]*\)\s*(?:@pragma\([^)]*\)\s*)*'
    r'(?:@DVFunctionalWidget\(\)\s*)?Widget\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(',
    dotAll: true,
  );

  static List<DVGraphRoute> _routesIn(String source, String rel) {
    // Matched against a copy whose annotation arguments are blanked to
    // spaces, because this pattern steps over `@DVPage(...)` to reach the
    // function under it and `[^)]*` stops inside a nested call -- so a page
    // declaring `sitemap: DVPageSitemap(...)` was not in the graph at all,
    // and the admin dashboard and the studio both simply did not show it.
    final Match? match =
        _pagePattern.firstMatch(dvMaskAnnotationArgs(source, 'DVPage'));
    if (match == null) return const <DVGraphRoute>[];
    // Routes are derived from the file's location, never written out as a
    // string: a repeated route drifts the moment the page file moves.
    String path;
    try {
      path = RouteUtils.routeFor(rel, 'lib/pages');
    } on Object {
      return const <DVGraphRoute>[];
    }
    return <DVGraphRoute>[
      DVGraphRoute(
        path: path,
        page: _publicName(match.group(1)!),
        source: '$rel:${_lineOf(source, match.start)}',
      ),
    ];
  }

  /// The `dartvel:` section of the project's pubspec.yaml, or null when the
  /// project has no pubspec to generate from.
  static Map<Object?, Object?>? _dartvelSection(String root) {
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    try {
      final Object? doc = loadYaml(pubspec.readAsStringSync());
      final Object? section = doc is Map ? doc['dartvel'] : null;
      return section is Map ? section : const <Object?, Object?>{};
    } on Object {
      return null;
    }
  }

  /// The prebuilt account pages the generated router serves.
  ///
  /// Not files under lib/pages, so a scan of the pages never saw them: the
  /// routes tab listed an application with no /login while the router
  /// served one. Read through the generator's own reader, so the graph and
  /// the router cannot disagree about where a page is or whether it exists.
  static List<DVGraphRoute> _accountRoutesIn(String root) {
    final Map<Object?, Object?>? dv = _dartvelSection(root);
    if (dv == null) return const <DVGraphRoute>[];
    final List<AccountPageRoute> pages;
    try {
      pages = AccountGenerator.readPages(dv);
    } on StateError {
      // The generator refuses the same declaration, loudly, on the build.
      return const <DVGraphRoute>[];
    }
    return <DVGraphRoute>[
      for (final AccountPageRoute page in pages)
        DVGraphRoute(
          path: page.path,
          page: page.widget,
          source: 'pubspec.yaml: dartvel.auth.pages.${page.key}',
          kind: 'account page',
        ),
    ];
  }

  /// The modules the parent declares, mounted or not.
  static List<DVGraphModule> _modulesIn(String root) {
    if (_dartvelSection(root)?['modules'] == null) {
      return const <DVGraphModule>[];
    }
    // Read once for every module rather than once per module: the lockfile is
    // one file, and reading it in a loop would parse it as many times as the
    // project has modules. A lockfile that will not parse pins nothing, and
    // the graph reports no pin rather than a wrong one.
    final Map<String, DVModulePin> pins = DVModuleLock.read(root).pins;
    final List<DVGraphModule> found = <DVGraphModule>[
      for (final DVModuleMount mount in dvDiscoverModuleMounts(root))
        DVGraphModule(
          id: mount.id,
          package: mount.packageName,
          mount: mount.mount,
          source: mount.fromPackage ? mount.packageName : mount.sourcePath,
          deployment: mount.deployment.name,
          mounted: mount.mounted,
          pages: mount.routes.length,
          data: mount.data,
          name: mount.name,
          version: mount.version,
          location: mount.location,
          backend: mount.backend,
          fromPackage: mount.fromPackage,
          problems: mount.problems,
          // Keyed by package, which is what the lockfile pins: a module's id
          // is what the parent calls it and two parents may call one package
          // different things.
          pin: pins[mount.packageName] == null
              ? null
              : DVGraphModulePin.of(pins[mount.packageName]!),
        ),
    ];
    found.sort((DVGraphModule a, DVGraphModule b) => a.id.compareTo(b.id));
    return found;
  }

  /// The routes mounted modules contribute, at the path the parent serves
  /// them, each with the module file it came from.
  static List<DVGraphRoute> _moduleRoutesIn(String root) {
    if (_dartvelSection(root)?['modules'] == null) return const <DVGraphRoute>[];
    final List<DVGraphRoute> found = <DVGraphRoute>[];
    for (final DVModuleMount mount in dvDiscoverModuleMounts(root)) {
      for (final DVModuleRoute route in mount.routes) {
        final String rel = p
            .normalize(p.join(mount.sourcePath, route.file))
            .replaceAll('\\', '/');
        final File file = File(p.join(root, rel));
        int line = 1;
        if (file.existsSync()) {
          final String source = file.readAsStringSync();
          final Match? match =
              _pagePattern.firstMatch(dvMaskAnnotationArgs(source, 'DVPage'));
          if (match != null) line = _lineOf(source, match.start);
        }
        found.add(DVGraphRoute(
          path: route.mounted,
          page: route.widget,
          source: mount.fromPackage ? '${mount.packageName}: ${route.file}:$line' : '$rel:$line',
          kind: 'module page',
          module: mount.id,
        ));
      }
    }
    return found;
  }

  /// Any annotations may follow `@DVBackendFunction` -- `@DVUseMiddleware`
  /// most often. The pattern used to step over `@pragma` and nothing else, so
  /// a function with middleware under its annotation was read as an
  /// unannotated file named after itself, at line 1.
  static final RegExp _functionPattern = RegExp(
    r'@DVBackendFunction\s*\([^)]*\)\s*'
    r'(?:@[A-Za-z_][A-Za-z0-9_.]*\s*(?:\([^)]*\))?\s*)*'
    r'(?:Future<[^>]*>|Stream<[^>]*>|[A-Za-z_][A-Za-z0-9_<>, ?]*)\s+'
    r'([A-Za-z_][A-Za-z0-9_]*)\s*\(',
    dotAll: true,
  );

  /// The methods a filename suffix may name. Anything else -- including no
  /// suffix at all -- is POST, matching what the generator registers.
  static const Set<String> _methods = <String>{
    'get',
    'post',
    'put',
    'delete',
    'patch',
    'head',
    'options',
  };

  static List<DVGraphFunction> _functionsIn(String source, String rel) {
    // Backend functions are file-based. A file under backend/functions is a
    // served route whether or not it carries @DVBackendFunction, so the
    // annotation decides the name, never whether the endpoint exists.
    final String base = p.basenameWithoutExtension(rel);
    final int dot = base.lastIndexOf('.');
    final String suffix = dot == -1 ? '' : base.substring(dot + 1).toLowerCase();
    final String method =
        _methods.contains(suffix) ? suffix.toUpperCase() : 'POST';

    final Match? match = _functionPattern.firstMatch(source);
    final String name = match != null
        ? _publicName(match.group(1)!)
        : (dot == -1 ? base : base.substring(0, dot))
            .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');

    return <DVGraphFunction>[
      DVGraphFunction(
        name: name,
        method: method,
        path: RouteUtils.routeFromRel(rel, 'lib/backend'),
        source: '$rel:${match == null ? 1 : _lineOf(source, match.start)}',
        annotated: match != null,
      ),
    ];
  }

  static String _publicName(String declared) =>
      declared.startsWith('_') ? declared.substring(1) : declared;

  static int _lineOf(String source, int offset) =>
      '\n'.allMatches(source.substring(0, offset)).length + 1;

  static int _matchingBrace(String source, int open) {
    int depth = 0;
    for (int at = open; at < source.length; at += 1) {
      if (source[at] == '{') depth += 1;
      if (source[at] == '}') {
        depth -= 1;
        if (depth == 0) return at;
      }
    }
    return source.length;
  }
}

/// A model and the fields it declares.
class DVGraphModel {
  const DVGraphModel({
    required this.name,
    required this.source,
    required this.fields,
  });

  final String name;
  final String source;
  final List<DVGraphField> fields;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'source': source,
        'fields': fields.map((DVGraphField f) => f.toJson()).toList(),
      };
}

/// A model field.
///
/// A sensitive field appears here as a field that exists, marked
/// `"sensitive": true`, and carries no value: the schema is what a reader
/// needs, and the data is what it must not be handed.
class DVGraphField {
  const DVGraphField({
    required this.name,
    required this.type,
    required this.sensitive,
  });

  final String name;
  final String type;
  final bool sensitive;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'type': type,
        if (sensitive) 'sensitive': true,
      };
}

/// A route and the page that answers it.
class DVGraphRoute {
  const DVGraphRoute({
    required this.path,
    required this.page,
    required this.source,
    this.kind = 'page',
    this.module,
  });

  final String path;
  final String page;
  final String source;

  /// `page` for a file under the pages directory, `account page` for a
  /// prebuilt account page the router generates, `module page` for a route
  /// a mounted module contributes.
  final String kind;

  /// The id of the module a `module page` comes from.
  final String? module;

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'page': page,
        'source': source,
        'kind': kind,
        if (module != null) 'module': module,
      };
}

/// A backend function and the request that reaches it.
class DVGraphFunction {
  const DVGraphFunction({
    required this.name,
    required this.method,
    required this.path,
    required this.source,
    this.annotated = true,
  });

  final String name;
  final String method;
  final String path;
  final String source;

  /// Whether the file carries `@DVBackendFunction`. It is served either way;
  /// this only says whether the annotation named it.
  final bool annotated;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'method': method,
        'path': path,
        'source': source,
        'annotated': annotated,
      };
}

/// A durable job and the queue it runs on.
class DVGraphJob {
  const DVGraphJob({
    required this.name,
    required this.queue,
    required this.source,
  });

  final String name;
  final String queue;
  final String source;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'queue': queue,
        'source': source,
      };
}

/// One module the parent mounts, as the graph records it.
///
/// Studio's Modules section is the reader: it names what is mounted, where it
/// came from, where it answers, and what is wrong with a declaration the
/// build could not honour. That last one is the reason this is in the graph
/// at all -- a module that failed to mount used to leave no trace anywhere an
/// operator looks.
class DVGraphModule {
  const DVGraphModule({
    required this.id,
    required this.package,
    required this.mount,
    required this.source,
    required this.deployment,
    required this.mounted,
    required this.pages,
    required this.data,
    this.name,
    this.version,
    this.location,
    this.backend,
    this.fromPackage = false,
    this.problems = const <String>[],
    this.pin,
  });

  /// What the parent knows it by: `DV.Modules.<id>`.
  final String id;

  /// The module project's package name.
  final String package;

  /// Where the parent serves it.
  final String mount;

  /// Where its project is, relative to the parent, or the package it came
  /// from.
  final String source;

  /// `embedded`, `split-backend` or `federated`, as declared.
  final String deployment;

  /// Whether the build could honour the declaration. False when there is no
  /// project at the source, or a federated manifest will not verify.
  final bool mounted;

  /// How many pages it contributes to the parent.
  final int pages;

  /// `shared`, `schema-isolated`, `database-isolated` or `remote`.
  final String data;

  final String? name;
  final String? version;

  /// Where a federated module answers from, or null when the parent serves
  /// it.
  final String? location;

  /// Where a split-backend module's functions answer.
  final String? backend;

  /// Whether it is mounted as a dependency instead of from a path.
  final bool fromPackage;

  /// What is wrong with the declaration.
  final List<String> problems;

  /// What the lockfile pinned for this module, or null when nothing did.
  ///
  /// Provenance in one place rather than spread across the node: `source`
  /// here already means where the module's project is, and a reader asking
  /// which bytes a module came from should not have to know that those are
  /// two different questions. Null is a real answer -- a path module in a
  /// monorepo is never pinned -- and inventing a digest for one would make
  /// the graph claim provenance it does not have.
  final DVGraphModulePin? pin;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'package': package,
        'mount': mount,
        'source': source,
        'deployment': deployment,
        'mounted': mounted,
        'pages': pages,
        'data': data,
        if (name != null) 'name': name,
        if (version != null) 'version': version,
        if (location != null) 'location': location,
        if (backend != null) 'backend': backend,
        if (fromPackage) 'fromPackage': true,
        if (problems.isNotEmpty) 'problems': problems,
        if (pin != null) 'pin': pin!.toJson(),
      };

  /// Reads one back, for a consumer of `graph.json`.
  factory DVGraphModule.fromJson(Map<String, Object?> json) => DVGraphModule(
        id: '${json['id'] ?? ''}',
        package: '${json['package'] ?? ''}',
        mount: '${json['mount'] ?? '/'}',
        source: '${json['source'] ?? ''}',
        deployment: '${json['deployment'] ?? 'embedded'}',
        mounted: json['mounted'] != false,
        pages: json['pages'] is int ? json['pages']! as int : 0,
        data: '${json['data'] ?? 'shared'}',
        name: json['name'] as String?,
        version: json['version'] as String?,
        location: json['location'] as String?,
        backend: json['backend'] as String?,
        fromPackage: json['fromPackage'] == true,
        problems: <String>[
          for (final Object? problem
              in (json['problems'] as List?) ?? const <Object?>[])
            '$problem',
        ],
        pin: json['pin'] is Map
            ? DVGraphModulePin.fromJson(
                (json['pin']! as Map).cast<String, Object?>())
            : null,
      );
}

/// What the lockfile pinned for a module, as the graph reports it.
///
/// A module from pub.dev is pinned by the archive the registry served and
/// carries the publisher it verified. A module generated from a foreign
/// source has neither: it is pinned by what was fetched and what was
/// generated from it, and those are separate because a changed source and a
/// changed wrapper are different events whose fixes are opposite.
class DVGraphModulePin {
  const DVGraphModulePin({
    required this.version,
    this.sha256,
    this.publisher,
    this.source,
    this.sourceDigest,
    this.wrapperHash,
    this.generator,
    this.resolvedFrom,
    this.targets = const <String>[],
  });

  final String version;

  /// The pub.dev archive's digest, or null for a foreign source.
  final String? sha256;

  /// The publisher pub.dev verified, or null when none could be asked and
  /// always null for a foreign source, which has no publisher to verify.
  final String? publisher;

  /// The descriptor a foreign module was resolved from, such as
  /// `maven:com.vendor:scanner`.
  final String? source;

  /// The digest of what was fetched.
  final String? sourceDigest;

  /// The digest of the module generated from it.
  final String? wrapperHash;

  /// The generator version that produced [wrapperHash].
  final String? generator;

  /// Where the source was fetched from.
  final String? resolvedFrom;

  /// The targets the generated module declares.
  final List<String> targets;

  /// Whether this came from outside pub.dev.
  bool get isForeign => source != null;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': version,
        if (sha256 != null) 'sha256': sha256,
        if (publisher != null) 'publisher': publisher,
        if (source != null) 'source': source,
        if (sourceDigest != null) 'sourceDigest': sourceDigest,
        if (wrapperHash != null) 'wrapperHash': wrapperHash,
        if (generator != null) 'generator': generator,
        if (resolvedFrom != null) 'resolvedFrom': resolvedFrom,
        if (targets.isNotEmpty) 'targets': targets,
      };

  factory DVGraphModulePin.fromJson(Map<String, Object?> json) =>
      DVGraphModulePin(
        version: '${json['version'] ?? ''}',
        sha256: json['sha256'] as String?,
        publisher: json['publisher'] as String?,
        source: json['source'] as String?,
        sourceDigest: json['sourceDigest'] as String?,
        wrapperHash: json['wrapperHash'] as String?,
        generator: json['generator'] as String?,
        resolvedFrom: json['resolvedFrom'] as String?,
        targets: <String>[
          for (final Object? t in (json['targets'] as List?) ?? const <Object?>[])
            '$t',
        ],
      );

  /// The pin a lockfile entry becomes.
  factory DVGraphModulePin.of(DVModulePin pin) => DVGraphModulePin(
        version: pin.version,
        sha256: pin.sha256,
        publisher: pin.publisher,
        source: pin.source,
        sourceDigest: pin.sourceDigest,
        wrapperHash: pin.wrapperHash,
        generator: pin.generator,
        resolvedFrom: pin.resolvedFrom,
        targets: pin.targets,
      );
}
