import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../graph/project_graph.dart';

/// Serves Dartvel's own tools -- the inspectors over the project graph -- to a
/// coding agent working on the application, over MCP on stdio.
///
/// This is deliberately not the application's tool registry. The spec calls the
/// separation load-bearing rather than tidy: a framework surface that let
/// itself be adopted into the process-global registry would make an agent
/// building the app indistinguishable from an agent the app serves to its
/// users, and one of those can read the project's schema. Keeping these tools
/// in the CLI, in a separate process, is what makes that separation structural
/// rather than a naming convention.
///
/// The redaction rule is the same on both sides: a `@DVModel.sensitiveField()`
/// is described, never valued.
class DartvelFrameworkMcpServer {
  DartvelFrameworkMcpServer({required this.root});

  /// The application being inspected.
  final String root;

  /// The MCP revision this server speaks.
  static const String protocolVersion = '2024-11-05';

  static const String _serverName = 'dartvel';

  /// Every tool is prefixed, so a framework tool can never read as one of the
  /// application's own.
  static const String _prefix = 'dartvel_';

  DartvelProjectGraph? _cached;

  Future<DartvelProjectGraph> _graph() async =>
      _cached ??= await DartvelProjectGraph.build(
        root: root,
        pkgName: _packageName(root),
      );

  /// Handles one JSON-RPC message, returning the response, or null for a
  /// notification.
  Future<Map<String, Object?>?> handle(Map<String, Object?> request) async {
    final Object? id = request['id'];
    final String method = (request['method'] ?? '') as String;

    // A request with no id is a notification. Answering one is a protocol
    // violation, and some clients close the connection on it.
    if (id == null) return null;

    switch (method) {
      case 'initialize':
        return _ok(id, <String, Object?>{
          'protocolVersion': protocolVersion,
          'capabilities': <String, Object?>{
            'tools': <String, Object?>{'listChanged': false},
          },
          'serverInfo': <String, Object?>{
            'name': _serverName,
            'version': '1',
          },
        });
      case 'ping':
        return _ok(id, <String, Object?>{});
      case 'tools/list':
        return _ok(id, <String, Object?>{'tools': _tools});
      case 'tools/call':
        return _ok(id, await _call(request['params']));
      default:
        return <String, Object?>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, Object?>{
            'code': -32601,
            'message': 'Method not found: $method',
          },
        };
    }
  }

  /// Reads newline-delimited JSON-RPC from [input] and writes responses to
  /// [output], which is how an MCP client speaks to a stdio server.
  Future<void> serve({Stream<List<int>>? input, IOSink? output}) async {
    final Stream<String> lines = (input ?? stdin)
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final IOSink sink = output ?? stdout;

    await for (final String line in lines) {
      if (line.trim().isEmpty) continue;
      Map<String, Object?>? response;
      try {
        final Object? decoded = jsonDecode(line);
        if (decoded is! Map<String, Object?>) continue;
        response = await handle(decoded);
      } on FormatException catch (error) {
        response = <String, Object?>{
          'jsonrpc': '2.0',
          'id': null,
          'error': <String, Object?>{
            'code': -32700,
            'message': 'Parse error: $error',
          },
        };
      }
      if (response != null) sink.writeln(jsonEncode(response));
    }
  }

  static Map<String, Object?> _ok(Object? id, Map<String, Object?> result) =>
      <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result};

  static const Map<String, Object?> _noArguments = <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{},
  };

  static final List<Map<String, Object?>> _tools = <Map<String, Object?>>[
    <String, Object?>{
      'name': '${_prefix}inspect_graph',
      'description':
          'The whole project graph as JSON: routes, models, backend functions '
              'and jobs, each with the source it was derived from.',
      'inputSchema': _noArguments,
    },
    <String, Object?>{
      'name': '${_prefix}inspect_routes',
      'description': 'Every page route and the page that answers it.',
      'inputSchema': _noArguments,
    },
    <String, Object?>{
      'name': '${_prefix}inspect_models',
      'description': 'Every model and how many fields it declares.',
      'inputSchema': _noArguments,
    },
    <String, Object?>{
      'name': '${_prefix}inspect_model',
      'description':
          'One model with its fields and types. A sensitive field is named and '
              'marked, and never carries a value.',
      'inputSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'name': <String, Object?>{
            'type': 'string',
            'description': 'The generated model name, such as User.',
          },
        },
        'required': <String>['name'],
      },
    },
    <String, Object?>{
      'name': '${_prefix}inspect_functions',
      'description':
          'Every backend function the application serves. These are '
              'file-based, so a file under backend/functions is an endpoint '
              'whether or not it carries @DVBackendFunction.',
      'inputSchema': _noArguments,
    },
    <String, Object?>{
      'name': '${_prefix}inspect_jobs',
      'description': 'Every durable job and the queue it runs on.',
      'inputSchema': _noArguments,
    },
  ];

  Future<Map<String, Object?>> _call(Object? params) async {
    final Map<String, Object?> args = params is Map<String, Object?>
        ? params
        : const <String, Object?>{};
    final String name = (args['name'] ?? '') as String;
    final Map<String, Object?> arguments =
        args['arguments'] is Map<String, Object?>
            ? args['arguments']! as Map<String, Object?>
            : const <String, Object?>{};

    final DartvelProjectGraph graph = await _graph();
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');

    switch (name) {
      case '${_prefix}inspect_graph':
        return _text(encoder.convert(graph.toJson()));
      case '${_prefix}inspect_routes':
        return _text(encoder
            .convert(graph.routes.map((DVGraphRoute r) => r.toJson()).toList()));
      case '${_prefix}inspect_models':
        return _text(encoder.convert(
            graph.models.map((DVGraphModel m) => m.toJson()).toList()));
      case '${_prefix}inspect_functions':
        return _text(encoder.convert(
            graph.functions.map((DVGraphFunction f) => f.toJson()).toList()));
      case '${_prefix}inspect_jobs':
        return _text(
            encoder.convert(graph.jobs.map((DVGraphJob j) => j.toJson()).toList()));
      case '${_prefix}inspect_model':
        final String wanted = (arguments['name'] ?? '') as String;
        final Iterable<DVGraphModel> found =
            graph.models.where((DVGraphModel m) => m.name == wanted);
        if (found.isEmpty) {
          return _text(
            'Model "$wanted" not found. Known models: '
            '${graph.models.isEmpty ? '(none)' : graph.models.map((DVGraphModel m) => m.name).join(', ')}',
            isError: true,
          );
        }
        return _text(encoder.convert(found.first.toJson()));
      default:
        // A tool error belongs in the result so the agent can read and correct
        // it, rather than as a transport error that ends the session.
        return _text('Unknown tool "$name".', isError: true);
    }
  }

  static Map<String, Object?> _text(String text, {bool isError = false}) =>
      <String, Object?>{
        'content': <Map<String, Object?>>[
          <String, Object?>{'type': 'text', 'text': text},
        ],
        if (isError) 'isError': true,
      };

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
