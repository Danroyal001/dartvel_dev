// window.persistState and window.restoreState were two of the names the
// framework called and nothing implemented, and they were on the list to be
// bound natively on every platform.
//
// They do not need a native binding. Persisting a window's state means
// recording its size and putting it back, and both halves already exist:
// Flutter knows its own window size, and window.setSize is bound on Linux and
// Windows. What was missing was somewhere to keep it between runs.
//
// So this is composed rather than bound — which is also why it works on macOS,
// where window.setSize is not bound: it degrades to remembering the size and
// declining to apply it, rather than throwing.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('encoding', () {
    test('a size round-trips through the stored form', () {
      const state = DVWindowState(width: 1280, height: 800);
      expect(DVWindowState.decode(state.encode()), state);
    });

    test('rubbish decodes to null rather than throwing', () {
      // The value comes from storage that another version of the application
      // wrote, so it is not trustworthy input. A throw here would break
      // startup over a stale preference.
      for (final bad in <String>['', 'nonsense', '{}', '{"width":"wide"}']) {
        expect(DVWindowState.decode(bad), isNull, reason: 'decoding $bad');
      }
    });

    test('a nonsensical size decodes to null', () {
      // Zero and negative sizes are what a crashed or minimised window can
      // leave behind, and restoring one produces a window nobody can find.
      expect(DVWindowState.decode('{"width":0,"height":800}'), isNull);
      expect(DVWindowState.decode('{"width":1280,"height":-1}'), isNull);
    });
  });

  group('storage key', () {
    test('it is namespaced, so an app key cannot collide with another', () {
      // It used to be 'dartvel.window.', which is not one of the reserved
      // prefixes -- so this state sat in the application's own namespace and
      // an application key could legally land on it, which is exactly what
      // this test claims cannot happen. Being namespaced only means anything
      // if the namespace is one applications are refused.
      final key = dvWindowStateKey('main');
      expect(key, contains('main'));
      expect(DVWindowSharedStore.reservedPrefixes.any(key.startsWith), isTrue,
          reason: '$key is not in a reserved namespace');

      expect(() => DVWindowSharedStore().set(key, const DVJsonString('x')),
          throwsA(isA<DVSharedStoreKeyError>()));
    });

    test('different windows get different keys', () {
      expect(dvWindowStateKey('main'), isNot(dvWindowStateKey('inspector')));
    });
  });
}
