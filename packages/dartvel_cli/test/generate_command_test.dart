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

  test('page template uses a private expression-bodied DVPage input', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartvel_generate_page_',
    );
    try {
      Directory.current = root.path;
      await _runGenerate(<String>['generate', 'page', 'dashboard']);

      final source = File(
        p.join(root.path, 'lib', 'pages', 'dashboard.dart'),
      ).readAsStringSync();

      expect(source, contains('@DVPage()'));
      expect(source, contains("@pragma('vm:entry-point')"));
      expect(source, isNot(contains('@DVFunctionalWidget()')));
      expect(
        source,
        contains('Widget _dashboardPage(BuildContext context) =>'),
      );
      expect(source, isNot(contains('Widget dashboardPage(')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test(
    'model template emits a private schema input without lint warnings',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartvel_generate_model_',
      );
      try {
        Directory.current = root.path;
        await _runGenerate(<String>['generate', 'model', 'account']);

        final source = File(
          p.join(root.path, 'lib', 'models', 'account.dart'),
        ).readAsStringSync();

        expect(source, isNot(contains('// ignore_for_file: unused_element')));
        expect(source, contains('@DVModel()'));
        expect(source, contains("@pragma('vm:entry-point')"));
        expect(source, contains('class _Account'));
        expect(source, isNot(contains('class Account')));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'backend function template emits a private expression-bodied input',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartvel_generate_backend_',
      );
      try {
        Directory.current = root.path;
        await _runGenerate(<String>['generate', 'backend-function', 'echo']);

        final source = File(
          p.join(root.path, 'lib', 'backend', 'functions', 'echo.dart'),
        ).readAsStringSync();

        expect(source, contains('@DVBackendFunction()'));
        expect(source, contains("@pragma('vm:entry-point')"));
        expect(
          source,
          contains(
            "Future<String> _getEcho(String input) async => 'Echo: \$input';",
          ),
        );
        expect(source, isNot(contains('Future<String> getEcho(')));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );
}

Future<void> _runGenerate(List<String> args) {
  return (CommandRunner<void>(
    'dartvel',
    'test',
  )..addCommand(GenerateCommand()))
      .run(args);
}
