import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Where the application key is kept.
///
/// The key is never in the bundle and never in `pubspec.yaml`: only
/// `PUBLIC_`-prefixed values reach the generated environment, and a key that
/// ships to every visitor encrypts nothing. A server-side framework can keep
/// such a key in an environment file because it lives on a machine the
/// operator controls; an application's store lives on the user's device, so
/// the key has to come from somewhere the user's own OS protects.
///
/// Implementations bind to DPAPI, Keychain, libsecret, Android Keystore, or a
/// non-extractable WebCrypto key. The in-memory implementation is for tests.
abstract class DVAppKeyStore {
  /// The stored key, or null when none has been generated.
  Future<Uint8List?> read();

  /// Stores [key], replacing any previous one.
  Future<void> write(Uint8List key);

  /// Removes the key. The store it protected becomes unreadable, which is
  /// survivable: it holds view state.
  Future<void> clear();
}

/// Holds the key for the lifetime of the process only.
class DVMemoryAppKeyStore implements DVAppKeyStore {
  Uint8List? _key;

  @override
  Future<Uint8List?> read() async => _key;

  @override
  Future<void> write(Uint8List key) async => _key = key;

  @override
  Future<void> clear() async => _key = null;
}

/// The application key: generated once per install and per user, used to
/// encrypt what Dartvel stores at rest on a device.
///
/// Distinct from the server-held secrets in `DV.Secrets`, which encrypt model
/// fields in a database. These are two keys with two threat models, and
/// conflating them is how a device key ends up on a server or a server key in
/// a bundle.
class DVAppKey {
  static const int lengthBytes = 32;

  const DVAppKey._();

  /// Returns the stored key, generating one on first use.
  ///
  /// Generated per install rather than shipped, so it is not a shared secret
  /// and there is nothing to leak into version control.
  static Future<Uint8List> ensure(
    DVAppKeyStore store, {
    Random? random,
  }) async {
    final existing = await store.read();
    if (existing != null && existing.length == lengthBytes) return existing;
    final generated = generate(random: random);
    await store.write(generated);
    return generated;
  }

  /// A fresh key. Uses [Random.secure] unless a source is supplied, which
  /// only tests should do.
  static Uint8List generate({Random? random}) {
    final source = random ?? Random.secure();
    final key = Uint8List(lengthBytes);
    for (var i = 0; i < lengthBytes; i++) {
      key[i] = source.nextInt(256);
    }
    return key;
  }

  /// Re-encrypts [values] under [next], returning the rewritten entries.
  ///
  /// A value that cannot be read under the current key is dropped rather than
  /// failing the rotation: rotation exists to move a store forward, and one
  /// unreadable entry should not strand the rest.
  static Map<String, String> rotate(
    Map<String, String> values, {
    required Uint8List from,
    required Uint8List next,
  }) {
    final current = DVAppKeyCipher(from);
    final replacement = DVAppKeyCipher(next);
    final rewritten = <String, String>{};
    for (final entry in values.entries) {
      final plaintext = current.decrypt(entry.value);
      if (plaintext == null) continue;
      rewritten[entry.key] = replacement.encrypt(plaintext);
    }
    return rewritten;
  }
}

/// AES-256-GCM over the application key.
///
/// Encryption happens before a value reaches any backing store, so the store
/// is a dumb byte sink on every target — one code path and one threat model,
/// rather than depending on encrypted preferences on one platform and
/// `localStorage`, which has no encryption story at all, on another.
class DVAppKeyCipher {
  /// 96 bits, the nonce size AES-GCM is specified for.
  static const int nonceBytes = 12;
  static const int macBits = 128;
  static const String _prefix = 'dv1:';

  final Uint8List _key;
  final Random _random;

  DVAppKeyCipher(this._key, {Random? random})
      : _random = random ?? Random.secure() {
    if (_key.length != DVAppKey.lengthBytes) {
      throw ArgumentError.value(
        _key.length,
        'key',
        'An application key is ${DVAppKey.lengthBytes} bytes.',
      );
    }
  }

  /// Encrypts [plaintext], returning `dv1:<base64 nonce||ciphertext>`.
  ///
  /// A fresh nonce per write: reusing one under the same key is what breaks
  /// GCM, so it is generated here rather than supplied by a caller who might
  /// hold it still.
  String encrypt(String plaintext) {
    final nonce = Uint8List(nonceBytes);
    for (var i = 0; i < nonceBytes; i++) {
      nonce[i] = _random.nextInt(256);
    }
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(_key), macBits, nonce, Uint8List(0)));
    final sealed = cipher.process(
      Uint8List.fromList(utf8.encode(plaintext)),
    );
    return '$_prefix${base64Encode(<int>[...nonce, ...sealed])}';
  }

  /// Returns null when the value cannot be read — a rotated key, a reset
  /// keychain, a profile moved between machines, or a tampered value.
  ///
  /// Null rather than an exception because every caller does the same thing
  /// with an unreadable value: discard it. A store that holds view state
  /// should lose a tab order, not refuse to open.
  String? decrypt(String ciphertext) {
    if (!ciphertext.startsWith(_prefix)) return null;
    try {
      final raw = base64Decode(ciphertext.substring(_prefix.length));
      if (raw.length <= nonceBytes) return null;
      final nonce = Uint8List.fromList(raw.sublist(0, nonceBytes));
      final sealed = Uint8List.fromList(raw.sublist(nonceBytes));
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(_key), macBits, nonce, Uint8List(0)),
        );
      return utf8.decode(cipher.process(sealed));
    } catch (_) {
      return null;
    }
  }
}
