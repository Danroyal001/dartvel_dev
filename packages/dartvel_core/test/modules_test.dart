import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late DVModuleRegistry modules;

  setUp(() => modules = DVModuleRegistry());

  group('registration', () {
    test('registers and returns a module', () {
      final store = modules.register(id: 'store', mountPath: '/store');
      expect(store.id, 'store');
      expect(store.mountPath, '/store');
      expect(modules.has('store'), isTrue);
      expect(modules.ids, <String>['store']);
    });

    test('re-registering replaces rather than duplicates', () {
      // Hot restart re-runs registration; it must not accumulate stale entries.
      modules.register(id: 'store', mountPath: '/store');
      modules.register(id: 'store', mountPath: '/shop');
      expect(modules.ids, <String>['store']);
      expect(modules.get('store').mountPath, '/shop');
    });

    test('preserves registration order', () {
      modules.register(id: 'a', mountPath: '/a');
      modules.register(id: 'b', mountPath: '/b');
      modules.register(id: 'c', mountPath: '/c');
      expect(modules.ids, <String>['a', 'b', 'c']);
      expect(modules.all.map((m) => m.id), <String>['a', 'b', 'c']);
    });
  });

  group('lookup', () {
    test('callable and get() are equivalent', () {
      modules.register(id: 'store', mountPath: '/store');
      expect(modules('store'), same(modules.get('store')));
    });

    test('an unknown module throws with the registered ids listed', () {
      modules.register(id: 'store', mountPath: '/store');
      try {
        modules.get('blog');
        fail('expected DVUnknownModuleException');
      } on DVUnknownModuleException catch (error) {
        expect(error.id, 'blog');
        expect(error.known, contains('store'));
        expect(error.toString(), contains('blog'));
        expect(error.toString(), contains('store'));
      }
    });

    test('maybeGet returns null instead of throwing', () {
      expect(modules.maybeGet('absent'), isNull);
    });
  });

  group('mount point independence', () {
    test('resolve() builds paths against the mount point', () {
      final store = modules.register(id: 'store', mountPath: '/store');
      expect(store.resolve('/products'), '/store/products');
      expect(store.resolve('products'), '/store/products');
    });

    test('the same module resolves differently when mounted elsewhere', () {
      // Module code must not hard-code its mount point.
      final store = modules.register(id: 'store', mountPath: '/store');
      expect(store.resolve('/cart'), '/store/cart');

      store.setMountPath('/shop');
      expect(store.resolve('/cart'), '/shop/cart');
    });

    test('handles a trailing slash on the mount point', () {
      final store = modules.register(id: 'store', mountPath: '/store/');
      expect(store.resolve('/products'), '/store/products');
    });

    test('handles mounting at the root', () {
      final root = modules.register(id: 'root', mountPath: '/');
      expect(root.resolve('/products'), '/products');
    });
  });

  group('module lifecycle', () {
    test('starts as discovered', () {
      final store = modules.register(id: 'store', mountPath: '/store');
      expect(store.lifecycle.value, DVModuleLifecycle.discovered);
    });

    test('emits transitions to observers', () async {
      final store = modules.register(id: 'store', mountPath: '/store');
      final seen = <DVModuleLifecycle>[];
      store.lifecycle.listen(seen.add);

      store.setLifecycle(DVModuleLifecycle.loading);
      store.setLifecycle(DVModuleLifecycle.mounted);
      store.setLifecycle(DVModuleLifecycle.active);
      await Future<void>.delayed(Duration.zero);

      expect(seen, <DVModuleLifecycle>[
        DVModuleLifecycle.loading,
        DVModuleLifecycle.mounted,
        DVModuleLifecycle.active,
      ]);
    });

    test('modules carry independent lifecycles', () {
      final a = modules.register(id: 'a', mountPath: '/a');
      final b = modules.register(id: 'b', mountPath: '/b');
      a.setLifecycle(DVModuleLifecycle.failed);
      expect(a.lifecycle.value, DVModuleLifecycle.failed);
      expect(b.lifecycle.value, DVModuleLifecycle.discovered);
    });
  });

  group('configuration', () {
    test('is exposed to the module', () {
      final store = modules.register(
        id: 'store',
        mountPath: '/store',
        config: <String, Object?>{'currency': 'NGN'},
      );
      expect(store.config['currency'], 'NGN');
    });

    test('is immutable, so a module cannot rewrite what the parent passed', () {
      final store = modules.register(
        id: 'store',
        mountPath: '/store',
        config: <String, Object?>{'currency': 'NGN'},
      );
      expect(() => store.config['currency'] = 'USD', throwsUnsupportedError);
    });
  });
  moduleAssets();
}

