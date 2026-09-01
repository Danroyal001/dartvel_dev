// The reserved key namespaces in the shared window store.
//
// The specification says application keys must not start with `dv.` or
// `workspace.`, and that a violation is a typed runtime failure where it
// cannot be a build error. Nothing enforced it, so an application could write
// `workspace.layout.main` and silently overwrite the tab workspace's own
// layout -- the failure arriving later, as a workspace that restores wrong,
// with nothing pointing at the write that caused it.
//
// The framework's own state was under `dartvel.window.*`, which is neither
// reserved prefix, so it sat in the application's namespace and an application
// key could collide with it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DVWindowSharedStore store;

  setUp(() => store = DVWindowSharedStore());
  tearDown(() => store.dispose());

  group('reserved prefixes', () {
    test('an application cannot write under dv.', () {
      expect(() => store.set('dv.anything', const DVJsonString('x')),
          throwsA(isA<DVSharedStoreKeyError>()));
    });

    test('an application cannot write under workspace.', () {
      // The concrete collision: DVTabWorkspace stores layouts here.
      expect(
          () => store.set('workspace.layout.main', const DVJsonString('x')),
          throwsA(isA<DVSharedStoreKeyError>()));
    });

    test('reading a reserved key is refused too', () {
      // Refusing only writes would leave an application reading framework
      // state as if it were its own, and depending on its shape.
      expect(() => store.get('dv.window.main'),
          throwsA(isA<DVSharedStoreKeyError>()));
    });

    test('watching and signalling a reserved key are refused', () {
      expect(() => store.watch('workspace.layout.main'),
          throwsA(isA<DVSharedStoreKeyError>()));
      expect(() => store.signal('dv.window.main'),
          throwsA(isA<DVSharedStoreKeyError>()));
    });

    test('flushing a reserved key is refused', () {
      expect(() => store.flush('dv.window.main'),
          throwsA(isA<DVSharedStoreKeyError>()));
    });

    test('the error names the key and the prefix', () {
      // A typed failure nobody can act on is only a crash with a nicer name.
      try {
        // ignore: discarded_futures
        store.set('workspace.x', const DVJsonString('x'));
        fail('expected a DVSharedStoreKeyError');
      } on DVSharedStoreKeyError catch (error) {
        expect(error.key, 'workspace.x');
        expect(error.toString(), contains('workspace.'));
        expect(error.toString(), contains('workspace.x'));
      }
    });
  });

  group('what is still allowed', () {
    test('an ordinary application key works', () async {
      await store.set('cart.total', const DVJsonString('12'));
      expect(await store.get('cart.total'), const DVJsonString('12'));
    });

    test('a key merely containing a reserved word is fine', () {
      // The rule is a prefix rule. Rejecting any key with "workspace" in it
      // would refuse `myapp.workspace.name`, which collides with nothing.
      expect(() => store.set('myapp.workspace.name', const DVJsonString('x')),
          returnsNormally);
      expect(() => store.set('dvorak', const DVJsonString('x')),
          returnsNormally);
    });

    test('the prefix must be exactly that, dot included', () {
      // `dvthing` is not in the `dv.` namespace.
      expect(() => store.set('dvthing', const DVJsonString('x')),
          returnsNormally);
      expect(() => store.set('workspaces.mine', const DVJsonString('x')),
          returnsNormally);
    });
  });

  group('the framework itself', () {
    test('stores window state under a reserved prefix', () {
      // It was `dartvel.window.*`, which is neither reserved prefix -- so it
      // sat in the application's namespace, where an application key could
      // legally collide with it.
      expect(dvWindowStateKey('main'), startsWith('dv.'));
    });

    test('and can still write there', () async {
      // The rule binds applications, not the framework that reserved it. If
      // the internal path went through the public one, persisting window state
      // would now throw on every desktop launch.
      TestWidgetsFlutterBinding.ensureInitialized();
      addTearDown(DVWindowManager.reset);

      await expectLater(DV.Platform.Window.persistState('main'),
          completes);
      await expectLater(DV.Platform.Window.restoreState('main'), completes);
    });
  });
}
