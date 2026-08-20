// The shared window store.
//
// Two properties are the whole argument for a store rather than message
// passing, and both are tested here: a window that opens later reads current
// state rather than missing it, and a window that was never running when the
// write happened still finds it. A message has a delivery moment; a store
// does not.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A backend that notifies, standing in for a preference store on a
/// cross-engine target.
class NotifyingBackend extends DVSharedStoreBackend {
  final Map<String, String> values = <String, String>{};
  final StreamController<String> _changes = StreamController<String>.broadcast();

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<List<String>> keys() async => values.keys.toList(growable: false);

  @override
  Stream<String> get changed => _changes.stream;

  /// Another window wrote this key.
  void externalWrite(String key, String raw) {
    values[key] = raw;
    _changes.add(key);
  }
}

/// A cipher that refuses to decrypt, standing in for a rotated key.
class UndecryptableCipher implements DVSharedStoreCipher {
  @override
  String encrypt(String plaintext) => plaintext;

  @override
  String? decrypt(String ciphertext) => null;
}

const noDebounce = Duration.zero;

void main() {
  group('reads and writes', () {
    late DVWindowSharedStore store;

    setUp(() => store = DVWindowSharedStore(debounce: noDebounce));
    tearDown(() => store.dispose());

    test('a value round-trips', () async {
      await store.set('workspace.activeTab', const DVJsonString('orders'));

      final value = await store.get('workspace.activeTab');

      expect(value, isA<DVJsonString>());
      expect((value! as DVJsonString).value, 'orders');
    });

    test('an unset key reads null rather than throwing', () async {
      expect(await store.get('nothing.here'), isNull);
    });

    test('remove clears the key', () async {
      await store.set('a', const DVJsonNumber(1));
      await store.remove('a');

      expect(await store.get('a'), isNull);
      expect(await store.keys(), isNot(contains('a')));
    });

    test('nested values survive the wire format', () async {
      await store.set(
        'workspace.tabs',
        const DVJsonList(<DVJsonValue>[
          DVJsonString('orders'),
          DVJsonString('customers'),
        ]),
      );

      final value = await store.get('workspace.tabs');

      expect((value! as DVJsonList).value.length, 2);
    });
  });

  group('the reason it is a store and not a message', () {
    test('a late joiner reads current state rather than missing it', () async {
      final store = DVWindowSharedStore(debounce: noDebounce);
      addTearDown(store.dispose);

      // Written before anyone is watching — a message here would be gone.
      await store.set('workspace.activeTab', const DVJsonString('reports'));

      final signal = store.signal('workspace.activeTab');
      await Future<void>.delayed(Duration.zero);

      expect((signal.value! as DVJsonString).value, 'reports',
          reason: 'a window opened after the write must still see it');
    });

    test('a signal updates when another window writes', () async {
      final backend = NotifyingBackend();
      final store =
          DVWindowSharedStore(backend: backend, debounce: noDebounce);
      addTearDown(store.dispose);

      final signal = store.signal('workspace.activeTab');
      backend.externalWrite('workspace.activeTab', '"customers"');
      await Future<void>.delayed(Duration.zero);

      expect((signal.value! as DVJsonString).value, 'customers');
    });

    test('watch reports another window\'s change', () async {
      final backend = NotifyingBackend();
      final store =
          DVWindowSharedStore(backend: backend, debounce: noDebounce);
      addTearDown(store.dispose);

      final seen = <DVJsonValue?>[];
      store.watch('k').listen(seen.add);
      backend.externalWrite('k', '"from-another-window"');
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(1));
      expect((seen.single! as DVJsonString).value, 'from-another-window');
    });
  });

  group('coalescing', () {
    test('rapid writes to one key produce one backend write', () async {
      final backend = NotifyingBackend();
      final store = DVWindowSharedStore(
        backend: backend,
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(store.dispose);

      // A signal changing per frame must not write per frame.
      for (var i = 0; i < 10; i++) {
        unawaited(store.set('scroll', DVJsonNumber(i)));
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(backend.values['scroll'], '9',
          reason: 'last write wins, per key');
    });

    test('a pending write is readable immediately by this window', () async {
      final store =
          DVWindowSharedStore(debounce: const Duration(milliseconds: 50));
      addTearDown(store.dispose);

      unawaited(store.set('k', const DVJsonString('v')));

      expect(await store.get('k'), isA<DVJsonString>(),
          reason: 'the writing window must not read its own stale value');
    });

    test('flush writes now, for tear-out', () async {
      final backend = NotifyingBackend();
      final store = DVWindowSharedStore(
        backend: backend,
        debounce: const Duration(seconds: 30),
      );
      addTearDown(store.dispose);

      unawaited(store.set('handover', const DVJsonString('ready')));
      await store.flush('handover');

      expect(backend.values['handover'], isNotNull,
          reason: 'the new window reads this on boot; it cannot wait 30s');
    });
  });

  group('failure is never fatal', () {
    test('an undecryptable value is discarded, not thrown', () async {
      final backend = NotifyingBackend()..values['k'] = 'whatever';
      final store = DVWindowSharedStore(
        backend: backend,
        cipher: UndecryptableCipher(),
        debounce: noDebounce,
      );
      addTearDown(store.dispose);

      // A rotated key costs a tab order, not a window that refuses to open.
      expect(await store.get('k'), isNull);
    });

    test('a corrupt value is discarded, not thrown', () async {
      final backend = NotifyingBackend()..values['k'] = 'not json at all{';
      final store =
          DVWindowSharedStore(backend: backend, debounce: noDebounce);
      addTearDown(store.dispose);

      expect(await store.get('k'), isNull);
    });
  });

  group('DV.Window.shared', () {
    tearDown(DVWindowManager.reset);

    test('is available without configuration', () async {
      await DVWindowManager.shared.set('k', const DVJsonString('v'));

      expect(await DVWindowManager.shared.get('k'), isA<DVJsonString>());
    });

    test('a signal is the same object for the same key', () {
      final a = DVWindowManager.shared.signal('k');
      final b = DVWindowManager.shared.signal('k');

      expect(identical(a, b), isTrue);
      expect(a, isA<ValueListenable<DVJsonValue?>>());
    });
  });
}
