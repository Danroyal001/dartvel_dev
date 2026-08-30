// A block-bodied private @DVBackendFunction, generated end to end.
//
// The last of the three annotations that refused a block body. The backend
// extractor was stricter than the others: its regex matched a single line, so
// even an expression body had to fit on one.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> generateRoutesFor(String functionSource) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_backend_block_');
  addTearDown(() => root.deleteSync(recursive: true));

  Directory(p.join(root.path, '.dart_tool')).createSync();
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'backend', 'functions'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'backend', 'functions', 'task.post.dart'))
      .writeAsStringSync(functionSource);

  await BackendGenerator.generate(
    root: root.path,
    backendDir: 'lib/backend',
    pkgName: 'backend_block_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    apiBasePath: '/api',
  );

  return File(
    p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
  ).readAsStringSync();
}

const String _imports = "import 'package:dartvel_core/dartvel.dart';\n";

void main() {
  test('a block body reaches the generated route', () async {
    final String routes = await generateRoutesFor('$_imports'
        '@DVBackendFunction()\n'
        'Future<String> _handler(String input) async {\n'
        '  final String trimmed = input.trim();\n'
        '  return trimmed.toUpperCase();\n'
        '}\n');

    expect(routes, contains('final String trimmed = input.trim();'));
    expect(routes, contains('return trimmed.toUpperCase();'));
    // Never a call back into the private input.
    expect(routes, isNot(contains('f0._handler(')));
  });

  test('async survives, or the route returns a value instead of a Future',
      () async {
    final String routes = await generateRoutesFor('$_imports'
        '@DVBackendFunction()\n'
        'Future<int> _handler(int value) async {\n'
        '  await Future<void>.delayed(Duration.zero);\n'
        '  return value * 2;\n'
        '}\n');

    expect(routes, contains('async'));
    expect(routes, contains('await Future<void>.delayed(Duration.zero);'));
  });

  test('a loop and a conditional survive', () async {
    final String routes = await generateRoutesFor('$_imports'
        '@DVBackendFunction()\n'
        'Future<int> _handler(int count) async {\n'
        '  int total = 0;\n'
        '  for (int i = 0; i < count; i++) {\n'
        '    total += i;\n'
        '  }\n'
        '  if (total == 0) {\n'
        '    return -1;\n'
        '  }\n'
        '  return total;\n'
        '}\n');

    expect(routes, contains('for (int i = 0; i < count; i++)'));
    expect(routes, contains('if (total == 0)'));
    expect(routes, contains('return total;'));
  });

  test('a symbol left in the source file is reached through its import',
      () async {
    final String routes = await generateRoutesFor('$_imports'
        '@DVBackendFunction()\n'
        'Future<String> _handler(String input) async {\n'
        '  return decorate(input);\n'
        '}\n'
        "String decorate(String value) => 'ok \$value';\n");

    expect(routes, contains('f0.decorate(input)'));
  });

  test('a multi-line expression body works', () async {
    // The old extractor matched one line, so this was refused even though it
    // is an expression body.
    final String routes = await generateRoutesFor('$_imports'
        '@DVBackendFunction()\n'
        'Future<String> _handler(String input) async =>\n'
        '    input\n'
        '        .trim()\n'
        '        .toUpperCase();\n');

    expect(routes, contains('.toUpperCase()'));
  });

  test('a single-line expression body still works', () async {
    final String routes = await generateRoutesFor('$_imports'
        '@DVBackendFunction()\n'
        "Future<String> _handler(String input) async => input.trim();\n");

    expect(routes, contains('input.trim()'));
  });

  test('async is kept on an expression body whose value is not a Future', () {
    // The old extractor matched `(?:async\s*)?=>` and threw the modifier away.
    // It went unnoticed because the bodies it was used on already returned a
    // Future; a plain value does not, and the generated helper stops
    // compiling.
    return generateRoutesFor("$_imports"
            '@DVBackendFunction()\n'
            "Future<String> _handler(String input) async => 'ok';\n")
        .then((String routes) {
      expect(routes, contains("async => 'ok'"));
    });
  });
}
