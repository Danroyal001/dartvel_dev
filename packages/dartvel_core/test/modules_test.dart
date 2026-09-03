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
}
