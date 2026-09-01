import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../graph/project_graph.dart';
import '../graph/windowing_config.dart';

/// `dartvel inspect` — what this application is made of.
///
/// Every subcommand answers from the same [DartvelProjectGraph] rather than
/// rediscovering the project for itself, so two inspectors cannot disagree
/// about the same fact. `--json` is a serialization of that graph, not a
/// separate rendering path.
///
/// Output goes to stdout unprefixed: `--json` has to be parseable by whatever
/// reads it.
class InspectCommand extends Command<void> {
  @override
  final String name = 'inspect';

  @override
  final String description =
      'Inspect the project graph: routes, models, functions and jobs.';

  @override
  String get invocation =>
      'dartvel inspect [routes|models|model <Name>|functions|function <name>|jobs|windows] [--json]';

  InspectCommand() {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Emit the graph as JSON. The shape is versioned by graphVersion.',
    );
  }

  @override
  Future<void> run() async {
    final bool asJson = argResults!['json'] as bool;
    final List<String> rest = argResults!.rest;
    final String root = Directory.current.path;

    final DartvelProjectGraph graph = await DartvelProjectGraph.build(
      root: root,
      pkgName: _packageName(root),
    );

    if (rest.isEmpty) {
      if (asJson) {
        _emit(const JsonEncoder.withIndent('  ').convert(graph.toJson()));
        return;
      }
      _emitSummary(graph);
      return;
    }

    switch (rest.first) {
      case 'routes':
        _emitList(
          asJson,
          graph.routes.map((DVGraphRoute r) => r.toJson()).toList(),
          graph.routes
              .map((DVGraphRoute r) => '${r.path}  ${r.page}  ${r.source}'),
          'No routes found under lib/pages.',
        );
      case 'models':
        _emitList(
          asJson,
          graph.models.map((DVGraphModel m) => m.toJson()).toList(),
          graph.models.map(
            (DVGraphModel m) => '${m.name}  ${m.fields.length} fields  ${m.source}',
          ),
          'No @DVModel inputs found.',
        );
      case 'functions':
        _emitList(
          asJson,
          graph.functions.map((DVGraphFunction f) => f.toJson()).toList(),
          graph.functions.map(
            (DVGraphFunction f) => '${f.method} ${f.path}  ${f.name}  ${f.source}',
          ),
          'No @DVBackendFunction inputs found.',
        );
      case 'jobs':
        _emitList(
          asJson,
          graph.jobs.map((DVGraphJob j) => j.toJson()).toList(),
          graph.jobs
              .map((DVGraphJob j) => '${j.name}  queue=${j.queue}  ${j.source}'),
          'No @DVJob inputs found.',
        );
      case 'windows':
        _emitWindows(root, graph, asJson);
      case 'model':
        _emitModel(graph, rest.length > 1 ? rest[1] : null, asJson);
      case 'function':
        _emitFunction(graph, rest.length > 1 ? rest[1] : null, asJson);
      default:
        throw UsageException(
          'Unknown inspector "${rest.first}".',
          invocation,
        );
    }
  }

  /// The static windowing picture: the policy in effect, and where each part
  /// of it came from.
  ///
  /// Not the live window list. That needs a running application to ask, and
  /// this command reads a directory -- saying so is better than reporting an
  /// empty list, which would read as "no windows are open".
  void _emitWindows(String root, DartvelProjectGraph graph, bool asJson) {
    final DVWindowingConfig config =
        DVWindowingConfig.parse(_dartvelSection(root));

    if (asJson) {
      _emit(const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'graphVersion': graph.graphVersion,
        'windowing': config.toJson(),
        // Window identity is the canonical URL, so every route is a window
        // that could be opened rather than a separate declaration.
        'routes': graph.routes.length,
        'live': null,
      }));
      return;
    }

    _emit('windowing');
    for (final MapEntry<String, Object?> entry
        in <String, Object?>{
      'enabled': config.enabled,
      'singleInstance': config.singleInstance,
      'exit': config.exit,
      'restoreOnLaunch': config.restoreOnLaunch,
      'workspace.persist': config.workspacePersist,
      'workspace.tearOut': config.workspaceTearOut,
    }.entries) {
      final String source = config.sources[entry.key] ?? 'default';
      _emit('  ${entry.key.padRight(20)} ${entry.value}'
          '${source == 'default' ? '  (default)' : ''}');
    }
    _emit('  ${'routes'.padRight(20)} ${graph.routes.length}'
        '  (window identity is the route URL)');

    config.displayNames.forEach((String id, Map<String, int> names) {
      final String pairs = names.entries
          .map((MapEntry<String, int> e) => '${e.key}=${e.value}')
          .join(', ');
      _emit('  ${'displays[$id]'.padRight(20)} $pairs');
    });

    for (final String problem in config.problems) {
      _emit('  ! $problem');
    }
    _emit('');
    _emit('The live window list needs a running application to ask.');
  }

  /// The `dartvel:` section of the project's pubspec, or null.
  static Object? _dartvelSection(String root) {
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    try {
      final Object? loaded = loadYaml(pubspec.readAsStringSync());
      return loaded is YamlMap ? loaded['dartvel'] : null;
    } on Object {
      // A pubspec that will not parse is the build's problem to report, not
      // this inspector's to crash on.
      return null;
    }
  }

  void _emitModel(DartvelProjectGraph graph, String? name, bool asJson) {
    if (name == null) {
      throw UsageException('Name the model to inspect.', invocation);
    }
    final Iterable<DVGraphModel> matches =
        graph.models.where((DVGraphModel m) => m.name == name);
    if (matches.isEmpty) {
      // Saying nothing would read as "this model has no fields".
      _emit('Model "$name" not found. Known models: '
          '${graph.models.isEmpty ? '(none)' : graph.models.map((DVGraphModel m) => m.name).join(', ')}');
      return;
    }
    final DVGraphModel model = matches.first;
    if (asJson) {
      _emit(const JsonEncoder.withIndent('  ').convert(model.toJson()));
      return;
    }
    _emit('${model.name}  ${model.source}');
    for (final DVGraphField field in model.fields) {
      // Named, marked, never valued.
      _emit('  ${field.type} ${field.name}'
          '${field.sensitive ? '  (sensitive)' : ''}');
    }
  }

  void _emitFunction(DartvelProjectGraph graph, String? name, bool asJson) {
    if (name == null) {
      throw UsageException('Name the function to inspect.', invocation);
    }
    final Iterable<DVGraphFunction> matches =
        graph.functions.where((DVGraphFunction f) => f.name == name);
    if (matches.isEmpty) {
      _emit('Function "$name" not found. Known functions: '
          '${graph.functions.isEmpty ? '(none)' : graph.functions.map((DVGraphFunction f) => f.name).join(', ')}');
      return;
    }
    final DVGraphFunction function = matches.first;
    if (asJson) {
      _emit(const JsonEncoder.withIndent('  ').convert(function.toJson()));
      return;
    }
    _emit('${function.name}  ${function.method} ${function.path}  '
        '${function.source}');
  }

  void _emitList(
    bool asJson,
    List<Map<String, Object?>> json,
    Iterable<String> lines,
    String whenEmpty,
  ) {
    if (asJson) {
      _emit(const JsonEncoder.withIndent('  ').convert(json));
      return;
    }
    if (json.isEmpty) {
      _emit(whenEmpty);
      return;
    }
    lines.forEach(_emit);
  }

  void _emitSummary(DartvelProjectGraph graph) {
    _emit('graphVersion ${graph.graphVersion}');
    _emit('  routes     ${graph.routes.length}');
    _emit('  models     ${graph.models.length}');
    _emit('  functions  ${graph.functions.length}');
    _emit('  jobs       ${graph.jobs.length}');
    _emit('');
    _emit('dartvel inspect routes | models | functions | jobs');
    _emit('dartvel inspect model <Name> | function <name>');
    _emit('dartvel inspect --json');
  }

  // ignore: avoid_print
  void _emit(String line) => print(line);

  static String _packageName(String root) {
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return 'app';
    final Object? loaded = loadYaml(pubspec.readAsStringSync());
    if (loaded is YamlMap && loaded['name'] is String) {
      return loaded['name'] as String;
    }
    return 'app';
  }
}
