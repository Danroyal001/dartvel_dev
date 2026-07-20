import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('backend generator emits explicit AI tool metadata', () async {
    final root = await Directory.systemTemp.createTemp('dartvel_ai_tool_test_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      final functionsDir =
          Directory(p.join(root.path, 'lib', 'backend', 'functions'))
            ..createSync(recursive: true);

      File(p.join(functionsDir.path, 'tools.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVAITool(description: 'Add two ledger amounts.')
@DVBackendFunction(method: 'post', path: '/ledger/sum')
Future<int> sumLedgerAmounts(int left, int right) async => left + right;

@DVBackendFunction(method: 'post', path: '/ledger/private')
Future<int> internalLedgerAdjustment(int amount) async => amount;

@DVAITool()
Future<String> describeLedger() async => 'ledger';
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'ai_tool_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final tools = File(
        p.join(root.path, 'lib', 'dartvel_client', 'ai_tools.g.dart'),
      );
      expect(tools.existsSync(), isTrue);
      final content = tools.readAsStringSync();
      expect(content, contains('library dartvel_client_ai_tools'));
      expect(content, contains('const List<DVAIToolEntry> dartvelAITools'));
      expect(content, contains('sumLedgerAmounts'));
      expect(content, contains('Add two ledger amounts.'));
      expect(content, contains('describeLedger'));
      expect(content, contains("description: ''"));
      expect(content,
          contains('package:ai_tool_app/backend/functions/tools.dart'));
      expect(content, isNot(contains('internalLedgerAdjustment')));
    } finally {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    }
  });

  test('backend generator can expose backend functions with opt-out', () async {
    final root =
        await Directory.systemTemp.createTemp('dartvel_ai_backend_tool_test_');
    try {
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: ai_backend_tool_app
dartvel:
  ai:
    exposeBackendFunctionsAsTools: true
''');
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      final functionsDir =
          Directory(p.join(root.path, 'lib', 'backend', 'functions'))
            ..createSync(recursive: true);

      File(p.join(functionsDir.path, 'ledger.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(method: 'post', path: '/ledger/reconcile')
Future<String> reconcileLedger() async => 'ok';

@DVAIHidden()
@DVBackendFunction(method: 'post', path: '/ledger/secret')
Future<String> rotateLedgerSecret() async => 'hidden';
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'ai_backend_tool_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final content = File(
        p.join(root.path, 'lib', 'dartvel_client', 'ai_tools.g.dart'),
      ).readAsStringSync();
      expect(content, contains('reconcileLedger'));
      expect(content, contains('Backend function reconcileLedger'));
      expect(content, isNot(contains('rotateLedgerSecret')));
    } finally {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    }
  });
}