// A module's assets move when it is mounted: Flutter serves another
// package's asset under packages/<name>/, so the path a module uses on its
// own is not the path that finds the file once a parent mounts it. Module
// code asks by its own name, which is what keeps the mount point out of it.
void moduleAssets() {
  group('assets', () {
    test('a mounted module answers with the path that finds the file here', () {
      final DVModuleRegistry registry = DVModuleRegistry();
      registry.register(
        id: 'store',
        mountPath: '/store',
        assets: <String, String>{'assets/logo.png': 'packages/store/assets/logo.png'},
      );

      expect(registry('store').asset('assets/logo.png'), 'packages/store/assets/logo.png');
    });

    test('a path the module never declared is its own, not a guess', () {
      final DVModuleRegistry registry = DVModuleRegistry();
      registry.register(id: 'store', mountPath: '/store');

      expect(registry('store').asset('assets/unknown.png'), 'assets/unknown.png');
    });
  });

  group('a registered module says where it is running', () {
    // DV.Modules.<id>.lifecycle was created at discovered and never moved.
    // Twelve states, one of them ever produced -- so an application waiting
    // for a module to be usable waited forever, and the signal reported a
    // module permanently being discovered. An enum that reports one value
    // for the life of the process is a field, not a signal.
    //
    // What registering says depends on where the module runs, and calling
    // every registered module active would be a claim the parent cannot
    // make.
    DVModuleLifecycle stateFor(String? deployment) => DVModuleRegistry()
        .register(
          id: 'm',
          mountPath: '/m',
          config: deployment == null
              ? const <String, Object?>{}
              : <String, Object?>{'deployment': deployment},
        )
        .lifecycle
        .value;

    test('one compiled into this artifact is active', () {
      expect(stateFor('embedded'), DVModuleLifecycle.active);
      expect(stateFor('backendOnly'), DVModuleLifecycle.active);
    });

    test('a split backend is active too, because its pages are here', () {
      // Only its functions answer elsewhere. The part somebody looks at is
      // compiled in and running.
      expect(stateFor('splitBackend'), DVModuleLifecycle.active);
    });

    test('a federated one is mounted, not active', () {
      // It is built and deployed somewhere else. The parent holds its routes
      // so it can send readers there, and whether it is up is not something
      // this process knows -- active would report a module that may be down.
      expect(stateFor('federated'), DVModuleLifecycle.mounted);
    });

    test('one that did not say stays discovered', () {
      // The registry has been handed something it cannot place, and a guess
      // is the whole problem again.
      expect(stateFor(null), DVModuleLifecycle.discovered);
      expect(stateFor('somethingElse'), DVModuleLifecycle.discovered);
    });

    test('every module in a registry, not just the first', () {
      final DVModuleRegistry registry = DVModuleRegistry();
      const Map<String, Object?> embedded = <String, Object?>{
        'deployment': 'embedded',
      };

      registry.register(id: 'notes', mountPath: '/notes', config: embedded);
      registry.register(id: 'store', mountPath: '/store', config: embedded);

      expect(
        registry.all.map((DVModule m) => m.lifecycle.value),
        everyElement(DVModuleLifecycle.active),
      );
    });
  });
}
