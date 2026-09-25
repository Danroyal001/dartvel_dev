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
// The annotation and dartvel.capture in the pubspec are all an application
// writes. The model generated here records its writes to the log; the spec
// the server reads says it is captured, so the server's own writes to it --
// Studio's, a device's replayed ones -- are recorded too, and the runtime
// knows which tables to backfill. Nothing on the model is capture machinery
// an application would call.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<({String models, String pages, Set<String> captured})> generated(
  String annotation,
) async {
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

  final Set<String> captured = await ModelGenerator.generate(
    root: root.path,
    pkgName: 'capture_app',
    buildId: 'test-build',
  );

  String read(String name) =>
      File(p.join(root.path, 'lib', 'dartvel_client', name)).readAsStringSync();
  return (
    models: read('models.g.dart'),
    pages: read('model_pages.g.dart'),
    captured: captured,
  );
}

void main() {
  test('a captured model writes to the configured log', () async {
    final generation = await generated('@DVModel(capture: true)');

    expect(generation.models, contains('capture: DVCapture.configured'),
        reason: 'the model names the log rather than being handed one');
    // And it is the model's own table that is captured, with the columns the
    // annotation declared, so nobody lists them a second time.
    expect(generation.models, contains("key: 'id'"));
    expect(generation.models,
        contains("sensitive: const <String>{'customerEmail'}"),
        reason: 'a sensitive field is named in a change and never carried');
  });

  // Model.backfillTo(consumer) was how an application copied a model's rows
  // to a destination it had built. The framework backfills a destination
  // that has never been copied to, so the member is gone: an application
  // that names a consumer is wiring machinery the pubspec already declares.
  test('a captured model has no capture machinery on it', () async {
    final generation = await generated('@DVModel(capture: true)');

    expect(generation.models, isNot(contains('backfillTo')));
    expect(generation.models, isNot(contains('DVCaptureConsumer')));
  });

  test("the server's spec of a captured model says it is captured", () async {
    final generation = await generated('@DVModel(capture: true)');

    expect(generation.pages, contains('capture: true'),
        reason: "Studio's and replayed writes are the model's writes too");
    expect(generation.captured, <String>{'Order'},
        reason: 'the build checks dartvel.capture against these');
  });

  test('a model that did not ask is not captured', () async {
    final generation = await generated('@DVModel()');

    expect(generation.models, isNot(contains('capture:')),
        reason: 'capture is opt-in, and costs a write nothing until it is on');
    expect(generation.pages, isNot(contains('capture: true')));
    expect(generation.captured, isEmpty);
  });
}
