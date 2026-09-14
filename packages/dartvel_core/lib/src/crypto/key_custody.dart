/// Key custody where the platform has a keyring and nothing else will do.
///
/// On a phone the application key goes into the Android Keystore or the iOS
/// Keychain, or it is refused. There is no file fallback there: a key in a
/// file under the app's home is readable by anything that can read the
/// sandbox -- a backup, a rooted device, a debugger attached to a debuggable
/// build -- and the keyring is the only custody those platforms offer against
/// that. A store that cannot answer throws [DVAppKeyStoreUnavailable], and
/// whatever the key would have sealed is refused by its caller instead.
library;

import 'dart:typed_data';

import 'app_key.dart';

/// The platform key store could not hold or give up the application key.
///
/// Typed so a caller can tell "the keyring refused" from every other fault,
/// and so nobody is tempted to catch it and write the key somewhere else:
/// the right response is to refuse what the key would have protected.
class DVAppKeyStoreUnavailable implements Exception {
  /// The store that was asked, in words: `the Keychain`, `the Android
  /// Keystore`.
  final String store;

  /// Why it could not answer, in words an operator can act on.
  final String reason;

  /// The platform's own status code, when it gave one (an `OSStatus` from the
  /// Keychain, say).
  final int? status;

  /// The underlying error, when there was one.
  final Object? cause;

  const DVAppKeyStoreUnavailable(
    this.store,
    this.reason, {
    this.status,
    this.cause,
  });

  @override
  String toString() {
    final StringBuffer out = StringBuffer(
        'DVAppKeyStoreUnavailable: $store cannot hold the application key: '
        '$reason');
    if (status != null) out.write(' (status $status)');
    if (cause != null) out.write(' ($cause)');
    return out.toString();
  }
}

/// A store that can say where it keeps the key.
///
/// For stores defined outside this package -- the Android Keystore store is
/// in dartvel_flutter, beside the JNI bindings it needs -- so
/// `DVAppKeyStores.describe` does not fall back to a class name.
abstract interface class DVDescribedAppKeyStore implements DVAppKeyStore {
  String get description;
}

/// A platform with a keyring and no binding to it in this process.
///
/// Every call refuses. It stands where the file store used to, so the absence
/// of a binding is a refusal with a reason rather than a key on disk.
class DVUnavailableAppKeyStore implements DVDescribedAppKeyStore {
  final String store;
  final String reason;

  const DVUnavailableAppKeyStore(this.store, this.reason);

  DVAppKeyStoreUnavailable get _refusal =>
      DVAppKeyStoreUnavailable(store, reason);

  @override
  String get description =>
      'no key store: $store is not reachable here ($reason), so the key is '
      'refused rather than kept in a file';

  @override
  Future<Uint8List?> read() async => throw _refusal;

  @override
  Future<void> write(Uint8List key) async => throw _refusal;

  @override
  Future<void> clear() async => throw _refusal;
}

/// The keyring, reading once from where an earlier version kept the key.
///
/// Dartvel used to keep the key on Android and iOS in a file under the home
/// directory. Data sealed under that key has to stay readable, so the key is
/// moved rather than replaced: on the first read that finds the keyring empty
/// and the file present, the key is written to [keyring], read back, and the
/// file is removed only once the copy compares equal. A keyring that refuses
/// or drops the write leaves the file where it was and throws, so a failed
/// move loses nothing and is tried again on the next start.
///
/// Nothing is ever written to [legacy]. Writes go to the keyring alone.
class DVMigratingAppKeyStore implements DVAppKeyStore {
  final DVAppKeyStore keyring;

  /// Where an earlier version kept the key: read, then removed; never written.
  final DVAppKeyStore legacy;

  /// Where [legacy] is, for [DVAppKeyStores.describe]; null when unknown.
  final String? legacyDescription;

  const DVMigratingAppKeyStore({
    required this.keyring,
    required this.legacy,
    this.legacyDescription,
  });

  @override
  Future<Uint8List?> read() async {
    // The keyring first, and its refusal propagates: a keyring that cannot
    // answer is never a reason to use the file.
    final Uint8List? held = await keyring.read();
    if (held != null) {
      // A move interrupted between the read-back and the delete leaves both.
      // Finish it -- but only for the same key. A file holding a different
      // key may be the only copy of something still sealed under it.
      final Uint8List? old = await legacy.read();
      if (old != null && _same(old, held)) await legacy.clear();
      return held;
    }

    final Uint8List? old = await legacy.read();
    if (old == null) return null;

    await keyring.write(old);
    final Uint8List? back = await keyring.read();
    if (back == null || !_same(back, old)) {
      throw DVAppKeyStoreUnavailable(
        'the platform key store',
        'the key from ${legacyDescription ?? 'the earlier key file'} was '
            'written to the keyring and did not read back '
            '${back == null ? 'at all' : 'the same'}; the file was kept, and '
            'the move is tried again next time',
      );
    }
    // Only now, with a copy the keyring has given back.
    await legacy.clear();
    return back;
  }

  @override
  Future<void> write(Uint8List key) => keyring.write(key);

  @override
  Future<void> clear() async {
    // Both, and the file even when the keyring refuses: clearing is asking for
    // the key to be gone, and the part that can go should.
    Object? refused;
    StackTrace? trace;
    try {
      await keyring.clear();
    } catch (error, stackTrace) {
      refused = error;
      trace = stackTrace;
    }
    await legacy.clear();
    if (refused != null) Error.throwWithStackTrace(refused, trace!);
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

const int _errSecNotAvailable = -25291;
const int _errSecInteractionNotAllowed = -25308;
const int _errSecAuthFailed = -25293;
const int _errSecMissingEntitlement = -34018;

/// The refusal for a Keychain [operation] that answered [status].
///
/// Pure, so the wording for each status is tested off a Mac. The statuses
/// named are the ones a running application meets: a device that has not
/// been unlocked since it booted (the item is available after first unlock),
/// a process with no keychain entitlement, and a machine with no keychain.
DVAppKeyStoreUnavailable dvKeychainRefusal(int status, String operation) {
  final String reason = switch (status) {
    _errSecInteractionNotAllowed =>
      'the device has not been unlocked since it started, and the key is '
          'kept for after first unlock; $operation was refused',
    _errSecMissingEntitlement =>
      'this process has no keychain entitlement, so $operation was refused; '
          'a signed application has one, an unsigned test host may not',
    _errSecNotAvailable =>
      'there is no keychain available to this process; $operation was refused',
    _errSecAuthFailed =>
      'the keychain is locked or refused the credentials; $operation was refused',
    _ => '$operation failed with OSStatus $status',
  };
  return DVAppKeyStoreUnavailable('the Keychain', reason, status: status);
}
