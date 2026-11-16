// WebMCP from @DVAITool: in a browser that offers agents a page's tools
// (document.modelContext, a W3C Web Machine Learning Community Group draft),
// a Dartvel web app registers each backend function marked as an AI tool.
//
// The tool calls the same generated client function the app's own code
// calls, so the function's route -- its policy, CSRF and rate limits -- is
// the only way in, exactly as for a person pressing a button. Nothing new is
// exposed: a hidden function stays hidden, a function that is not a tool is
// not registered.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> _webMcpFor(String functions) async {
  final Directory root = await Directory.systemTemp.createTemp('dartvel_web_mcp_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: web_mcp_app\n');
  Directory(p.join(root.path, '.dart_tool')).createSync();
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'backend', 'functions')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'backend', 'functions', 'catalog.dart')).writeAsStringSync(functions);
  await BackendGenerator.generate(
    root: root.path,
    backendDir: 'lib/backend',
    pkgName: 'web_mcp_app',
    buildId: 'test',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    apiBasePath: '/api',
  );
  final File file = File(p.join(root.path, 'lib', 'dartvel_client', 'web_mcp.g.dart'));
  expect(file.existsSync(), isTrue, reason: 'written for every project, empty or not');
  return file.readAsStringSync();
}

void main() {
  test('each AI-tool backend function is a WebMCP tool calling its client function', () async {
    final String out = await _webMcpFor('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(aiTool: DVAITool(description: 'Find products by name'))
Future<List<String>> _findProducts(String query, int limit) async => <String>[];

@DVAIHidden()
@DVBackendFunction(aiTool: DVAITool(description: 'Hidden'))
Future<String> _rotateSecret() async => 'hidden';

@DVBackendFunction()
Future<String> _notATool() async => 'plain';
''');
    expect(out, contains("import 'functions.g.dart' as client;"));
    expect(out, contains('void registerDartvelWebMcpTools()'));
    expect(out, contains("name: 'findProducts'"));
    expect(out, contains("description: 'Find products by name'"));
    expect(out, contains("'query': <String, Object?>{'type': 'string'}"));
    expect(out, contains("'limit': <String, Object?>{'type': 'integer'}"));
    expect(out, contains("'required': <String>['query', 'limit']"));
    // The client function the app calls, with named arguments as it takes them.
    expect(out, contains("client.findProducts(query: _dvWebToolArg(input, 'query', 'String') as String, "
        "limit: _dvWebToolArg(input, 'limit', 'int') as int)"));
    expect(out, isNot(contains('rotateSecret')), reason: '@DVAIHidden wins');
    expect(out, isNot(contains('notATool')), reason: 'not an AI tool');
  });

  test('a project with no AI tools registers none, and says so', () async {
    final String out = await _webMcpFor('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _hello() async => 'hi';
''');
    expect(out, contains('void registerDartvelWebMcpTools() {}'));
    expect(out, isNot(contains('DVWebMcpTool(')));
  });

  test('the web runtime registers them as it registers the browser bindings', () async {
    final Directory root = await Directory.systemTemp.createTemp('dartvel_web_mcp_runtime_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
    File(p.join(root.path, 'lib', 'pages', 'index.dart')).writeAsStringSync('''
import 'package:flutter/widgets.dart';
import '../dartvel_client/dartvel_client.dart';
@DVPage()
Widget _indexPage(BuildContext context) => const DVText('Home');
''');
    await ClientGenerator.generate(
      root: root.path, pagesDir: 'lib/pages', pkgName: 'web_mcp_app', buildId: 'test',
      backendHost: '127.0.0.1', backendPort: 3000, devBackendHost: 'http://localhost:3000',
      prodBackendHost: 'https://api.example.test', apiBasePath: '/api', envFiles: const <String>[],
      seoSiteName: 'A', seoTitle: 'A', seoDesc: 'A', seoImage: '', seoTwitter: '',
      defaultTransition: 'fade', durationMs: 200, curve: 'easeInOut', normalizeTrailing: true,
      notFoundRedirect: '', plugins: const <String>[], ota: false, dv: YamlMap.wrap(<String, Object?>{}),
    );
    final String runtime =
        File(p.join(root.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart')).readAsStringSync();
    expect(runtime, contains("import 'web_mcp.g.dart' show registerDartvelWebMcpTools;"));
    final int web = runtime.indexOf('DVWebBindings.register();');
    expect(web, isNot(-1));
    expect(runtime.indexOf('registerDartvelWebMcpTools();', web), greaterThan(web));
  });
}
