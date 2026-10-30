// An AI tool is declared with @DVAITool and nothing else.
//
// The owner's decision: there is one way to give a model a tool, the
// annotation, and the generated registration is how it reaches the registry.
// A DV.AI.registerTool beside it would be a second way to declare a tool that
// the build never sees -- no generated schema, no approval read from source,
// nothing in the documentation the project graph renders -- and the
// registry's own register is the same thing one level down. So neither
// resolves from what a page imports.
//
// The check analyzes a file that imports what a page imports, so it fails
// when a name comes back by any route rather than when one export line
// changes.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<String> analyzed(String source) async {
  final Directory scratch = Directory(
    p.join(
      Directory.current.path,
      '.dart_tool',
      'dv_ai_tool_surface_check',
      'probe_${DateTime.now().microsecondsSinceEpoch}',
    ),
  )..createSync(recursive: true);
  addTearDown(() {
    if (scratch.parent.existsSync()) scratch.parent.deleteSync(recursive: true);
  });
  final File probe = File(p.join(scratch.path, 'probe.dart'))
    ..writeAsStringSync(source);
  final ProcessResult result = await Process.run(
    'dart',
    <String>['analyze', '--no-fatal-warnings', probe.path],
  );
  return '${result.stdout}${result.stderr}';
}

void main() {
  test('a page reaches DV.AI, the agent run and its pause', () async {
    // The control: if this stops holding, the checks below pass because
    // nothing resolves rather than because registration is hidden.
    final String output = await analyzed('''
import 'package:dartvel_flutter/dartvel_flutter.dart';

Future<void> use() async {
  final DVAIAgentResult result = await DV.AI.runAgent(
    const DVAIAgentRequest(goal: 'g', tools: <String>['t']),
  );
  final DVAIToolPause? pause = result.pause;
  await pause?.resume(approved: true);
  final bool known = DV.AI.hasTool('t');
  const DVToolApproval approval = DVToolApproval.required;
}
''');
    expect(output, isNot(contains(' error ')));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('DV.AI has no registerTool', () async {
    final String output = await analyzed('''
import 'package:dartvel_flutter/dartvel_flutter.dart';

Object? get probe => DV.AI.registerTool;
''');
    expect(output, contains('probe.dart:3:'),
        reason: 'DV.AI.registerTool still resolves from a page');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a page cannot name the tool registry', () async {
    final String output = await analyzed('''
import 'package:dartvel_flutter/dartvel_flutter.dart';

Type get probe => DVAIToolRegistry;
''');
    expect(output, contains('probe.dart:3:'),
        reason: 'DVAIToolRegistry still resolves from a page');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
