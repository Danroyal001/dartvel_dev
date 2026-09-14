/// What the Android Keystore store decides before it reaches Java, and what
/// it puts on disk.
///
/// Apart from the JNI calls so they can be asserted on a machine with no
/// device -- and because the one property that matters most here, that what
/// reaches storage is a sealed key and never the key, is a property of these
/// functions.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The provider whose keys never leave secure storage.
const String dvAndroidKeystoreProvider = 'AndroidKeyStore';

/// How the application key is sealed under the Keystore key.
const String dvAndroidKeystoreTransformation = 'AES/GCM/NoPadding';

/// The GCM nonce the Keystore generates for an encryption, in bytes.
const int dvAndroidKeystoreNonceBytes = 12;

/// The GCM tag, in bits and bytes.
const int dvAndroidKeystoreTagBits = 128;
const int _tagBytes = dvAndroidKeystoreTagBits ~/ 8;

/// A sealed application key: 32 bytes of key and the tag on them.
const int dvAndroidSealedKeyBytes = 32 + _tagBytes;

const String _blobPrefix = 'dvks1:';

/// The Keystore alias of [app]'s wrapping key. One per application, so two
/// Dartvel applications in one process never share a key.
String dvAndroidKeystoreAlias(String app) => 'dartvel.appkey.$app';

/// Where [app]'s sealed key is kept, given the application's no-backup
/// directory; null when there is none.
///
/// No-backup, because the Keystore key the blob is sealed under does not
/// leave the device: a blob restored onto another phone can never be opened,
/// and would only turn a clean first start into a failed read.
String? dvAndroidSealedKeyPath(String? noBackupDir, String app) {
  if (noBackupDir == null || noBackupDir.isEmpty) return null;
  String base = noBackupDir;
  while (base.length > 1 && base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  // An application name is not a path.
  final String name = app.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return '$base/dartvel-keys/$name.sealed';
}

/// The text kept on disk for a key sealed as [sealed] under [nonce].
///
/// Refuses anything that is not a nonce and a sealed key. A 32-byte
/// [sealed] is an application key with no tag on it -- the key itself --
/// and a store that tried to write one would otherwise put it in a file.
String dvAndroidSealKeyBlob(Uint8List nonce, Uint8List sealed) {
  if (nonce.length != dvAndroidKeystoreNonceBytes) {
    throw ArgumentError.value(nonce.length, 'nonce', 'a GCM nonce is $dvAndroidKeystoreNonceBytes bytes');
  }
  if (sealed.length != dvAndroidSealedKeyBytes) {
    throw ArgumentError.value(sealed.length, 'sealed',
        'a sealed application key is $dvAndroidSealedKeyBytes bytes (key and tag)');
  }
  return '$_blobPrefix${base64Encode(<int>[...nonce, ...sealed])}';
}

/// The nonce and sealed key in [blob], or null when it is not one.
({Uint8List nonce, Uint8List sealed})? dvAndroidOpenKeyBlob(String blob) {
  final String text = blob.trim();
  if (!text.startsWith(_blobPrefix)) return null;
  final Uint8List raw;
  try {
    raw = base64Decode(text.substring(_blobPrefix.length));
  } on FormatException {
    return null;
  }
  if (raw.length != dvAndroidKeystoreNonceBytes + dvAndroidSealedKeyBytes) return null;
  return (
    nonce: Uint8List.fromList(raw.sublist(0, dvAndroidKeystoreNonceBytes)),
    sealed: Uint8List.fromList(raw.sublist(dvAndroidKeystoreNonceBytes)),
  );
}
