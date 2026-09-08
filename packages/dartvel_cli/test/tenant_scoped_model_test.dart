// Rows scoped by a tenant column, on the strategy named for it.
//
// DVTenantIsolation.sharedDatabase is "one database, one schema, rows scoped
// by a tenant column". Resolution was real -- the tenant comes off the
// subdomain or the header, the middleware makes it current, presence is
// scoped by it -- and the column was not: the word tenant appeared zero
// times in the model generator and nowhere in any database adapter, so every
// generated query read every tenant's rows.
//
// Filtering cannot be bolted on to the reads alone. A column written and not
// filtered on, or filtered on and not written, would each look exactly like
// the feature working while being worse than not having it: the first leaks,
// the second hides every row. So the schema, the writes and the reads are
// asserted together here.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> _generate(String source, {String pkg = 'tenant_app'}) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_tenant_');
  try {
    Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);
    File(p.join(root.path, 'lib', 'models', 'order.dart'))
        .writeAsStringSync(source);

    await ModelGenerator.generate(
      root: root.path,
      pkgName: pkg,
      buildId: 'test-build',
    );

    return File(
      p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
    ).readAsStringSync();
  } finally {
    root.deleteSync(recursive: true);
  }
}

const String _scoped = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(tenantScoped: true)
class _Order {
  final String id;
  final String total;

  const _Order({required this.id, required this.total});
}
''';

const String _unscoped = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Order {
  final String id;
  final String total;

  const _Order({required this.id, required this.total});
}
''';

void main() {
  group('a tenant-scoped model', () {
    test('has a tenant column in its schema', () async {
      final String generated = await _generate(_scoped);
      expect(generated, contains('dv_tenant TEXT'));
    });

    test('every read is filtered by the current tenant', () async {
      final String generated = await _generate(_scoped);

      // Both readers. all() was the obvious one; find() by key is the one
      // that looks safe because it has a predicate already, and a key that
      // is unique per tenant rather than globally is exactly how one tenant
      // reads another's row.
      // The table resolves for the tenant asking and the predicate is on
      // the read. Both together: the name alone would pass on a query with
      // no predicate, and the predicate alone would pass on one that reads
      // the shared table under schemaPerTenant.
      expect(
        generated,
        contains("SELECT * FROM \${dvTenantTable('orders')} "
            'WHERE dv_tenant = ?'),
      );
      expect(
        generated,
        contains('WHERE dv_tenant = ? AND id = ?'),
      );
    });

    test('every write carries the current tenant', () async {
      final String generated = await _generate(_scoped);

      // The insert has to store it or every read filters everything out,
      // which is the failure that looks like an empty database.
      expect(generated, contains('dv_tenant'));
      expect(generated, contains('INSERT INTO'));
      final int insertAt = generated.indexOf('INSERT INTO');
      expect(
        generated.substring(insertAt, insertAt + 200),
        contains('dv_tenant'),
      );
    });

    test('a delete cannot reach another tenant\'s row', () async {
      final String generated = await _generate(_scoped);
      expect(
        generated,
        contains("DELETE FROM \${dvTenantTable('orders')} "
            'WHERE dv_tenant = ? AND id = ?'),
      );
    });

    test('the tenant bound is the current one, read at call time', () async {
      // Not captured once into a constant. The tenant is per request and
      // DVTenants keeps it in a zone, so reading it when the query runs is
      // the whole point.
      final String generated = await _generate(_scoped);
      expect(generated, contains('const DVTenants().currentTenant'));
    });
  });

  group('a model that did not ask', () {
    test('carries no tenant column and no predicate', () async {
      // Opt-in per model: a single-tenant application should not carry a
      // column it never reads, and a table deliberately shared across
      // tenants would be broken by a predicate it never asked for.
      final String generated = await _generate(_unscoped, pkg: 'plain_app');
      expect(generated, isNot(contains('dv_tenant')));
      expect(generated, isNot(contains('DVTenants')));
    });
  });

  group('what it refuses', () {
    test('a tenant-scoped model cannot also have public pages', () async {
      // The public page resolver reads the row by key with no tenant
      // predicate, and it has to: a statically generated page is written
      // with no request, so there is no current tenant to scope it by. One
      // tenant's row would be served at a public URL to anybody -- the exact
      // leak the column exists to close, on the one path that never sees it.
      await expectLater(
        _generate('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(tenantScoped: true, generatePublicPages: true)
class _Order {
  final String id;
  final String total;

  const _Order({required this.id, required this.total});
}
'''),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(
              contains('tenantScoped'),
              contains('generatePublicPages'),
              contains('Order'),
            ),
          ),
        ),
      );
    });

    test('a field named dv_tenant collides with the column', () async {
      // Two columns of that name is a create-table error at runtime, in a
      // deployment, rather than a generation error here.
      await expectLater(
        _generate('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(tenantScoped: true)
class _Order {
  final String id;
  final String dv_tenant;

  const _Order({required this.id, required this.dv_tenant});
}
'''),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('dv_tenant'), contains('Order')),
          ),
        ),
      );
    });
  });

  group('the generated client says which tables are scoped', () {
    test('a scoped model is registered, so a raw query can be refused', () async {
      // The check that refuses a raw query reading across every tenant lives
      // in the database layer, which has no idea what a model is. This
      // registration is the only thing that tells it, so a generator that
      // emitted the predicate and not this would leave every hand-written
      // query unchecked while looking complete.
      final String generated = await _generate(_scoped);

      expect(
        generated,
        contains("dvRegisterTenantScopedTables(<String>{'orders'})"),
      );
    });

    test('an unscoped model registers nothing', () async {
      final String generated = await _generate(_unscoped);

      expect(generated, contains('dvRegisterTenantScopedTables(<String>{})'));
    });
  });
}
