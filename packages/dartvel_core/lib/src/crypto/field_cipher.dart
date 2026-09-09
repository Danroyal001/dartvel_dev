import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../secrets/secrets.dart';
import 'app_key.dart';

/// One key an operator has put on the field keyring.
class DVFieldKey {
  /// The label the ciphertext records, so a rotated-out key can be named in
  /// a failure without printing any of its bytes.
  final String id;

  final Uint8List bytes;

  DVFieldKey(this.id, this.bytes) {
    if (!_idPattern.hasMatch(id)) {
      throw ArgumentError.value(
        id,
        'id',
        'A field key id is letters, digits, underscore or hyphen.',
      );
    }
    if (bytes.length != DVAppKey.lengthBytes) {
      throw ArgumentError(
        'The field key "$id" is ${bytes.length} bytes; '
        '${DVAppKey.lengthBytes} are required for AES-256.',
      );
    }
  }

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]+$');

  /// Never the bytes. A key that prints itself ends up in a crash report.
  @override
  String toString() => 'DVFieldKey($id)';
}

/// The keys available to a process for model-field encryption.
///
/// More than one so a key can be rotated without rewriting every row first:
/// the head of the ring encrypts, and every entry can decrypt. An operator
/// rotates by putting the new key at the front, leaving the old one behind
/// it, and drops the old entry once nothing is still sealed under it.
class DVFieldKeyring {
  final List<DVFieldKey> keys;

  DVFieldKeyring(this.keys) {
    if (keys.isEmpty) {
      throw ArgumentError.value(
        keys,
        'keys',
        'A keyring needs at least one key.',
      );
    }
    final ids = <String>{};
    for (final DVFieldKey key in keys) {
      if (!ids.add(key.id)) {
        throw ArgumentError(
          'The field key id "${key.id}" appears twice. Decryption picks a key '
          'by id, so two keys under one id means values sealed under the '
          'second can never be opened.',
        );
      }
    }
  }

  /// The key new values are sealed under.
  DVFieldKey get writeKey => keys.first;

  DVFieldKey? byId(String id) {
    for (final DVFieldKey key in keys) {
      if (key.id == id) return key;
    }
    return null;
  }

