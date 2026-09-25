// A data model that works offline says so, and the rest is the model's.
//
// The sample built a DVOfflineStore by hand: a DVRecordTable restating the
// table name, the key and every column the model declares, a remote on the
// server restating all of it again, and a replay the application had to call
// on a reconnect it had to notice. Now the model's own save, destroy and
// reads are the whole surface, and the runtime does the rest.
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
  /// The generated member starting at [signature], up to the next member.
  String member(String content, String signature) {
    final int start = content.indexOf(signature);
    expect(start, isNonNegative, reason: 'no $signature generated');
    final int end = content.indexOf(RegExp(r'\n  (static |///)|\n}'), start);
    return content.substring(start, end < 0 ? content.length : end);
  }

  test('saving writes on the device at once and queues it', () async {
    // The runtime was built and the model did not use it: Order.save wrote
    // to whatever database the process had, so a write made offline was a
    // row the server never heard of, and syncing was a store an application
    // had to construct and a replay it had to call.
    final String content = await generated(
      '@DVModel(offline: DVConflict.lastWriteWins)',
    );

    expect(content,
        contains("_dvOffline() => DVOfflineSync.store('Order')"));
    final String save = member(content, 'static Future<Order> save(');
    expect(save, contains('_dvOffline()'));
    expect(save, contains('.write('));
    expect(save, contains("DVOfflineSync.written('Order')"));
    expect(save, isNot(contains('_dvRecords().write(')));

    final String destroy = member(content, 'static Future<void> destroy(');
    expect(destroy, contains('.delete('));
    expect(destroy, contains("DVOfflineSync.written('Order')"));
    expect(destroy, isNot(contains('_dvRecords().delete(')));
  });

  test('reads come from the device copy, so they work with no network',
      () async {
    final String content = await generated(
      '@DVModel(offline: DVConflict.lastWriteWins)',
    );

    expect(member(content, 'static Future<Order?> find('),
        contains('_dvOffline()'));
    expect(member(content, 'static Future<core.List<Order>> all('),
        contains('_dvOffline()'));
    // The columns are the model's stored columns, written once.
    expect(
      content,
      contains("columns: const <String>['id', 'reference', 'quantity']"),
    );
  });

  test('the model is registered, so last session\'s queue is sent', () async {
    // The runtime replays every registered queue at start. A model whose
    // store was made only when it was first used would leave yesterday's
    // writes on the device until somebody opened a screen that read it.
    final String content = await generated(
      '@DVModel(offline: DVConflict.lastWriteWins)',
    );

    expect(member(content, 'void _registerOrder()'),
        contains("DVOfflineSync.register('Order'"));
  });

  test('a record says where it stands, and nothing else is to be named',
      () async {
    final String content = await generated(
      '@DVModel(offline: DVConflict.lastWriteWins)',
    );

    expect(content, contains('Stream<DVSyncState> get syncState'));
    // The machinery is the framework's. A generated member returning a
    // store or a remote put it in the application's hands, and a validate:
    // taking a map of column names put a record shape there.
    expect(content, isNot(contains('offlineStore(')));
    expect(content, isNot(contains('offlineRemote(')));
    expect(content, isNot(contains('Map<String, Object?> values)? validate')));
  });

  test('a copy the server replaced is published, so a watcher sees it',
      () async {
    final String content = await generated(
      '@DVModel(offline: DVConflict.lastWriteWins)',
    );

    final String register = member(content, 'void _registerOrder()');
    expect(register, contains('onAdopted:'));
    expect(register, contains('DVModelChangeKind.updated'));
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

  test('a model that did not ask for it is not queued', () async {
    final String content = await generated('@DVModel()');

    expect(content, isNot(contains('DVOfflineSync')));
    expect(content, isNot(contains('syncState')));
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
