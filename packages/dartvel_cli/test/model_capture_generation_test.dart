// @DVModel(capture: true), so a captured model is declared rather than built.
//
// A generated model already builds its own DVRecordTable, with the table,
// key, columns and sensitive fields the annotation declares, and that table
// has always taken a change-capture log. Nothing could hand it one, so the
// only way to capture anything was to build a second DVRecordTable by hand
// and write rows to it as raw maps -- listing again the columns of a model
// that had already declared them, which is a second description of one
// model's shape and the one that drifts.
//
// docs/spec-status.json named this: "the @DVModel(capture: true) annotation
// field and a process-wide capture log for it to name" were the two absent
// pieces, "so generated models, which now write through DVRecordTable,
// capture nothing".
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> generated(String annotation) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_capture_test_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'models', 'order.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

$annotation
class _Order {
  final String id;
  final int total;
  @DVModel.sensitiveField()
  final String customerEmail;

  const _Order({
    required this.id,
    required this.total,
    required this.customerEmail,
  });
}
''');

  await ModelGenerator.generate(
    root: root.path,
    pkgName: 'capture_app',
    buildId: 'test-build',
  );

  return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
      .readAsStringSync();
}

void main() {
  test('a captured model writes to the configured log', () async {
    final String content = await generated('@DVModel(capture: true)');

    expect(content, contains('capture: DVCapture.configured'),
        reason: 'the model names the log rather than being handed one');
    // And it is the model's own table that is captured, with the columns the
    // annotation declared, so nobody lists them a second time.
    expect(content, contains("key: 'id'"));
    expect(content, contains("sensitive: const <String>{'customerEmail'}"),
        reason: 'a sensitive field is named in a change and never carried');
    // And the backfill is the model's, so an application copying its orders
    // to a warehouse never names the table underneath.
    expect(content, contains('static Future<DVCaptureBackfillProgress> backfillTo('));
  });

  test('a model that did not ask is not captured', () async {
    final String content = await generated('@DVModel()');

    expect(content, isNot(contains('capture:')),
        reason: 'capture is opt-in, and costs a write nothing until it is on');
    expect(content, isNot(contains('backfillTo')),
        reason: 'nothing to backfill from a model nobody captures');
  });
}
