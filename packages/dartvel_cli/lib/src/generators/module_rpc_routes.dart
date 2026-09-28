/// The routes that answer module calls carried to the backend.
///
/// A module operation declared `{compat: backend}` in some environment is
/// sent to the application's backend by that environment's carrier. This
/// file finds those operations among the modules the application mounts and
/// writes one route for each, behind the policy the application names for
/// the module under `dartvel.modules.<id>.backendPolicy`.
///
/// The route runs the operation with the server's authority, not the
/// caller's -- a package that reads files reads the server's -- so a module
/// that carries anything here and names no policy is refused at build time
/// (DV-MODULE-021). `public` is accepted, and has to be written.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// One carried operation, and who may call it.
class DVModuleRpcRoute {
  const DVModuleRpcRoute({
    required this.module,
    required this.operation,
    required this.packageName,
    required this.policy,
    required this.alias,
  });

  /// The module's own id: what [path] is named after.
  final String module;
  final String operation;
  final String packageName;

  /// A policy name, or `public`.
  final String policy;

  /// The import prefix of the module's backend carrier.
  final String alias;

  String get path => '/_dv/modules/$module/$operation';
}

/// Thrown when a carried operation has no policy.
class DVModuleRpcPolicyMissing implements Exception {
  const DVModuleRpcPolicyMissing(this.message);
  final String message;
  @override
  String toString() => 'DV-MODULE-021: $message';
}

/// Every carried operation of every module mounted from a path in [root].
List<DVModuleRpcRoute> dvModuleRpcRoutes(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return const <DVModuleRpcRoute>[];
  final Object? doc = loadYaml(pubspec.readAsStringSync());
  final Object? modules =
      doc is Map && doc['dartvel'] is Map ? doc['dartvel']['modules'] : null;
  if (modules is! Map) return const <DVModuleRpcRoute>[];

  final List<DVModuleRpcRoute> routes = <DVModuleRpcRoute>[];
  var index = 0;
  for (final MapEntry<Object?, Object?> entry in modules.entries) {
    final Object? body = entry.value;
    if (body is! Map) continue;
    final Object? source = body['source'];
    final Object? path = source is Map ? source['path'] : null;
    if (path is! String) continue;
    final File modulePubspec = File(p.join(root, path, 'pubspec.yaml'));
    if (!modulePubspec.existsSync()) continue;
    final Object? moduleDoc = loadYaml(modulePubspec.readAsStringSync());
    if (moduleDoc is! Map) continue;
    final Object? module =
        moduleDoc['dartvel'] is Map ? moduleDoc['dartvel']['module'] : null;
    if (module is! Map || module['operations'] is! Map) continue;

    final List<String> carried = <String>[
      for (final MapEntry<Object?, Object?> op
          in (module['operations'] as Map).entries)
        if (op.value is Map &&
            (op.value as Map).values.any((Object? outcome) =>
                outcome is Map && outcome['compat'] == 'backend'))
          '${op.key}',
    ];
    if (carried.isEmpty) continue;

    final String id = '${module['id'] ?? entry.key}';
    final Object? policy = body['backendPolicy'];
    if (policy is! String || policy.trim().isEmpty) {
      throw DVModuleRpcPolicyMissing(
        '${carried.map((String op) => '$id.$op').join(', ')} '
        '${carried.length == 1 ? 'is' : 'are'} carried to the backend, where '
        'the call runs with the server\'s authority, and dartvel.modules.'
        '${entry.key} names no backendPolicy. Name the policy that may call '
        'it -- backendPolicy: <a DVPolicies name> -- or write '
        'backendPolicy: public to serve it to anybody.',
      );
    }
    final String alias = 'dvRpcModule${index++}';
    for (final String op in carried) {
      routes.add(DVModuleRpcRoute(
        module: id,
        operation: op,
        packageName: '${moduleDoc['name']}',
        policy: policy.trim(),
        alias: alias,
      ));
    }
  }
  return routes;
}

/// The imports [routes] need, one per module.
String dvModuleRpcImports(List<DVModuleRpcRoute> routes) {
  final Map<String, String> byAlias = <String, String>{
    for (final DVModuleRpcRoute r in routes) r.alias: r.packageName,
  };
  return byAlias.entries
      .map((MapEntry<String, String> e) =>
          "import 'package:${e.value}/src/carrier_backend.dart' as ${e.key} "
          'show dvModuleDispatch;\n')
      .join();
}

/// The route registrations for [routes], written into the backend router.
///
/// Each is staged like every other route that is not a backend function --
/// tenant, privacy and authentication -- asks the module's policy, checks the
/// CSRF token a browser sends, and answers `{"result": ...}`. A body that is
/// not a JSON object, or arguments the operation cannot read, is a 400
/// naming nothing from the request.
String dvModuleRpcRegistrations(List<DVModuleRpcRoute> routes) {
  final StringBuffer out = StringBuffer();
  for (final DVModuleRpcRoute r in routes) {
    final String guard = r.policy == 'public'
        ? ''
        : "    if (!await _dvAllowed('${r.policy}', req)) "
            "return _dvPolicyForbidden('${r.policy}');\n";
    out.write('''
  // ${r.module}.${r.operation}, carried here from a client that cannot run it.
  router.post(cfg.apiBasePath + '${r.path}', (dv.Request req) => _dvStaged(req, () async {
$guard    if (!_dvValidateCsrf(req, null)) return _dvCsrfForbidden();
    final Map<String, Object?> arguments;
    try {
      final Object? decoded = conv.jsonDecode(await req.body.text());
      arguments = (decoded as Map).cast<String, Object?>();
    } on Object {
      return _dvModuleRpcBadRequest();
    }
    final Object? result;
    try {
      result = await ${r.alias}.dvModuleDispatch('${r.operation}', arguments);
    } on TypeError {
      return _dvModuleRpcBadRequest();
    }
    return dv.Response(200,
        headers: dv.Headers({'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'}),
        body: Stream<List<int>>.value(conv.utf8.encode(conv.jsonEncode(<String, Object?>{'result': result}))));
  }));
''');
  }
  if (routes.isNotEmpty) {
    out.write('''
''');
  }
  return out.toString();
}

/// The shared 400 for a module call the backend could not read.
const String dvModuleRpcHelpers = r'''
dv.Response _dvModuleRpcBadRequest() => dv.Response(400,
    headers: dv.Headers({'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store'}),
    body: Stream<List<int>>.value(conv.utf8.encode('Bad module call')));
''';
