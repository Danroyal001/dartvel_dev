// `dartvel mcp` serves Dartvel's own tools -- the inspectors over the project
// graph -- to a coding agent working on the application.
//
// The registry separation the spec calls load-bearing is why this lives in the
// CLI and answers from the graph: an agent building the app must not be
// reachable through the same surface the app serves to its users, because one
// of them can read the project's schema.
import 'dart:io';

import 'package:dartvel_cli/src/mcp/framework_mcp_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _models = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  final String email;

  @DVModel.sensitiveField()
  final String taxId;

  const _User({required this.email, required this.taxId});
}
''';

Directory projectWith(Map<String, String> files) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_mcp_');
  addTearDown(() => root.deleteSync(recursive: true));
  for (final MapEntry<String, String> entry in files.entries) {
    final File file = File(p.join(root.path, entry.key));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: mcp_app\n');
  return root;
}

DartvelFrameworkMcpServer serverFor(Directory root) =>
    DartvelFrameworkMcpServer(root: root.path);

void main() {
  group('protocol', () {
    test('initialize answers with a protocol version and server identity',
        () async {
      final Map<String, Object?>? response = await serverFor(projectWith({}))
          .handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, Object?>{'protocolVersion': '2024-11-05'},
      });

      expect(response!['jsonrpc'], '2.0');
      expect(response['id'], 1);
      final Map<String, Object?> result =
          response['result']! as Map<String, Object?>;
      expect(result['protocolVersion'], isNotNull);
      expect(
        (result['serverInfo']! as Map<String, Object?>)['name'],
        contains('dartvel'),
      );
    });

    test('a notification gets no response, as JSON-RPC requires', () async {
      // A response to a request with no id is a protocol violation, and some
      // clients close the connection on it.
      final Map<String, Object?>? response = await serverFor(projectWith({}))
          .handle(<String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      });

      expect(response, isNull);
    });

    test('an unknown method is method-not-found, not a crash', () async {
      final Map<String, Object?>? response = await serverFor(projectWith({}))
          .handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 7,
        'method': 'does/notExist',
      });

      expect((response!['error']! as Map<String, Object?>)['code'], -32601);
    });
  });

  group('tools', () {
    test('every tool declares an input schema', () async {
      // A tool without one is unusable by an agent that validates arguments.
      final Map<String, Object?>? response = await serverFor(projectWith({}))
          .handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
      });

      final List<Object?> tools =
          (response!['result']! as Map<String, Object?>)['tools']! as List<Object?>;
      expect(tools, isNotEmpty);
      for (final Object? tool in tools) {
        final Map<String, Object?> entry = tool! as Map<String, Object?>;
        expect(entry['name'], isA<String>());
        expect(entry['description'], isA<String>());
        expect(entry['inputSchema'], isA<Map<String, Object?>>());
      }
    });

    test('tool names are framework-scoped', () async {
      // The separation is load-bearing: these must never read as application
      // tools.
      final Map<String, Object?>? response = await serverFor(projectWith({}))
          .handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/list',
      });

      final List<Object?> tools =
          (response!['result']! as Map<String, Object?>)['tools']! as List<Object?>;
      for (final Object? tool in tools) {
        expect((tool! as Map<String, Object?>)['name'], startsWith('dartvel_'));
      }
    });

    test('inspecting a model describes a sensitive field but never values it',
        () async {
      final Map<String, Object?>? response =
          await serverFor(projectWith(<String, String>{
        'lib/models/user.dart': _models,
      })).handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'dartvel_inspect_model',
          'arguments': <String, Object?>{'name': 'User'},
        },
      });

      final Map<String, Object?> result =
          response!['result']! as Map<String, Object?>;
      final String text = ((result['content']! as List<Object?>).first!
          as Map<String, Object?>)['text']! as String;

      expect(text, contains('taxId'));
      expect(text, contains('sensitive'));
      expect(result['isError'], isNot(true));
    });

    test('an unknown tool is an error result, not a thrown exception', () async {
      final Map<String, Object?>? response = await serverFor(projectWith({}))
          .handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 5,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'dartvel_not_a_tool',
          'arguments': <String, Object?>{},
        },
      });

      // A tool error belongs in the result so the agent can read it, rather
      // than as a transport error that ends the session.
      expect(response!['result'], isNotNull);
      expect((response['result']! as Map<String, Object?>)['isError'], isTrue);
    });
  });
}
