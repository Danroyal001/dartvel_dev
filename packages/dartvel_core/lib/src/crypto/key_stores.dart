/// Where the application key is kept, chosen by what answers.
///
/// The spec's table names a custody per platform; this is the part of it
/// Dartvel has built, and [describe] says which store a key is actually in
/// so nobody assumes keyring protection they do not have.
library;

import 'app_key.dart';
import 'file_key_store_unsupported.dart'
    if (dart.library.io) 'file_key_store_io.dart';
import 'secret_service_key_store_unsupported.dart'
    if (dart.library.ffi) 'secret_service_key_store_io.dart';

export 'file_key_store_unsupported.dart'
    if (dart.library.io) 'file_key_store_io.dart';
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
  }) {
    if (platform == 'linux' && secretService) {
      return DVSecretServiceAppKeyStore(service: 'dartvel/$app', account: app);
    }
    return DVFileAppKeyStore('$home/.dartvel/keys/$app.key');
  }

  /// Where a key in [store] actually is, in words an operator can act on.
  static String describe(DVAppKeyStore store) {
    if (store is DVSecretServiceAppKeyStore) {
      return 'the Secret Service (libsecret), keyring-backed, as ${store.service}';
    }
    if (store is DVFileAppKeyStore) {
      return 'a file only this user can read, ${store.path} -- no platform '
          'key store answered, so the key is not keyring-protected';
    }
    return store.runtimeType.toString();
  }
}
