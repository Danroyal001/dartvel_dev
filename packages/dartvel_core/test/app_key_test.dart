// The application key and the cipher over it.
//
// This is the layer the shared window store's "encryption is Dartvel's job"
// claim rests on, so the tests are about the properties that claim implies:
// a fresh nonce per write, an unreadable value returning null rather than
// throwing, and a rotation that moves a store forward without stranding it.
import 'dart:math';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// Deterministic, so a test can assert what a real one must never do.
class FixedRandom implements Random {
  final int value;
  const FixedRandom(this.value);

  @override
  int nextInt(int max) => value % max;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

void main() {
  group('the key', () {
    test('is generated on first use and kept thereafter', () async {
      final store = DVMemoryAppKeyStore();

      final first = await DVAppKey.ensure(store);
      final second = await DVAppKey.ensure(store);

      expect(first.length, 32);
      expect(second, first, reason: 'a second call must not rotate the key');
    });

    test('a cleared store generates a new key', () async {
      final store = DVMemoryAppKeyStore();
      final first = await DVAppKey.ensure(store);
      await store.clear();

      final second = await DVAppKey.ensure(store);

      expect(second, isNot(first));
    });

    test('two installs do not share a key', () {
      expect(DVAppKey.generate(), isNot(DVAppKey.generate()),
          reason: 'per install and per user, so it is not a shared secret');
    });

    test('a key of the wrong length is refused', () {
      expect(() => DVAppKeyCipher(DVAppKey.generate().sublist(0, 16)),
          throwsArgumentError);
    });
  });

  group('the cipher', () {
    late DVAppKeyCipher cipher;

    setUp(() => cipher = DVAppKeyCipher(DVAppKey.generate()));

    test('a value round-trips', () {
      expect(cipher.decrypt(cipher.encrypt('workspace.activeTab=orders')),
          'workspace.activeTab=orders');
    });

    test('ciphertext does not contain the plaintext', () {
      expect(cipher.encrypt('super-secret-draft'),
          isNot(contains('super-secret-draft')));
    });

    test('a fresh nonce per write, so one key encrypts twice differently', () {
      // Nonce reuse under one key is what breaks GCM, which is why the nonce
      // is generated at the write rather than supplied by a caller.
      expect(cipher.encrypt('same'), isNot(cipher.encrypt('same')));
    });

    test('unicode survives the round trip', () {
      expect(cipher.decrypt(cipher.encrypt('タブ順 — draft ✓')), 'タブ順 — draft ✓');
    });

    test('another key cannot read it', () {
      final other = DVAppKeyCipher(DVAppKey.generate());

      expect(other.decrypt(cipher.encrypt('mine')), isNull,
          reason: 'a rotated key or a moved profile reads as unreadable');
    });

    test('a tampered value is rejected rather than returned', () {
      final sealed = cipher.encrypt('trusted');
      final tampered = '${sealed.substring(0, sealed.length - 4)}AAAA';

      expect(cipher.decrypt(tampered), isNull,
          reason: 'GCM authenticates; a modified value must not decrypt');
    });

    test('unreadable input returns null rather than throwing', () {
      for (final value in <String>['', 'plain', 'dv1:not-base64!!', 'dv1:AAAA']) {
        expect(cipher.decrypt(value), isNull, reason: value);
      }
    });

    test('a value written without the scheme prefix is not decrypted', () {
      expect(cipher.decrypt('AAAAAAAAAAAAAAAAAAAA'), isNull);
    });
  });

  group('rotation', () {
    test('re-encrypts every readable value under the new key', () {
      final from = DVAppKey.generate();
      final next = DVAppKey.generate();
      final old = DVAppKeyCipher(from);
      final values = <String, String>{
        'a': old.encrypt('one'),
        'b': old.encrypt('two'),
      };

      final rotated = DVAppKey.rotate(values, from: from, next: next);

      final reader = DVAppKeyCipher(next);
      expect(reader.decrypt(rotated['a']!), 'one');
      expect(reader.decrypt(rotated['b']!), 'two');
      expect(old.decrypt(rotated['a']!), isNull,
          reason: 'the old key must no longer read the rotated store');
    });

    test('an unreadable entry is dropped rather than stranding the rest', () {
      final from = DVAppKey.generate();
      final next = DVAppKey.generate();
      final values = <String, String>{
        'good': DVAppKeyCipher(from).encrypt('kept'),
        'bad': 'dv1:garbage',
      };

      final rotated = DVAppKey.rotate(values, from: from, next: next);

      expect(rotated.keys, <String>['good']);
    });
  });

  group('the nonce is not a formality', () {
    test('a fixed source produces the reuse a real one must avoid', () {
      // A negative control: with a deterministic source the two ciphertexts
      // match, which is exactly what Random.secure prevents in production.
      final key = DVAppKey.generate();
      final predictable = DVAppKeyCipher(key, random: const FixedRandom(7));

      expect(predictable.encrypt('same'), predictable.encrypt('same'));
    });
  });
}
