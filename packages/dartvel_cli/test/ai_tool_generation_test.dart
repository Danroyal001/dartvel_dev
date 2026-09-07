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

  test('a declared AI tool is registered with a handler that calls it',
      () async {
    // The generated list carried a name, a description and a file path and
    // nothing else, which is a catalogue rather than a set of tools: an
    // assistant could read that a function existed and had no way to run it.
    final root = await Directory.systemTemp.createTemp('dartvel_aitool_run_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);

      File(p.join(root.path, 'lib', 'backend', 'functions', 'weather.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVAITool(description: 'Current temperature for a city')
Future<num> temperature(String city, int days) async => 21;
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'aitool_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final tools = File(
        p.join(root.path, 'lib', 'dartvel_client', 'ai_tools.g.dart'),
      ).readAsStringSync();

      // Registered, with a handler that calls the function.
      expect(tools, contains('void registerDartvelAITools()'));
      expect(tools, contains("registry.register('temperature'"));
      expect(tools, contains('.temperature('));
      // A schema, because every provider requires one on each tool, and the
      // types have to survive the trip: an int advertised as a string is a
      // tool a model will call wrongly.
      expect(tools, contains("'city'"));
      expect(tools, contains("DVJsonString('string')"));
      expect(tools, contains("DVJsonString('integer')"));
      // Refused by name rather than coerced. A tool that quietly received 0
      // for a number it could not read would run and be wrong.
      expect(tools, contains('_dvToolArg('));
      expect(tools, contains('is required by this tool'));

      // And something has to call the registration, or it is a function in a
      // generated file nobody imports.
      final routes = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();
      expect(routes, contains('registerDartvelAITools()'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('an application with no tools still defines the registration',
      () async {
    // The generated backend calls it unconditionally, so an application with
    // no @DVAITool inputs would otherwise generate a server that does not
    // compile.
    final root = await Directory.systemTemp.createTemp('dartvel_aitool_none_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'no_tools_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final tools = File(
        p.join(root.path, 'lib', 'dartvel_client', 'ai_tools.g.dart'),
      ).readAsStringSync();
      expect(tools, contains('void registerDartvelAITools()'));
      expect(tools, isNot(contains('registry.register(')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a private declaration is listed and not registered', () async {
    // Backend function inputs are private by the spec, and the catalogue
    // lists one under the public name the generated client exposes. There is
    // no public symbol in the source file to call, so a handler written
    // against that name would be generated code that does not compile.
    final root = await Directory.systemTemp.createTemp('dartvel_aitool_priv_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: priv_tools_app
dartvel:
  ai:
    exposeBackendFunctionsAsTools: true
''');
      File(p.join(root.path, 'lib', 'backend', 'functions', 'pay.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<Map<String, bool>> _pay(String orderId) async => <String, bool>{'ok': true};
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'priv_tools_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final tools = File(
        p.join(root.path, 'lib', 'dartvel_client', 'ai_tools.g.dart'),
      ).readAsStringSync();

      expect(tools, contains("name: 'pay'"));
      expect(tools, isNot(contains("registry.register('pay'")));
      expect(tools, contains('private to its own file'));
      // And no import for a file nothing calls into, or the generated file
      // carries a warning nobody can act on.
      expect(tools, isNot(contains("as tool0")));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a tool that returns nothing still compiles', () async {
    // await on a void or Future<void> function produces void, and assigning
    // that does not compile. A tool that sends an email and returns nothing
    // is an ordinary tool, and a handler that assigned its result would be a
    // server that will not build -- found by reading the emitted code rather
    // than by a compiler, because nothing here compiles generated output.
    final root = await Directory.systemTemp.createTemp('dartvel_aitool_void_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);

      File(p.join(root.path, 'lib', 'backend', 'functions', 'notify.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVAITool(description: 'Tell the owner')
Future<void> notifyOwner(String message) async {}
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'void_tool_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final tools = File(
        p.join(root.path, 'lib', 'dartvel_client', 'ai_tools.g.dart'),
      ).readAsStringSync();

      expect(tools, contains('.notifyOwner('));
      expect(tools, contains('const DVJsonNull()'));
      expect(tools, isNot(contains('final result = await')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
