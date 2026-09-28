/// Studio on a development server: `dartvel preview` and `dartvel dev`.
///
/// A web-server binary serves Studio with the generated specs and its own
/// database, to accounts granted `Studio.access`. A development server has
/// the same Studio to serve and neither of those: the CLI cannot import the
/// application's generated code, and a developer's machine has no account
/// anybody granted. So the models come from the manifest the generator
/// writes beside the schema, the data from the project's own database, and
/// the gate is a development grant printed as a link.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show
        DVAdminMount,
        DVDatabaseAdapter,
        DVDatabaseConnection,
        DVStudioModelSpec,
        SqliteDVDatabaseAdapter;
import 'package:path/path.dart' as p;

import '../graph/project_graph.dart' show DartvelProjectGraph;

import '../commands/db_command.dart' show dvDatabaseSettings;
import 'admin_mount.dart' show dvAdminMount;

/// The mount a development server serves Studio at: where the project put
/// it, on unless the project turned it off, and behind the development grant.
DVAdminMount dvDevStudioMount(Object? dartvel) {
  final DVAdminMount declared = dvAdminMount(dartvel, release: false);
  return DVAdminMount(
    path: declared.path,
    enabled: declared.enabled,
    requiresAuth: true,
  );
}

/// The models the generator described in `.dart_tool`, or none before the
/// project was generated.
List<DVStudioModelSpec> dvDevStudioModels(String root) {
  final File manifest =
      File(p.join(root, '.dart_tool', 'dartvel_studio_models.json'));
  if (!manifest.existsSync()) return const <DVStudioModelSpec>[];
  try {
    final Object? decoded = jsonDecode(manifest.readAsStringSync());
    final Object? models = decoded is Map ? decoded['models'] : null;
    return <DVStudioModelSpec>[
      if (models is List)
        for (final Object? model in models)
          if (model is Map)
            DVStudioModelSpec.fromManifest(model.cast<String, Object?>()),
    ];
  } on FormatException {
    return const <DVStudioModelSpec>[];
  }
}

/// The project's database: `DATABASE_URL`, else the SQLite file
/// `dartvel.database` names, created on first use the way local development
/// creates it. Null for a server database with no URL to reach it.
DVDatabaseAdapter? dvDevStudioDatabase(
  String root,
  Map<String, String> environment,
) {
  final DVDatabaseConnection? connection =
      DVDatabaseConnection.fromEnvironment(environment);
  if (connection != null) return connection.open();
  final ({String provider, String path}) settings = dvDatabaseSettings(root);
  if (settings.provider != 'sqlite') return null;
  final String file = p.isAbsolute(settings.path)
      ? settings.path
      : p.join(root, settings.path);
  File(file).parent.createSync(recursive: true);
  return SqliteDVDatabaseAdapter.file(file);
}

/// Writes the project graph into [adminRoot], where Studio's Site map and
/// Pages read the compiled routes from, as `dartvel build` writes it beside
/// the Studio it compiles. A graph that cannot be built leaves the last one
/// in place: a page mid-edit that fails to parse is not a reason to list no
/// pages at all.
Future<void> dvWriteDevStudioGraph({
  required String root,
  required String adminRoot,
}) async {
  try {
    final Object? declared = _pubspecName(root);
    final DartvelProjectGraph graph = await DartvelProjectGraph.build(
      root: root,
      pkgName: declared is String ? declared : p.basename(root),
    );
    Directory(adminRoot).createSync(recursive: true);
    File(p.join(adminRoot, 'graph.json'))
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(graph.toJson()));
  } on Object {
    // Kept as it was.
  }
}

Object? _pubspecName(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return null;
  final RegExpMatch? name = RegExp(r'^name:\s*([A-Za-z0-9_]+)', multiLine: true)
      .firstMatch(pubspec.readAsStringSync());
  return name?.group(1);
}
