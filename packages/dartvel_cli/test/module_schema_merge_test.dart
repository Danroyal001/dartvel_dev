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
    // database-isolated, schema-isolated and remote each say the module's
    // tables are not in this database. Creating them here would make an
    // empty copy the module never writes to, and the module's own data would
    // look like it had been lost.
    for (final String data in const <String>[
      'database-isolated',
      'schema-isolated',
      'remote',
    ]) {
      final DartvelDbSchema schema =
          discoverLocalSchema(workspace(data: data).path);

      expect(schema.tables.map((DartvelDbTable t) => t.name), <String>['orders'],
          reason: 'data: $data');
    }
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
