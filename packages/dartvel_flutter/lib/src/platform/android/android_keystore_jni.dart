/// The application key in the Android Keystore.
///
/// JNI through jnigen-generated bindings, per the native integration rule --
/// never a platform channel.
///
/// The application key is 32 raw bytes that AES-GCM in Dart uses directly, so
/// it cannot itself be a Keystore key: a key generated inside AndroidKeyStore
/// never hands out its bytes, which is the point of it. So there are two keys.
/// An AES-256 key is generated inside the Keystore under a per-application
/// alias and never leaves it; the application key is sealed under it with
/// AES/GCM/NoPadding, and what reaches storage is the Keystore's nonce and the
/// sealed bytes, in the application's no-backup directory. Copied off the
/// device, that file opens under nothing.
///
/// Nothing here falls back. With no Context, no Keystore, or a Keystore that
/// refuses, every call throws [DVAppKeyStoreUnavailable], and whatever the key
/// would have sealed is refused by its caller instead.
library dartvel_flutter.platform.android.keystore;

// Prefixed: the generated java.io.File below is also called File, and its
// members (absolutePath) are only reachable with that library imported.
import 'dart:io' as io show File, Platform;
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart'
    show DVAppKey, DVAppKeyStoreUnavailable, DVDescribedAppKeyStore;
import 'package:jni/jni.dart';

import 'android_bindings_jni.dart' show DVAndroidBindings;
import 'android_keystore_shapes.dart';
import 'generated/android/content/Context.dart';
import 'generated/android/security/keystore/KeyGenParameterSpec.dart';
import 'generated/android/security/keystore/KeyProperties.dart';
import 'generated/java/io/File.dart';
import 'generated/java/security/Key.dart';
import 'generated/java/security/KeyStore.dart';
import 'generated/javax/crypto/Cipher.dart';
import 'generated/javax/crypto/KeyGenerator.dart';
import 'generated/javax/crypto/SecretKey.dart';
import 'generated/javax/crypto/spec/GCMParameterSpec.dart';

const String _store = 'the Android Keystore';

class DVAndroidKeystoreAppKeyStore implements DVDescribedAppKeyStore {
  /// The application the key belongs to; names the alias and the file.
  final String app;

  const DVAndroidKeystoreAppKeyStore({required this.app});

  /// The Keystore alias of the key that seals this application's key.
  String get alias => dvAndroidKeystoreAlias(app);

  @override
  String get description {
    final String? where = sealedPath;
    return 'the Android Keystore, where an AES-256 key ($alias) that never '
        'leaves it seals the application key'
        '${where == null ? '' : ', kept sealed at $where'}';
  }

  /// Where the sealed key is kept, or null with no application Context.
  String? get sealedPath {
    final Context? context = _context();
    if (context == null) return null;
    final File? dir = context.noBackupFilesDir;
    return dvAndroidSealedKeyPath(
      dir?.absolutePath?.toDartString(releaseOriginal: true),
      app,
    );
  }

  static Context? _context() {
    if (!io.Platform.isAndroid) return null;
    try {
      return DVAndroidBindings.applicationContext;
    } on Object {
      return null;
    }
  }

  static DVAppKeyStoreUnavailable _refuse(String reason, [Object? cause]) =>
      DVAppKeyStoreUnavailable(_store, reason, cause: cause);

  /// The sealed key's path, or the refusal that says why there is none.
  String _requirePath() {
    if (!io.Platform.isAndroid) {
      throw _refuse('there is no Android Keystore on ${io.Platform.operatingSystem}');
    }
    if (_context() == null) {
      throw _refuse('there is no application Context, so the sealed key has '
          'nowhere to be kept (${DVAndroidBindings.lastFailure ?? 'no reason was given'})');
    }
    final String? path = sealedPath;
    if (path == null) throw _refuse('the application has no no-backup directory');
    return path;
  }

  /// The loaded AndroidKeyStore, or the refusal.
  static KeyStore _keystore() {
    try {
      final KeyStore? keystore = KeyStore.getInstance(dvAndroidKeystoreProvider.toJString());
      if (keystore == null) throw _refuse('the $dvAndroidKeystoreProvider provider is not on this device');
      keystore.load(null, null);
      return keystore;
    } on DVAppKeyStoreUnavailable {
      rethrow;
    } on Object catch (error) {
      throw _refuse('the $dvAndroidKeystoreProvider provider could not be loaded', error);
    }
  }

  SecretKey? _secret(KeyStore keystore) {
    final Key? key = keystore.getKey(alias.toJString(), null);
    return key?.as(SecretKey.type);
  }

  /// A new AES-256 key inside the Keystore, for GCM without padding.
  SecretKey _generate() {
    final KeyGenerator? generator = KeyGenerator.getInstance$1(
      'AES'.toJString(),
      dvAndroidKeystoreProvider.toJString(),
    );
    if (generator == null) throw _refuse('the Keystore will not generate AES keys');
    final KeyGenParameterSpec? spec = KeyGenParameterSpec$Builder(
      alias.toJString(),
      KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT,
    )
        .setBlockModes(JArray.of<JString?>(JString.type, <JString?>[KeyProperties.BLOCK_MODE_GCM]))
        ?.setEncryptionPaddings(
            JArray.of<JString?>(JString.type, <JString?>[KeyProperties.ENCRYPTION_PADDING_NONE]))
        ?.setKeySize(256)
        ?.build();
    if (spec == null) throw _refuse('the Keystore key specification could not be built');
    generator.init$1(spec);
    final SecretKey? key = generator.generateKey();
    if (key == null) throw _refuse('the Keystore generated no key');
    return key;
  }

