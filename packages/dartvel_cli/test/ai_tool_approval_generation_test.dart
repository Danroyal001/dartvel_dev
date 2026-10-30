// @DVAITool(approval: DVToolApproval.required) reaches the registry.
//
// The approval is the whole point of declaring it on the tool: if the
// generator read the description and dropped the approval, the tool would be
// registered as one that runs on a model's word, and nothing would say so.
// So this runs the generated registration and asks the registry.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:approval_app/dartvel_client/ai_tools.g.dart';

Future<void> main() async {
  registerDartvelAITools();
  const registry = DVAIToolRegistry();
  final Map<String, Object?> out = <String, Object?>{};
  for (final String name in registry.names) {
    String called;
    try {
      await registry.call(name, DVJsonCodec.fromJsonObject(
          <String, Object?>{'amount': 1, 'orderId': 'o1'}));
      called = 'ran';
    } on DVAIToolApprovalRequired catch (e) {
      called = e.code;
    }
    out[name] = <String, Object?>{
      'approval': registry.definition(name)!.approval.name,
      'called': called,
    };
  }
  print('PROBE ${jsonEncode(out)}');
}
''';

Future<Directory> _project(String tools, {String? functions}) async {
  final Directory project =
      await Directory.systemTemp.createTemp('dartvel_ai_tool_approval_');
  final String packages = p.normalize(p.join(Directory.current.path, '..'));
  void write(String path, String text) {
    File(p.join(project.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  write('pubspec.yaml', '''
name: approval_app
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
''');
  write('lib/backend/functions/tools.dart', tools);
  if (functions != null) write('lib/backend/functions/refunds.post.dart', functions);
  write('bin/probe.dart', _probe);
  Directory(p.join(project.path, '.dart_tool')).createSync();
  return project;
}

Future<void> _generate(Directory project) => BackendGenerator.generate(
      root: project.path,
      backendDir: 'lib/backend',
      pkgName: 'approval_app',
      buildId: 'test-build',
      backendHost: '127.0.0.1',
      backendPort: 3000,
      apiBasePath: '/api',
    );

void main() {
  late Map<String, Object?> r;

  setUpAll(() async {
    final Directory project = await _project('''
import 'package:dartvel_core/dartvel.dart';

@DVAITool(description: 'Issue a refund (once)', approval: DVToolApproval.required)
Future<String> issueRefund(int amount) async => 'refunded';

@DVAITool(approval: .required, description: 'Cancel an order')
Future<String> cancelOrder(String orderId) async => 'cancelled';

@DVAITool(description: 'Look up an order', approval: DVToolApproval.none)
Future<String> lookupOrder(String orderId) async => 'order';

@DVAITool(description: 'Count orders')
Future<int> countOrders() async => 3;
''', functions: '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(
  aiTool: DVAITool(description: 'Void an invoice', approval: DVToolApproval.required),
)
Future<String> voidInvoice(String orderId) async => 'void';
''');
    addTearDown(() => project.deleteSync(recursive: true));
    await _generate(project);

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

  test('a tool declared as needing approval is registered as one', () {
    expect(r['issueRefund'],
        <String, Object?>{'approval': 'required', 'called': 'DV-AI-010'});
  });

  test('either argument order, and the dot shorthand, read the same', () {
    expect(r['cancelOrder'],
        <String, Object?>{'approval': 'required', 'called': 'DV-AI-010'});
  });

  test('a backend function exposed as a tool carries its approval', () {
    expect(r['voidInvoice'],
        <String, Object?>{'approval': 'required', 'called': 'DV-AI-010'});
  });

  test('a tool that needs none still runs', () {
    expect(r['lookupOrder'],
        <String, Object?>{'approval': 'none', 'called': 'ran'});
    expect(r['countOrders'],
        <String, Object?>{'approval': 'none', 'called': 'ran'});
  });

  test('an approval the generator cannot read stops the build', () async {
    // Dropping it would register a tool that runs on a model's word, and
    // dropping the tool would leave the author wondering where it went.
    final Directory project = await _project('''
import 'package:dartvel_core/dartvel.dart';

const DVToolApproval needsApproval = DVToolApproval.required;

@DVAITool(description: 'Issue a refund', approval: needsApproval)
Future<String> issueRefund(int amount) async => 'refunded';
''');
    addTearDown(() => project.deleteSync(recursive: true));
    await expectLater(
      _generate(project),
      throwsA(predicate((Object e) =>
          '$e'.contains('issueRefund') && '$e'.contains('approval'))),
    );
  });
}
