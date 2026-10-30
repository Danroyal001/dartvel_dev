// A tool parameter with a default is optional, and the default applies.
//
// The generator dropped a parameter's default when it read the signature, so
// the handler always passed something: a non-nullable parameter with a
// default was refused as missing, and the schema told the model it was
// required; a nullable one with a default was handed null, so the function
// ran with null where its author had written 10 -- a wrong value with no
// error anywhere. A default that is a literal is now carried into the
// handler. One that names something (a constant, a call) cannot be copied
// out of its file, so it stays required, and the schema says so.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:defaults_app/dartvel_client/ai_tools.g.dart';

Future<void> main() async {
  registerDartvelAITools();
  const registry = DVAIToolRegistry();
  Future<Object?> call(String name, Map<String, Object?> args) async {
    try {
      return DVJsonCodec.toJson(
          await registry.call(name, DVJsonCodec.fromJsonObject(args)));
    } on ArgumentError catch (e) {
      return 'refused ${e.name}';
    }
  }

  final Map<String, Object?> out = <String, Object?>{
    for (final String name in registry.names)
      '$name.required': registry.definition(name)!.jsonSchema['required'],
    'positional': await call('search', <String, Object?>{'query': 'tea'}),
    'positionalGiven':
        await call('search', <String, Object?>{'query': 'tea', 'limit': 3}),
    'named': await call('browse', <String, Object?>{'query': 'tea'}),
    'nonLiteral': await call('page', <String, Object?>{}),
  };
  print('PROBE ${jsonEncode(out)}');
}
''';

void main() {
  late Map<String, Object?> r;

  setUpAll(() async {
    final Directory project =
        await Directory.systemTemp.createTemp('dartvel_ai_tool_defaults_');
    addTearDown(() => project.deleteSync(recursive: true));
    final String packages = p.normalize(p.join(Directory.current.path, '..'));
    void write(String path, String text) {
      File(p.join(project.path, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    }

    write('pubspec.yaml', '''
name: defaults_app
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
''');
    write('lib/backend/functions/catalog.dart', r'''
import 'package:dartvel_core/dartvel.dart';

const int firstPage = 1;

@DVAITool(description: 'Search')
Future<String> search(String query, [int limit = 10]) async =>
    '$query:$limit';

@DVAITool(description: 'Browse')
Future<String> browse({
  required String query,
  int? limit = 5,
  String sort = 'recent',
  bool fuzzy = true,
  double boost = -1.5,
}) async =>
    '$query:$limit:$sort:$fuzzy:$boost';

@DVAITool(description: 'Page')
Future<String> page({int number = firstPage}) async => 'page $number';
''');
    write('bin/probe.dart', _probe);
    Directory(p.join(project.path, '.dart_tool')).createSync();

    await BackendGenerator.generate(
      root: project.path,
      backendDir: 'lib/backend',
      pkgName: 'defaults_app',
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

  test('a positional parameter with a default may be left out', () {
    expect(r['search.required'], <String>['query']);
    expect(r['positional'], 'tea:10');
    expect(r['positionalGiven'], 'tea:3');
  });

  test('named defaults apply, a nullable one included', () {
    expect(r['browse.required'], <String>['query']);
    expect(r['named'], 'tea:5:recent:true:-1.5');
  });

  test('a default that names something stays required', () {
    expect(r['page.required'], <String>['number']);
    expect(r['nonLiteral'], 'refused number');
  });
}
