import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/generate_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late String originalCwd;

  setUp(() {
    originalCwd = Directory.current.path;
  });

  tearDown(() {
    Directory.current = originalCwd;
  });

  test('page template uses DVPage without redundant public functional widget',
      () async {
    final root =
        await Directory.systemTemp.createTemp('dartvel_generate_page_');
    try {
      Directory.current = root.path;
      await _runGenerate(<String>['generate', 'page', 'dashboard']);

      final source = File(
        p.join(root.path, 'lib', 'pages', 'dashboard.dart'),
      ).readAsStringSync();

      expect(source, contains('@DVPage()'));
      expect(source, isNot(contains('@DVFunctionalWidget()')));
      expect(source, contains('Widget dashboardPage(BuildContext context)'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('backend function template remains executable by current generator',
      () async {
    final root =
        await Directory.systemTemp.createTemp('dartvel_generate_backend_');
    try {
      Directory.current = root.path;
      await _runGenerate(<String>['generate', 'backend-function', 'echo']);

      final source = File(
        p.join(root.path, 'lib', 'backend', 'functions', 'echo.dart'),
      ).readAsStringSync();

      expect(source, contains('@DVBackendFunction()'));
      expect(source, contains('Future<String> getEcho(String input) async'));
      expect(source, isNot(contains('Future<String> _getEcho(')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}

Future<void> _runGenerate(List<String> args) {
  return (CommandRunner<void>('dartvel', 'test')..addCommand(GenerateCommand()))
      .run(args);
}
