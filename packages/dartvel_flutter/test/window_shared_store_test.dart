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

import 'window_shared_store_helpers.dart';

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
      await store.set('shop.activeTab', const DVJsonString('orders'));

      final value = await store.get('shop.activeTab');

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
        'shop.tabs',
        const DVJsonList(<DVJsonValue>[
          DVJsonString('orders'),
          DVJsonString('customers'),
        ]),
      );

      final value = await store.get('shop.tabs');

      expect((value! as DVJsonList).value.length, 2);
    });
  });

  group('the reason it is a store and not a message', () {
    test('a late joiner reads current state rather than missing it', () async {
      final store = DVWindowSharedStore(debounce: noDebounce);
      addTearDown(store.dispose);

      // Written before anyone is watching — a message here would be gone.
      await store.set('shop.activeTab', const DVJsonString('reports'));

      final signal = store.signal('shop.activeTab');
      await Future<void>.delayed(Duration.zero);

      expect((signal.value! as DVJsonString).value, 'reports',
          reason: 'a window opened after the write must still see it');
    });

    test('a signal updates when another window writes', () async {
      final backend = NotifyingBackend();
      final store =
          DVWindowSharedStore(backend: backend, debounce: noDebounce);
      addTearDown(store.dispose);

      final signal = store.signal('shop.activeTab');
      backend.externalWrite('shop.activeTab', '"customers"');
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

  group('encrypted at rest', () {
    test('the backend never sees the plaintext', () async {
      final backend = NotifyingBackend();
      final cipher = await DVAppKeySharedStoreCipher.forStore(
        DVMemoryAppKeyStore(),
      );
      final store = DVWindowSharedStore(
        backend: backend, cipher: cipher, debounce: noDebounce,
      );
      addTearDown(store.dispose);

      await store.set('draft', const DVJsonString('the unsent message'));

      expect(backend.values['draft'], isNotNull);
      expect(backend.values['draft'], isNot(contains('unsent')),
          reason: 'the store is a byte sink; encryption happens before it');
      expect(backend.values['draft'], startsWith('dv1:'));
    });

    test('and the value still round-trips', () async {
      final cipher = await DVAppKeySharedStoreCipher.forStore(
        DVMemoryAppKeyStore(),
      );
      final store = DVWindowSharedStore(
        backend: NotifyingBackend(), cipher: cipher, debounce: noDebounce,
      );
      addTearDown(store.dispose);

      await store.set('k', const DVJsonString('readable again'));
      store.evictCache();

      expect(((await store.get('k'))! as DVJsonString).value, 'readable again');
    });

    test('a store written under another key reads as empty, not broken',
        () async {
      final backend = NotifyingBackend();
      final theirs = await DVAppKeySharedStoreCipher.forStore(
        DVMemoryAppKeyStore(),
      );
      final writing = DVWindowSharedStore(
        backend: backend, cipher: theirs, debounce: noDebounce,
      );
      await writing.set('k', const DVJsonString('theirs'));
      await writing.dispose();

      // A rotated key, a reset keychain, a profile moved between machines.
      final ours = await DVAppKeySharedStoreCipher.forStore(
        DVMemoryAppKeyStore(),
      );
      final reading = DVWindowSharedStore(
        backend: backend, cipher: ours, debounce: noDebounce,
      );
      addTearDown(reading.dispose);

      expect(await reading.get('k'), isNull,
          reason: 'losing view state costs a tab order, not a window');
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
