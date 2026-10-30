// The schema a provider is given says which arguments a tool needs.
//
// It listed a type per property and no `required`, which in JSON Schema means
// every property is optional. A model told that is free to leave out an
// argument the generated handler then refuses -- so the call fails at run
// time on something the schema could have said up front. The handler refuses
// exactly a missing non-nullable argument, so that is what `required` lists.
//
// This compiles and runs the generated registration rather than reading the
// emitted source, because what matters is the schema the registry hands a
// provider, not the shape of the file that builds it.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:schema_app/dartvel_client/ai_tools.g.dart';

Future<void> main() async {
  registerDartvelAITools();
  const registry = DVAIToolRegistry();
  final Map<String, Object?> out = <String, Object?>{};
  for (final DVAIToolDefinition tool
      in registry.definitions(<String>['findProducts', 'listAll'])) {
    out[tool.name] = tool.jsonSchema;
  }
  // Called the way the schema says it may be: with only what is required.
  final DVJsonValue answer = await registry.call(
    'findProducts',
    DVJsonCodec.fromJsonObject(<String, Object?>{'query': 'tea', 'inStock': true}),
  );
  out['answer'] = DVJsonCodec.toJson(answer);
  // And refused when a required argument is missing.
  try {
    await registry.call(
      'findProducts',
      DVJsonCodec.fromJsonObject(<String, Object?>{'inStock': true}),
    );
    out['missing'] = 'accepted';
  } on ArgumentError catch (e) {
    out['missing'] = e.name;
  }
  print('PROBE ${jsonEncode(out)}');
}
''';

void main() {
  late Map<String, Object?> r;

  setUpAll(() async {
    final Directory project =
        await Directory.systemTemp.createTemp('dartvel_ai_tool_required_');
    addTearDown(() => project.deleteSync(recursive: true));
    final String packages = p.normalize(p.join(Directory.current.path, '..'));
    void write(String path, String text) {
      File(p.join(project.path, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    }

    write('pubspec.yaml', '''
name: schema_app
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
''');
    write('lib/backend/functions/catalog.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVAITool(description: 'Find products')
Future<String> findProducts(String query, int? limit, bool inStock) async =>
    '\$query:\${limit ?? 'all'}:\$inStock';

@DVAITool(description: 'List everything')
Future<String> listAll() async => 'all';
''');
    write('bin/probe.dart', _probe);
    Directory(p.join(project.path, '.dart_tool')).createSync();

    await BackendGenerator.generate(
      root: project.path,
      backendDir: 'lib/backend',
      pkgName: 'schema_app',
      buildId: 'test-build',
      backendHost: '127.0.0.1',
      backendPort: 3000,
      apiBasePath: '/api',
    );

    final ProcessResult resolved = await Process.run(
      Platform.resolvedExecutable,
      <String>['pub', 'get', '--offline'],
      workingDirectory: project.path,
    );
    if (resolved.exitCode != 0) {
      throw StateError('dart pub get failed:\n${resolved.stderr}');
    }
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
    ).timeout(const Duration(minutes: 4));
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run (exit ${result.exitCode}):\n'
          '${result.stdout}\n${result.stderr}');
    }
    r = jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
  });

  test('required lists the arguments the handler refuses to go without', () {
    final Map<String, Object?> schema =
        r['findProducts']! as Map<String, Object?>;
    expect(schema['type'], 'object');
    expect(schema['required'], <String>['query', 'inStock']);
  });

  test('a nullable argument is not required, and may be left out', () {
    expect(r['answer'], 'tea:all:true');
  });

  test('a required argument left out is refused by name', () {
    expect(r['missing'], 'query');
  });

  test('a tool with no parameters requires nothing', () {
    final Map<String, Object?> schema = r['listAll']! as Map<String, Object?>;
    expect(schema['required'], isNull);
  });
}
