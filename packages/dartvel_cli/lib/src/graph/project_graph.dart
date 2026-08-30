import 'dart:io';

import 'package:path/path.dart' as p;

import '../generators/route_utils.dart';

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
  });

  /// The shape version. See the class doc: this is a contract, not a stamp.
  int get graphVersion => 1;

  /// Application nodes only. The backend generator also registers framework
  /// built-ins -- `/health`, `/openapi.json`, `/graphql` and its two siblings
  /// -- which are served but are not something the application declared, so
  /// they are not graph nodes. Verified against the example: 19 function files
  /// on disk, 19 in the graph, 24 routes registered.
  final List<DVGraphModel> models;
  final List<DVGraphRoute> routes;
  final List<DVGraphFunction> functions;
  final List<DVGraphJob> jobs;

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
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'graphVersion': graphVersion,
        'models': models.map((DVGraphModel m) => m.toJson()).toList(),
        'routes': routes.map((DVGraphRoute r) => r.toJson()).toList(),
        'functions': functions.map((DVGraphFunction f) => f.toJson()).toList(),
        'jobs': jobs.map((DVGraphJob j) => j.toJson()).toList(),
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
    for (final Match match in _modelPattern.allMatches(source)) {
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

  static final RegExp _fieldPattern = RegExp(
    r'(@DVModel\.sensitiveField\(\)\s*)?final\s+([A-Za-z0-9_<>, ?]+?)\s+'
    r'([A-Za-z0-9_]+)\s*;',
  );

  static List<DVGraphField> _fieldsIn(String body) {
    return _fieldPattern
        .allMatches(body)
        .map(
          (Match m) => DVGraphField(
            name: m.group(3)!,
            type: m.group(2)!.trim(),
            sensitive: m.group(1) != null,
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
    final Match? match = _pagePattern.firstMatch(source);
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

  static final RegExp _functionPattern = RegExp(
    r'@DVBackendFunction\s*\([^)]*\)\s*(?:@pragma\([^)]*\)\s*)*'
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
  });

  final String path;
  final String page;
  final String source;

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'page': page,
        'source': source,
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
