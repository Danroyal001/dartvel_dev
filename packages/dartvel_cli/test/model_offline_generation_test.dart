// A data model that works offline says so, and the rest is the model's.
//
// The sample built a DVOfflineStore by hand: a DVRecordTable restating the
// table name, the key and every column the model declares a few lines above
// its own annotation, and then a DVRecordTableRemote on the server restating
// all of it again. Two hand-written copies of one model's shape, which drift
// the first time a field is added.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> generated(String annotation) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_offline_gen_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'models', 'order.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

$annotation
class _Order {
  final String id;
  final String reference;
  final int quantity;

  const _Order({
    required this.id,
    required this.reference,
    required this.quantity,
  });
}
''');

  await ModelGenerator.generate(
    root: root.path,
    pkgName: 'offline_app',
    buildId: 'test-build',
  );

  return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
      .readAsStringSync();
}

void main() {
  test('the store and the remote come from the model', () async {
    final String content = await generated(
      '@DVModel(offline: DVConflict.lastWriteWins)',
    );

    expect(content, contains('static DVOfflineStore offlineStore('));
    expect(content, contains('static DVOfflineRemote offlineRemote('));
    // The columns are the model's stored columns, written once.
    expect(
      content,
      contains("columns: const <String>['id', 'reference', 'quantity']"),
    );
    expect(content, contains('DVConflict.lastWriteWins'));
  });

  test('the server side asks the model\'s policy, per mutation', () async {
    // Replay is the one write path where the server is handed a change that
    // nothing on the server decided to make. Before this, Model.offlineRemote
    // applied a device's queued writes with at most a synchronous look at
    // the values -- and a queued delete was not even given that.
    final String content = await generated(
      '@DVModel(offline: DVConflict.lastWriteWins)',
    );

    expect(content, contains('authorize: (DVMutation mutation) async {'));
    // The same three actions an online write asks about, chosen the same way.
    expect(content, contains("'Order.delete'"));
    expect(content, contains("'Order.update'"));
    expect(content, contains("'Order.create'"));
    // And a refusal is a refusal, not an exception that escapes replay.
    expect(content, contains('return false;'));
  });

  test('a model that did not ask for it has neither', () async {
    final String content = await generated('@DVModel()');

    expect(content, isNot(contains('offlineStore(')));
    expect(content, isNot(contains('offlineRemote(')));
  });

  test('a strategy that cannot work offline is refused at the build', () async {
    expect(
      () => generated('@DVModel(offline: DVConflict.ask)'),
      throwsA(isA<StateError>().having(
        (StateError e) => e.message,
        'message',
        contains('nobody to ask'),
      )),
    );
  });
}
