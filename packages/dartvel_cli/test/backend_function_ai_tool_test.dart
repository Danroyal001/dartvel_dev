import 'dart:io';
import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// @DVBackendFunction(aiTool: ...) adds the function to the same AI tool
/// registry @DVAITool does, with its description, even with
/// parentheses inside the description.
void main() {
  test('@DVBackendFunction(aiTool:) generates AI tool entry', () async {
    final root = await Directory.systemTemp.createTemp('track_c_1_');
    try {
      // No `exposeBackendFunctionsAsTools`: aiTool alone must make it a tool.
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: track_c_1_app\n');
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);

      File(p.join(root.path, 'lib', 'backend', 'functions', 'catalog.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(
  aiTool: DVAITool(description: 'Look up a product (by id)'),
)
Future<String> _getProduct(String id) async => 'product-\$id';

@DVAIHidden()
@DVBackendFunction(aiTool: DVAITool(description: "Hidden (even though it says aiTool)"))
Future<String> _rotateSecret() async => 'hidden';

@DVBackendFunction()
Future<String> _notATool() async => 'plain';
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'track_c_1_app',
        buildId: 'test',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final aiToolsFile = File(
        p.join(root.path, 'lib', 'dartvel_client', 'ai_tools.g.dart'),
      );
      expect(aiToolsFile.existsSync(), isTrue);
      final content = aiToolsFile.readAsStringSync();
      // The function declared via aiTool must appear in the AI tools list.
      expect(content, contains('getProduct'));
      expect(content, contains('Look up a product (by id)'));
      expect(content, isNot(contains('rotateSecret')), reason: '@DVAIHidden wins');
      expect(content, isNot(contains('notATool')), reason: 'no aiTool and no global opt-in');
    } finally {
      if (root.existsSync()) root.deleteSync(recursive: true);
    }
  });
}
