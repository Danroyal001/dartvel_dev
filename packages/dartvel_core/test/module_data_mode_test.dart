// What a module's data mode does at run time.
//
// The four modes have been read out of the pubspec, carried into the
// generated registry and checked against the deployment for a while, and
// then nothing happened: a module declared schema-isolated queried the bare
// table name in the parent's database exactly as a shared one did. That is
// the worst shape a gap can take, because it works. A module whose model is
// called Order, mounted into an application that also has orders, reads and
// writes somebody else's rows and reports no error at all.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVModule _module(String id, String data) => DVModule(
      id: id,
      mountPath: '/$id',
      config: <String, Object?>{'data': data},
    );

void main() {
  _generatedSide();
  group('the mode a module was mounted with', () {
    test('is read off the registration', () {
      expect(_module('store', 'shared').dataMode, DVModuleDataMode.shared);
      expect(_module('store', 'schema-isolated').dataMode,
          DVModuleDataMode.schemaIsolated);
      expect(_module('store', 'database-isolated').dataMode,
          DVModuleDataMode.databaseIsolated);
      expect(_module('store', 'remote').dataMode, DVModuleDataMode.remote);
    });

    test('defaults to shared when nothing was declared', () {
      final DVModule module = DVModule(id: 'store', mountPath: '/store');
      expect(module.dataMode, DVModuleDataMode.shared);
    });

    test('an unrecognised mode is refused, not treated as shared', () {
      // Treating it as shared is the dangerous default: a typo in a pubspec
      // would put a module's tables in the parent's database silently.
      expect(() => _module('store', 'isolated-ish').dataMode,
          throwsA(isA<StateError>()));
    });
  });

  group('the table a module actually reads', () {
    test('shared is the name the model declared', () {
      expect(_module('store', 'shared').table('orders'), 'orders');
    });

    test('schema-isolated carries the module id', () {
      expect(_module('store', 'schema-isolated').table('orders'),
          'store_orders');
    });

    test('database-isolated keeps the plain name, in its own database', () {
      // Nothing to disambiguate from: the module has the database to itself,
      // and prefixing there would make the same module standing alone and
      // mounted read different tables.
      expect(_module('store', 'database-isolated').table('orders'), 'orders');
    });

    test('remote has no local table at all', () {
      expect(() => _module('store', 'remote').table('orders'),
          throwsA(isA<StateError>()));
    });

    test('a module id that is not an identifier cannot become one', () {
      // The prefix is concatenated into SQL. An id that is not a plain
      // identifier has to fail here rather than downstream.
      expect(() => _module('store-front', 'schema-isolated').table('orders'),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('the database a module reads from', () {
    late MemoryDVDatabaseAdapter application;

    setUp(() {
      application = MemoryDVDatabaseAdapter();
      const DVDatabase().configure(application);
    });

    tearDown(() => const DVDatabase().unconfigure());

    test('shared and schema-isolated use the application\'s', () {
      expect(identical(_module('store', 'shared').database, application),
          isTrue);
      expect(
          identical(_module('store', 'schema-isolated').database, application),
          isTrue);
    });

    test('database-isolated uses the one configured for it', () {
      final MemoryDVDatabaseAdapter own = MemoryDVDatabaseAdapter();
      final DVModule module = _module('store', 'database-isolated')
        ..useDatabase(own);

      expect(identical(module.database, own), isTrue);
    });

    test('database-isolated with none configured says which module', () {
      final DVModule module = _module('store', 'database-isolated');

      // Not the application's. Falling back would be a module writing into
      // the parent's database while its declaration says it does not.
      expect(
        () => module.database,
        throwsA(
          isA<StateError>().having(
              (StateError e) => e.message, 'message', contains('store')),
        ),
      );
    });

    test('remote refuses a local database', () {
      expect(() => _module('store', 'remote').database,
          throwsA(isA<StateError>()));
    });
  });
}

// Appended: what a module's generated model actually calls.
//
// A module's models are generated from the module's own project, standing
// alone, so they cannot be given the mount-time answer at generation time --
// the same module is mounted into different applications with different
// modes. They ask at run time instead, and the same code has to work when
// nothing mounted the module at all.
void _generatedSide() {
  group('what a generated model asks', () {
    late MemoryDVDatabaseAdapter application;

    setUp(() {
      dvModuleRegistry.resetForTesting();
      application = MemoryDVDatabaseAdapter();
      const DVDatabase().configure(application);
    });

    tearDown(() {
      dvModuleRegistry.resetForTesting();
      const DVDatabase().unconfigure();
    });

    test('an unmounted module reads the plain table in the application', () {
      // The module running on its own. Nothing registered it, so there is no
      // parent to have declared anything, and it is its own application.
      const DVModuleData data = DVModuleData('store');

      expect(data.table('orders'), 'orders');
      expect(identical(data.database, application), isTrue);
    });

    test('mounted shared, it reads the same thing', () {
      dvModuleRegistry.register(
        id: 'store',
        mountPath: '/store',
        config: const <String, Object?>{'data': 'shared'},
      );

      expect(const DVModuleData('store').table('orders'), 'orders');
    });

    test('mounted schema-isolated, it reads its own table', () {
      dvModuleRegistry.register(
        id: 'store',
        mountPath: '/store',
        config: const <String, Object?>{'data': 'schema-isolated'},
      );

      expect(const DVModuleData('store').table('orders'), 'store_orders');
    });

    test('mounted database-isolated, it reads its own database', () {
      final MemoryDVDatabaseAdapter own = MemoryDVDatabaseAdapter();
      dvModuleRegistry.register(
        id: 'store',
        mountPath: '/store',
        config: const <String, Object?>{'data': 'database-isolated'},
      ).useDatabase(own);

      expect(identical(const DVModuleData('store').database, own), isTrue);
      expect(const DVModuleData('store').table('orders'), 'orders');
    });

    test('mounted remote, reading locally fails rather than reading the '
        "parent's rows", () {
      dvModuleRegistry.register(
        id: 'store',
        mountPath: '/store',
        config: const <String, Object?>{'data': 'remote'},
      );

      expect(() => const DVModuleData('store').table('orders'),
          throwsA(isA<StateError>()));
    });
  });
}
