// A mounted module's tables, in the parent's database.
//
// The specification lists models, storage behaviour and migrations among what
// a backend-only module contributes, and a module that shares the parent's
// data is the default for anything compiled into it. Schema discovery read
// the parent's lib/models alone, so `dartvel db migrate` created every table
// but the module's, and the first anyone knew was a query against a table
// that was never there.
import 'dart:io';

import 'package:dartvel_cli/src/commands/db_command.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _product = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Product {
  final String id;
  const _Product(this.id);
}
''';

/// A parent with one model, mounting `store`, which has its own.
Directory workspace({String deployment = 'backend-only', String? data}) {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_module_schema_');
  addTearDown(() => root.deleteSync(recursive: true));

  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      source: { path: modules/store }
      mount: /store
      deployment: $deployment
${data == null ? '' : '      data: $data'}
''');
  File(p.join(root.path, 'lib', 'models', 'order.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_product.replaceAll('Product', 'Order'));

  final Directory module = Directory(p.join(root.path, 'modules', 'store'));
  module.createSync(recursive: true);
  File(p.join(module.path, 'pubspec.yaml')).writeAsStringSync('''
name: store
dartvel:
  module:
    id: store
    version: 1.0.0
''');
  File(p.join(module.path, 'lib', 'models', 'product.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_product);
  return root;
}

void main() {
  _oneRule();
  test('a module that shares the database has its tables created', () {
    final DartvelDbSchema schema = discoverLocalSchema(workspace().path);

    expect(schema.tables.map((DartvelDbTable t) => t.name),
        <String>['orders', 'products']);
    // Named, so a snapshot says which module a table belongs to rather than
    // leaving a reader to guess why the parent has a table no model of its
    // own declares.
    expect(schema.tables.firstWhere((DartvelDbTable t) => t.name == 'products').module,
        'store');
    expect(schema.tables.firstWhere((DartvelDbTable t) => t.name == 'orders').module,
        isNull);
  });

  test('a module with its own database does not', () {
    // database-isolated and remote each say the module's tables are not in
    // this database. Creating them here would make an empty copy the module
    // never writes to, and the module's own data would look like it had been
    // lost.
    //
    // schema-isolated is not one of them, which this test used to claim. It
    // means the parent's database and the module's own tables *within it* --
    // so skipping them left the module querying a table nothing had created.
    for (final String data in const <String>[
      'database-isolated',
      'remote',
    ]) {
      final DartvelDbSchema schema =
          discoverLocalSchema(workspace(data: data).path);

      expect(schema.tables.map((DartvelDbTable t) => t.name), <String>['orders'],
          reason: 'data: $data');
    }
  });

  test('a schema-isolated module has its tables created, under its own names',
      () {
    final DartvelDbSchema schema =
        discoverLocalSchema(workspace(data: 'schema-isolated').path);

    // The same name the module's generated models resolve to at run time.
    // The two have to agree or the migration writes one table and the query
    // reads another, which is the whole reason the naming rule is one rule.
    expect(schema.tables.map((DartvelDbTable t) => t.name),
        <String>['orders', 'store_products']);
    expect(
        schema.tables
            .firstWhere((DartvelDbTable t) => t.name == 'store_products')
            .module,
        'store');
  });

  test('a schema-isolated module cannot collide with the parent', () {
    // The prefix is what makes this safe: the parent has orders, the module
    // has orders, and mounted schema-isolated they are two tables. Before,
    // the module's was simply not created and its queries read the parent's
    // rows.
    final Directory root = workspace(data: 'schema-isolated');
    File(p.join(root.path, 'modules', 'store', 'lib', 'models', 'order.dart'))
        .writeAsStringSync(_product.replaceAll('Product', 'Order'));

    final DartvelDbSchema schema = discoverLocalSchema(root.path);

    expect(schema.tables.map((DartvelDbTable t) => t.name),
        <String>['orders', 'store_orders', 'store_products']);
  });

  test('a federated module does not', () {
    final DartvelDbSchema schema =
        discoverLocalSchema(workspace(deployment: 'federated').path);

    expect(schema.tables.map((DartvelDbTable t) => t.name), <String>['orders']);
  });

  test('a module table that collides with the parent\'s is refused', () {
    final Directory root = workspace();
    File(p.join(root.path, 'lib', 'models', 'product.dart'))
        .writeAsStringSync(_product);

    expect(
      () => discoverLocalSchema(root.path),
      throwsA(isA<StateError>().having((StateError e) => e.message, 'message',
          allOf(contains('store'), contains('products')))),
    );
  });
}

// Appended: the two halves of one naming rule.
//
// The migration decides what a schema-isolated module's table is called, and
// the module's generated models decide what to ask for. They are in different
// packages and neither would notice the other changing. If they ever
// disagree, the migration creates a table nothing reads and every query goes
// to one that is not there -- and it fails at run time, on a device, in a
// module whose whole point was that its data is its own.
void _oneRule() {
  test('the migration and the run time agree on the name', () {
    final DartvelDbSchema schema =
        discoverLocalSchema(workspace(data: 'schema-isolated').path);
    final DartvelDbTable table =
        schema.tables.firstWhere((DartvelDbTable t) => t.module == 'store');

    final DVModule mounted = DVModule(
      id: 'store',
      mountPath: '/store',
      config: const <String, Object?>{'data': 'schema-isolated'},
    );

    // 'products' is the name the model declares; both sides start there.
    expect(table.name, mounted.table('products'));
  });
}
