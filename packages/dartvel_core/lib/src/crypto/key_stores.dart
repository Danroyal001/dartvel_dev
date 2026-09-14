/// Where the application key is kept, chosen by what answers.
///
/// The spec's table names a custody per platform; this is the part of it
/// Dartvel has built, and [describe] says which store a key is actually in
/// so nobody assumes keyring protection they do not have.
library;

import 'app_key.dart';
import 'file_key_store_unsupported.dart'
    if (dart.library.io) 'file_key_store_io.dart';
import 'key_custody.dart';
import 'platform_key_stores_unsupported.dart'
    if (dart.library.ffi) 'platform_key_stores_io.dart';
import 'secret_service_key_store_unsupported.dart'
    if (dart.library.ffi) 'secret_service_key_store_io.dart';

export 'file_key_store_unsupported.dart'
    if (dart.library.io) 'file_key_store_io.dart';
export 'key_custody.dart';
export 'platform_key_stores_unsupported.dart'
    if (dart.library.ffi) 'platform_key_stores_io.dart';
export 'secret_service_key_store_unsupported.dart'
    if (dart.library.ffi) 'secret_service_key_store_io.dart';

class DVAppKeyStores {
  DVAppKeyStores._();

  /// The store for [app] on [platform] (`linux`, `macos`, `windows`, ...),
  /// given whether a Secret Service answers. Pure, so it can be tested for
  /// every machine from one.
  static DVAppKeyStore choose({
    required String app,
    required String home,
    required String platform,
    required bool secretService,
    DVAppKeyStore Function(String app)? androidKeystore,
  }) {
    if (platform == 'linux' && secretService) {
      return DVSecretServiceAppKeyStore(service: 'dartvel/$app', account: app);
    }
    if (platform == 'windows') {
      // The blob is sealed to the user, so where it sits matters less than
      // that it sits in the user's own profile.
      final String sep = home.contains('\\') ? '\\' : '/';
      return DVDpapiAppKeyStore('$home${sep}AppData${sep}Local${sep}dartvel${sep}keys$sep$app.key');
    }
    if (platform == 'macos') {
      return DVKeychainAppKeyStore(service: 'dartvel/$app', account: app);
    }
    // Phones: the keyring or a refusal, never the file. The file is still
    // named, as the place an earlier version kept the key, so a key already
    // there is moved in rather than replaced.
    if (platform == 'ios' || platform == 'android') {
      final String old = legacyFilePath(app: app, home: home);
      final DVAppKeyStore keyring = platform == 'ios'
          ? DVKeychainAppKeyStore(service: 'dartvel/$app', account: app)
          : androidKeystore?.call(app) ??
              const DVUnavailableAppKeyStore(
                'the Android Keystore',
                'no Android Keystore binding is linked into this process; '
                    "dartvel_flutter's dvAppKeyStoreFor supplies one",
              );
      return DVMigratingAppKeyStore(
        keyring: keyring,
        legacy: DVFileAppKeyStore(old),
        legacyDescription: old,
      );
    }
    return DVFileAppKeyStore(legacyFilePath(app: app, home: home));
  }

  /// The file the key is kept in where no keyring answers -- and, on Android
  /// and iOS, where an earlier version kept it.
  static String legacyFilePath({required String app, required String home}) =>
      '$home/.dartvel/keys/$app.key';

  /// The store for [app] on this machine: the Secret Service when one
  /// answers, else the file under [home] (the user's by default). This is
  /// what a running application hands to `DVAppKey.ensure` at first start,
  /// so the key is generated per install and per user into custody the OS
  /// protects, and never held only in memory.
  static Future<DVAppKeyStore> platform(
    String app, {
    String? home,
    bool? secretService,
    String? platform,
    DVAppKeyStore Function(String app)? androidKeystore,
  }) async {
    final String os = platform ?? dvHostOperatingSystem();
    return choose(
      app: app,
      home: home ?? dvHostHome() ?? '.',
      platform: os,
      // Only Linux asks: elsewhere the answer changes nothing, and asking
      // loads libsecret for no reason.
      secretService: os != 'linux'
          ? false
          : secretService ?? await DVSecretServiceAppKeyStore.isAvailable(),
      androidKeystore: androidKeystore,
    );
  }

  /// Where a key in [store] actually is, in words an operator can act on.
  static String describe(DVAppKeyStore store) {
    if (store is DVMigratingAppKeyStore) {
      final String where = store.legacyDescription ?? 'the earlier key file';
      return '${describe(store.keyring)}; a key an earlier version kept in '
          '$where is moved in on first read, and that file is removed once '
          'the keyring copy reads back';
    }
    if (store is DVDescribedAppKeyStore) return store.description;
    if (store is DVSecretServiceAppKeyStore) {
      return 'the Secret Service (libsecret), keyring-backed, as ${store.service}';
    }
    if (store is DVDpapiAppKeyStore) {
      return 'a DPAPI-protected blob, sealed to this user on this machine, at ${store.path}';
    }
    if (store is DVKeychainAppKeyStore) {
      return 'the Keychain, as ${store.service} for ${store.account}';
    }
    if (store is DVFileAppKeyStore) {
      return 'a file only this user can read, ${store.path} -- no platform '
          'key store answered, so the key is not keyring-protected';
    }
    return store.runtimeType.toString();
  }
}