  /// Reads `id:base64key` entries separated by commas or whitespace, newest
  /// first.
  ///
  /// Parse errors deliberately never quote the offending text: the text is
  /// the key, and an operator debugging a typo should not have to weigh
  /// whether the error they are about to paste into a ticket contains it.
  static DVFieldKeyring parse(String value) {
    final List<String> entries = value
        .split(RegExp(r'[,\s]+'))
        .map((String entry) => entry.trim())
        .where((String entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (entries.isEmpty) {
      throw ArgumentError('No field keys were found in the value provided.');
    }
    final keys = <DVFieldKey>[];
    for (var i = 0; i < entries.length; i++) {
      final int separator = entries[i].indexOf(':');
      if (separator <= 0) {
        throw ArgumentError(
          'Field key ${i + 1} of ${entries.length} has no id. Each entry is '
          'written as <id>:<base64 32-byte key>, and the id is what a stored '
          'value records so it can still be opened after a rotation.',
        );
      }
      final String id = entries[i].substring(0, separator);
      Uint8List bytes;
      try {
        bytes = base64Decode(entries[i].substring(separator + 1));
      } on FormatException {
        throw ArgumentError('The field key "$id" is not valid base64.');
      }
      keys.add(DVFieldKey(id, bytes));
    }
    return DVFieldKeyring(keys);
  }

  @override
  String toString() =>
      'DVFieldKeyring(${keys.map((DVFieldKey k) => k.id).join(', ')})';
}

/// Thrown when a stored field cannot be opened.
///
/// Unlike [DVAppKeyCipher], which returns null because the value it protects
/// is view state a user can lose, this raises. A national ID that silently
/// reads back as null looks like a row that never had one, and the code
/// downstream then writes that absence back over the real value.
class DVFieldDecryptionFailure implements Exception {
  final String model;
  final String field;
  final String reason;

  const DVFieldDecryptionFailure({
    required this.model,
    required this.field,
    required this.reason,
  });

  @override
  String toString() =>
      'DVFieldDecryptionFailure: $model.$field could not be decrypted — '
      '$reason';
}

/// Thrown when an encrypted field is read or written and the process has no
/// usable keyring.
class DVFieldEncryptionUnavailable implements Exception {
  final String model;
  final String field;
  final String reason;

  const DVFieldEncryptionUnavailable({
    required this.model,
    required this.field,
    required this.reason,
  });

  @override
  String toString() =>
      'DVFieldEncryptionUnavailable: $model.$field is declared '
      '@DVModel.sensitiveField(encrypted: true) and no field encryption key '
      'is available — $reason';
}

/// AES-256-GCM over a server-held keyring, for model fields stored in a
/// database.
///
/// Separate from [DVAppKeyCipher] because the threat models do not overlap.
/// That key belongs to one device and is held by the OS key store of the
/// person using it; this one belongs to a server process and protects rows
/// that many people's requests read. Handing either job to the other key is
/// how a device key ends up in a shared database, or a server key in an
/// application bundle.
///
/// The column and the model name are authenticated alongside the value, so a
/// ciphertext copied into a different column, or into the same column of a
/// different model's table, fails to open rather than decrypting into a place
/// it was never written for. It does not bind the row: an attacker who can
/// write to the database can still swap two rows' values within one column,
/// and stopping that needs a per-row identity that survives an update, which
/// a generated model does not currently have.
class DVFieldCipher {
  /// 96 bits, the nonce size AES-GCM is specified for.
  static const int nonceBytes = 12;
  static const int macBits = 128;

  /// Version tag. A stored value carries it so a future format can be told
  /// apart from this one rather than being fed to the wrong reader.
  static const String prefix = 'dvf1';

  final DVFieldKeyring keyring;
  final Random _random;

  DVFieldCipher(this.keyring, {Random? random})
    : _random = random ?? Random.secure();

  /// Seals [plaintext] as `dvf1:<key id>:<base64 nonce||ciphertext>`.
  ///
  /// A fresh nonce per write, so two rows holding the same value do not hold
  /// the same bytes — otherwise the column leaks equality, which for
  /// something like a national ID is most of what it was hidden for.
  String encrypt({
    required String model,
    required String field,
    required String plaintext,
  }) {
    final DVFieldKey key = keyring.writeKey;
    final nonce = Uint8List(nonceBytes);
    for (var i = 0; i < nonceBytes; i++) {
      nonce[i] = _random.nextInt(256);
    }
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key.bytes),
          macBits,
          nonce,
          _associatedData(model, field),
        ),
      );
    final sealed = cipher.process(Uint8List.fromList(utf8.encode(plaintext)));
    return '$prefix:${key.id}:${base64Encode(<int>[...nonce, ...sealed])}';
  }

  /// Opens a value written by [encrypt] for the same model and column.
  String decrypt({
    required String model,
    required String field,
    required String ciphertext,
  }) {
    final List<String> parts = ciphertext.split(':');
    if (parts.length != 3 || parts[0] != prefix) {
      throw DVFieldDecryptionFailure(
        model: model,
        field: field,
        reason:
            'the stored value is not in Dartvel field-encryption format, '
            'which is what a column written before encrypted: true was '
            'declared looks like; those rows have to be rewritten',
      );
    }
    final DVFieldKey? key = keyring.byId(parts[1]);
    if (key == null) {
      throw DVFieldDecryptionFailure(
        model: model,
        field: field,
        reason:
            'it was sealed under key "${parts[1]}", which is not on the '
            'keyring; put that key back to read the row, or rewrite the row '
            'under a current key',
      );
    }
    try {
      final raw = base64Decode(parts[2]);
      if (raw.length <= nonceBytes) {
        throw const FormatException('short');
      }
      final nonce = Uint8List.fromList(raw.sublist(0, nonceBytes));
      final sealed = Uint8List.fromList(raw.sublist(nonceBytes));
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(key.bytes),
            macBits,
            nonce,
            _associatedData(model, field),
          ),
        );
      return utf8.decode(cipher.process(sealed));
    } on Object {
      // Nothing from the failure is repeated back. A GCM tag check fails the
      // same way for a tampered value, a wrong column and a wrong key, and
      // the bytes that would distinguish them are the ones worth not
      // logging.
      throw DVFieldDecryptionFailure(
        model: model,
        field: field,
        reason:
            'authentication failed under key "${parts[1]}" — the value '
            'was altered, or it was written for a different model or column',
      );
    }
  }

  /// Binds a ciphertext to where it was written. GCM authenticates this
  /// without storing it, so moving the value elsewhere breaks the tag.
  static Uint8List _associatedData(String model, String field) =>
      Uint8List.fromList(utf8.encode('$model.$field'));

  @override
  String toString() => 'DVFieldCipher($keyring)';
}