  static Uint8List _bytes(JByteArray? array) {
    if (array == null) return Uint8List(0);
    return Uint8List.fromList(array.getRange(0, array.length));
  }

  @override
  Future<Uint8List?> read() async {
    final String path = _requirePath();
    final io.File file = io.File(path);
    if (!file.existsSync()) return null;
    final ({Uint8List nonce, Uint8List sealed})? opened = dvAndroidOpenKeyBlob(file.readAsStringSync());
    // A damaged file is not this key, the same as a damaged file store.
    if (opened == null) return null;
    final KeyStore keystore = _keystore();
    try {
      final SecretKey? secret = _secret(keystore);
      // The sealing key is gone -- the Keystore was reset -- so the sealed
      // key can never be opened again. Nothing to read.
      if (secret == null) return null;
      final Cipher? cipher = Cipher.getInstance(dvAndroidKeystoreTransformation.toJString());
      if (cipher == null) throw _refuse('$dvAndroidKeystoreTransformation is not available');
      cipher.init$2(
        Cipher.DECRYPT_MODE,
        secret,
        GCMParameterSpec(dvAndroidKeystoreTagBits, JByteArray.of(opened.nonce)),
      );
      final Uint8List key = _bytes(cipher.doFinal$2(JByteArray.of(opened.sealed)));
      return key.length == DVAppKey.lengthBytes ? key : null;
    } on DVAppKeyStoreUnavailable {
      rethrow;
    } on JThrowable catch (error) {
      // A tag that does not verify, or a key the platform has invalidated:
      // not this key, as with any other store that cannot read its value.
      final String what = error.message;
      if (what.contains('AEADBadTagException') || what.contains('KeyPermanentlyInvalidatedException')) {
        return null;
      }
      throw _refuse('the Keystore would not open the sealed application key', error);
    } on Object catch (error) {
      throw _refuse('the Keystore would not open the sealed application key', error);
    }
  }

  @override
  Future<void> write(Uint8List key) async {
    if (key.length != DVAppKey.lengthBytes) {
      throw ArgumentError.value(key.length, 'key', 'An application key is ${DVAppKey.lengthBytes} bytes.');
    }
    final String path = _requirePath();
    final KeyStore keystore = _keystore();
    final String blob;
    try {
      final SecretKey secret = _secret(keystore) ?? _generate();
      final Cipher? cipher = Cipher.getInstance(dvAndroidKeystoreTransformation.toJString());
      if (cipher == null) throw _refuse('$dvAndroidKeystoreTransformation is not available');
      // No nonce is supplied: the Keystore insists on choosing its own for
      // an encryption, and hands it back.
      cipher.init(Cipher.ENCRYPT_MODE, secret);
      final Uint8List sealed = _bytes(cipher.doFinal$2(JByteArray.of(key)));
      final Uint8List nonce = _bytes(cipher.iV);
      // Refuses anything that is not a nonce and a sealed key, so a cipher
      // that handed back its input could not put the key in the file.
      blob = dvAndroidSealKeyBlob(nonce, sealed);
    } on DVAppKeyStoreUnavailable {
      rethrow;
    } on Object catch (error) {
      throw _refuse('the Keystore could not seal the application key', error);
    }
    final io.File file = io.File(path);
    file.parent.createSync(recursive: true);
    // Beside the destination and renamed over it, so a write cut short
    // leaves the previous sealed key rather than half of a new one.
    final io.File partial = io.File('$path.partial');
    partial.writeAsStringSync(blob, flush: true);
    partial.renameSync(path);
  }

  @override
  Future<void> clear() async {
    final String path = _requirePath();
    for (final io.File file in <io.File>[io.File(path), io.File('$path.partial')]) {
      if (file.existsSync()) file.deleteSync();
    }
    final KeyStore keystore = _keystore();
    try {
      final JString name = alias.toJString();
      if (keystore.containsAlias(name)) keystore.deleteEntry(name);
    } on Object catch (error) {
      throw _refuse('the Keystore entry could not be deleted', error);
    }
  }

  /// What the Keystore says about this application's sealing key: whether
  /// it holds an entry (`entry`) and whether that key hands out its bytes
  /// (`exportable`, which must be false). For tests, which have to ask the
  /// platform rather than trust what was asked of it.
  Future<Map<String, Object?>> debugKeystoreFacts() async {
    final KeyStore keystore = _keystore();
    final bool entry = keystore.containsAlias(alias.toJString());
    final SecretKey? secret = entry ? _secret(keystore) : null;
    return <String, Object?>{
      'alias': alias,
      'entry': entry,
      'exportable': secret == null ? null : secret.getEncoded() != null,
    };
  }
}
