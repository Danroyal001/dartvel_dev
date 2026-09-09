// The server-side key surface `@DVModel.sensitiveField(encrypted: true)` had
// nothing to wire to. DVAppKeyCipher is a per-device key held by an OS key
// store, which is the wrong threat model for a column in a shared database,
// and DV.Secrets only reads configuration.
//
// These tests pin the behaviour that makes the flag safe to honour: a key
// that only ever comes from the server process environment, a ciphertext
// bound to the column it was written for, an unreadable value that raises
// rather than quietly becoming null, and error text that never carries the
// key or the plaintext into a log.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// Deterministic bytes so a test can name an exact key.
Uint8List _key(int seed) {
  final random = Random(seed);
  return Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
}

String _keyring(Map<String, Uint8List> keys) => keys.entries
    .map((MapEntry<String, Uint8List> e) => '${e.key}:${base64Encode(e.value)}')
    .join(',');

void main() {
  setUp(DVFieldEncryption.reset);
  tearDown(() {
    DVFieldEncryption.reset();
    DVSecrets.reset();
  });

  group('DVFieldCipher', () {
    test(
      'a value survives a round trip through the column it was written for',
      () {
        final cipher = DVFieldCipher(
          DVFieldKeyring.parse(_keyring({'k1': _key(1)})),
        );
        final sealed = cipher.encrypt(
          model: 'User',
          field: 'taxNumber',
          plaintext: 'GB-4471-22',
        );
        expect(sealed, isNot(contains('GB-4471-22')));
        expect(
          cipher.decrypt(model: 'User', field: 'taxNumber', ciphertext: sealed),
          'GB-4471-22',
        );
      },
    );

    test('two writes of the same value differ, so equal columns do not leak '
        'equal plaintext', () {
      final cipher = DVFieldCipher(
        DVFieldKeyring.parse(_keyring({'k1': _key(1)})),
      );
      final a = cipher.encrypt(
        model: 'User',
        field: 'taxNumber',
        plaintext: 'same',
      );
      final b = cipher.encrypt(
        model: 'User',
        field: 'taxNumber',
        plaintext: 'same',
      );
      expect(a, isNot(b));
    });

    test('a ciphertext moved to another column will not open', () {
      final cipher = DVFieldCipher(
        DVFieldKeyring.parse(_keyring({'k1': _key(1)})),
      );
      final sealed = cipher.encrypt(
        model: 'User',
        field: 'taxNumber',
        plaintext: 'GB-4471-22',
      );
      expect(
        () => cipher.decrypt(
          model: 'User',
          field: 'recoveryToken',
          ciphertext: sealed,
        ),
        throwsA(isA<DVFieldDecryptionFailure>()),
      );
      expect(
        () => cipher.decrypt(
          model: 'Invoice',
          field: 'taxNumber',
          ciphertext: sealed,
        ),
        throwsA(isA<DVFieldDecryptionFailure>()),
      );
    });

    test('a tampered ciphertext raises instead of returning a value', () {
      final cipher = DVFieldCipher(
        DVFieldKeyring.parse(_keyring({'k1': _key(1)})),
      );
      final sealed = cipher.encrypt(
        model: 'User',
        field: 'taxNumber',
        plaintext: 'GB-4471-22',
      );
      final parts = sealed.split(':');
      final raw = base64Decode(parts[2]);
      raw[raw.length - 1] ^= 0x01;
      final tampered = '${parts[0]}:${parts[1]}:${base64Encode(raw)}';
      expect(
        () => cipher.decrypt(
          model: 'User',
          field: 'taxNumber',
          ciphertext: tampered,
        ),
        throwsA(isA<DVFieldDecryptionFailure>()),
      );
    });

    test(
      'a plaintext column raises rather than being read as its own value',
      () {
        final cipher = DVFieldCipher(
          DVFieldKeyring.parse(_keyring({'k1': _key(1)})),
        );
        expect(
          () => cipher.decrypt(
            model: 'User',
            field: 'taxNumber',
            ciphertext: 'GB-4471-22',
          ),
          throwsA(isA<DVFieldDecryptionFailure>()),
        );
      },
    );

    test(
      'rotation writes under the newest key and still reads the old one',
      () {
        final old = DVFieldCipher(
          DVFieldKeyring.parse(_keyring({'k1': _key(1)})),
        );
        final sealed = old.encrypt(
          model: 'User',
          field: 'taxNumber',
          plaintext: 'GB-4471-22',
        );

        final rotated = DVFieldCipher(
          DVFieldKeyring.parse(_keyring({'k2': _key(2), 'k1': _key(1)})),
        );
        expect(
          rotated.decrypt(
            model: 'User',
            field: 'taxNumber',
            ciphertext: sealed,
          ),
          'GB-4471-22',
        );
        final rewritten = rotated.encrypt(
          model: 'User',
          field: 'taxNumber',
          plaintext: 'GB-4471-22',
        );
        expect(rewritten.split(':')[1], 'k2');
        expect(
          () => old.decrypt(
            model: 'User',
            field: 'taxNumber',
            ciphertext: rewritten,
          ),
          throwsA(isA<DVFieldDecryptionFailure>()),
        );
      },
    );

    test('a retired key names itself, so an operator can put it back', () {
      final old = DVFieldCipher(
        DVFieldKeyring.parse(_keyring({'k1': _key(1)})),
      );
      final sealed = old.encrypt(
        model: 'User',
        field: 'taxNumber',
        plaintext: 'GB-4471-22',
      );
      final without = DVFieldCipher(
        DVFieldKeyring.parse(_keyring({'k2': _key(2)})),
      );
      expect(
        () => without.decrypt(
          model: 'User',
          field: 'taxNumber',
          ciphertext: sealed,
        ),
        throwsA(
          isA<DVFieldDecryptionFailure>().having(
            (DVFieldDecryptionFailure e) => e.toString(),
            'toString',
            contains('k1'),
          ),
        ),
      );
    });

    test('failure text carries neither key material nor the value', () {
      final keyBytes = _key(1);
      final cipher = DVFieldCipher(
        DVFieldKeyring.parse(_keyring({'k1': keyBytes})),
      );
      final sealed = cipher.encrypt(
        model: 'User',
        field: 'taxNumber',
        plaintext: 'GB-4471-22',
      );
      try {
        cipher.decrypt(
          model: 'User',
          field: 'recoveryToken',
          ciphertext: sealed,
        );
        fail('expected a decryption failure');
      } on DVFieldDecryptionFailure catch (error) {
        final String text = error.toString();
        expect(text, contains('User'));
        expect(text, contains('recoveryToken'));
        expect(text, isNot(contains(base64Encode(keyBytes))));
        expect(text, isNot(contains(sealed)));
      }
    });
  });

  group('DVFieldKeyring', () {
    test('a key that is not 32 bytes is refused, not padded', () {
      expect(
        () =>
            DVFieldKeyring.parse('k1:${base64Encode(List<int>.filled(16, 7))}'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an empty keyring is refused', () {
      expect(() => DVFieldKeyring.parse('   '), throwsA(isA<ArgumentError>()));
    });

    test('a repeated key id is refused, because decryption would pick one of '
        'two keys by position', () {
      expect(
        () => DVFieldKeyring.parse(
          '${_keyring({'k1': _key(1)})},k1:${base64Encode(_key(2))}',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'an entry with no key id is refused, since rotation needs a label',
      () {
        expect(
          () => DVFieldKeyring.parse(base64Encode(_key(1))),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('a parse failure does not put the offending value in its message', () {
      final String secret = base64Encode(_key(1));
      try {
        DVFieldKeyring.parse('k1:$secret,k1:$secret');
        fail('expected a refusal');
      } on ArgumentError catch (error) {
        expect(error.toString(), isNot(contains(secret)));
      }
    });
  });

  group('DVFieldEncryption', () {
    test('an encrypted field with no configured key refuses rather than '
        'writing plaintext', () {
      expect(
        () => DVFieldEncryption.encrypt('User', 'taxNumber', 'GB-4471-22'),
        throwsA(
          isA<DVFieldEncryptionUnavailable>().having(
            (DVFieldEncryptionUnavailable e) => e.toString(),
            'toString',
            allOf(
              contains(DVFieldEncryption.secretName),
              contains('User'),
              contains('taxNumber'),
              isNot(contains('GB-4471-22')),
            ),
          ),
        ),
      );
    });

    test('the key is read from the server secret, never from a constant', () {
      DVSecrets.configure(<String, String>{
        DVFieldEncryption.secretName: _keyring({'k1': _key(1)}),
      });
      final String sealed = DVFieldEncryption.encrypt(
        'User',
        'taxNumber',
        'GB-4471-22',
      )!;
      expect(
        DVFieldEncryption.decrypt('User', 'taxNumber', sealed),
        'GB-4471-22',
      );
    });

    test('null stays null, so an optional field is not stored as a ciphertext '
        'of the empty string', () {
      DVSecrets.configure(<String, String>{
        DVFieldEncryption.secretName: _keyring({'k1': _key(1)}),
      });
      expect(DVFieldEncryption.encrypt('User', 'taxNumber', null), isNull);
      expect(DVFieldEncryption.decrypt('User', 'taxNumber', null), isNull);
    });

    test('rotating the secret takes effect without a restart', () {
      DVSecrets.configure(<String, String>{
        DVFieldEncryption.secretName: _keyring({'k1': _key(1)}),
      });
      final String sealed = DVFieldEncryption.encrypt(
        'User',
        'taxNumber',
        'GB-4471-22',
      )!;

      DVSecrets.configure(<String, String>{
        DVFieldEncryption.secretName: _keyring({'k2': _key(2), 'k1': _key(1)}),
      });
      expect(
        DVFieldEncryption.decrypt('User', 'taxNumber', sealed),
        'GB-4471-22',
      );
      expect(
        DVFieldEncryption.encrypt(
          'User',
          'taxNumber',
          'GB-4471-22',
        )!.split(':')[1],
        'k2',
      );
    });

    test('a host can supply the cipher directly instead of through the '
        'environment', () {
      DVFieldEncryption.configure(
        DVFieldCipher(DVFieldKeyring.parse(_keyring({'k1': _key(3)}))),
      );
      final String sealed = DVFieldEncryption.encrypt(
        'User',
        'taxNumber',
        'GB-4471-22',
      )!;
      expect(
        DVFieldEncryption.decrypt('User', 'taxNumber', sealed),
        'GB-4471-22',
      );
    });

    test('a malformed secret refuses without echoing the secret', () {
      DVSecrets.configure(<String, String>{
        DVFieldEncryption.secretName: 'k1:not-base-64!!',
      });
      try {
        DVFieldEncryption.encrypt('User', 'taxNumber', 'GB-4471-22');
        fail('expected a refusal');
      } on DVFieldEncryptionUnavailable catch (error) {
        expect(error.toString(), contains(DVFieldEncryption.secretName));
        expect(error.toString(), isNot(contains('not-base-64')));
      }
    });
  });
}