/// How generated models reach the field cipher.
///
/// The keyring is read from the server process environment through
/// [DVSecrets] and never from anything the generator writes. That is the
/// whole point of the split: generated model code is compiled into the
/// application bundle as well as the server, so a key that lived in
/// generated code would ship to every visitor. Only `PUBLIC_`-prefixed values
/// reach the generated environment, and a browser has no environment to read
/// at all, so on the web this resolves to nothing and an encrypted field
/// raises rather than storing plaintext.
class DVFieldEncryption {
  DVFieldEncryption._();

  /// The environment variable holding the keyring, newest key first.
  static const String secretName = 'DARTVEL_FIELD_KEYS';

  static DVFieldCipher? _configured;

  /// The last secret value parsed, with what it parsed to, so a read does not
  /// re-derive the ring on every column. Keyed by the raw value so a rotation
  /// through `DV.Secrets.rotate` takes effect without a restart.
  static String? _cachedSource;
  static DVFieldCipher? _cachedCipher;

  /// Supplies the cipher directly, for a host that loads keys from a manager
  /// rather than the environment, and for tests.
  static void configure(DVFieldCipher? cipher) {
    _configured = cipher;
  }

  /// Drops a configured cipher and the parsed keyring.
  static void reset() {
    _configured = null;
    _cachedSource = null;
    _cachedCipher = null;
  }

  /// Whether an encrypted field can be read or written in this process.
  static bool get isAvailable {
    if (_configured != null) return true;
    final String? source = const DVSecrets().maybeGet(secretName);
    if (source == null) return false;
    try {
      _resolve(source);
      return true;
    } on ArgumentError {
      return false;
    }
  }

  static DVFieldCipher _resolve(String source) {
    if (_cachedSource == source && _cachedCipher != null) return _cachedCipher!;
    final DVFieldCipher cipher = DVFieldCipher(DVFieldKeyring.parse(source));
    _cachedSource = source;
    _cachedCipher = cipher;
    return cipher;
  }

  static DVFieldCipher _cipherFor(String model, String field) {
    final DVFieldCipher? configured = _configured;
    if (configured != null) return configured;
    final String? source = const DVSecrets().maybeGet(secretName);
    if (source == null) {
      throw DVFieldEncryptionUnavailable(
        model: model,
        field: field,
        reason:
            'set $secretName in the server process environment to '
            '<id>:<base64 32-byte key>, newest key first. It must never be '
            'set for a client build: only PUBLIC_ values reach the generated '
            'environment, and a key that ships in a bundle protects nothing',
      );
    }
    try {
      return _resolve(source);
    } on ArgumentError catch (error) {
      throw DVFieldEncryptionUnavailable(
        model: model,
        field: field,
        // error.message, not the ArgumentError's toString: an ArgumentError
        // prints the value it rejected, and here the rejected value is the
        // key.
        reason: '$secretName could not be read — ${error.message}',
      );
    }
  }

  /// Seals [value] for storage. Null passes through, so an optional column
  /// stays empty rather than holding a ciphertext of the empty string that
  /// every `IS NULL` query would then miss.
  static String? encrypt(String model, String field, String? value) {
    if (value == null) return null;
    return _cipherFor(
      model,
      field,
    ).encrypt(model: model, field: field, plaintext: value);
  }

  /// Opens a stored value.
  static String? decrypt(String model, String field, String? value) {
    if (value == null) return null;
    return _cipherFor(
      model,
      field,
    ).decrypt(model: model, field: field, ciphertext: value);
  }
}
