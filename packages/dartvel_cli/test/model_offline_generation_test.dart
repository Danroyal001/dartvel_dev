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

  test('a tenant-scoped model carries its tenant into replay', () async {
    // The hole: _dvRecords() scopes every ordinary read and write to the
    // current tenant, and the table replay applied to did not. A device
    // signed into one tenant could write a row that belonged to no tenant,
    // and the server would read another tenant's row of the same key when
    // it went looking for the stored one.
    final Directory root =
        await Directory.systemTemp.createTemp('dartvel_offline_tenant_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);
    File(p.join(root.path, 'lib', 'models', 'invoice.dart'))
        .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(tenantScoped: true, offline: DVConflict.lastWriteWins)
class _Invoice {
  final String id;
  final int totalCents;

  const _Invoice({required this.id, required this.totalCents});
}
''');
    await ModelGenerator.generate(
      root: root.path,
      pkgName: 'tenant_offline_app',
      buildId: 'test-build',
    );
    final String content =
        File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
            .readAsStringSync();

    final int start = content.indexOf('_dvOfflineTable(DVDatabaseAdapter');
    expect(start, isNonNegative);
    final String offlineTable = content.substring(start, start + 500);

    expect(offlineTable, contains('scope: DVRecordScope('));
    expect(offlineTable, contains('const DVTenants().currentTenant'));
  });

  test('the backend learns which models are offline, and how they resolve',
      () async {
    // The generated backend cannot import models.g.dart -- that file imports
    // Flutter -- so the route that applies replayed writes cannot call
    // Model.offlineRemote. It builds its remotes from the specs in
    // model_pages.g.dart, which already carry the table, the key, the
    // sensitive fields, tenancy, versioning and soft delete for exactly this
    // reason. The conflict strategy is the one thing they were missing.
    final Directory root =
        await Directory.systemTemp.createTemp('dartvel_offline_spec_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);
    File(p.join(root.path, 'lib', 'models', 'order.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(offline: DVConflict.lastWriteWins)
class _Order {
  final String id;
  final String reference;

  const _Order({required this.id, required this.reference});
}
''');
    File(p.join(root.path, 'lib', 'models', 'ledger.dart'))
        .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Ledger {
  final String id;
  final int balance;

  const _Ledger({required this.id, required this.balance});
}
''');
    await ModelGenerator.generate(
      root: root.path,
      pkgName: 'offline_spec_app',
      buildId: 'test-build',
    );
    final String pages =
        File(p.join(root.path, 'lib', 'dartvel_client', 'model_pages.g.dart'))
            .readAsStringSync();

    // The one that declared it says which strategy, and the one that did not
    // says nothing -- a spec that defaulted to a strategy would put every
    // model in the registry the route writes through.
    final int order = pages.indexOf("model: 'Order'");
    final int ledger = pages.indexOf("model: 'Ledger'");
    expect(order, isNonNegative);
    expect(ledger, isNonNegative);
    final String orderSpec =
        pages.substring(order, order < ledger ? ledger : pages.length);
    final String ledgerSpec =
        pages.substring(ledger, ledger < order ? order : pages.length);

    expect(orderSpec, contains('offline: DVConflict.lastWriteWins'));
    expect(ledgerSpec, isNot(contains('offline:')));
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
