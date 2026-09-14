import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart'
    show DVAppKeyStoreUnavailable, DVDescribedAppKeyStore;

/// No Android Keystore without dart:ffi and JNI -- in a browser, say.
///
/// Refuses rather than answering null, so nothing mistakes a platform with no
/// Keystore for an empty one and generates a key it then cannot keep.
class DVAndroidKeystoreAppKeyStore implements DVDescribedAppKeyStore {
  final String app;

  const DVAndroidKeystoreAppKeyStore({required this.app});

  static const DVAppKeyStoreUnavailable _refusal = DVAppKeyStoreUnavailable(
    'the Android Keystore',
    'there is no Android Keystore on this platform',
  );

  @override
  String get description => 'the Android Keystore, which is not on this platform';

  String? get sealedPath => null;

  @override
  Future<Uint8List?> read() async => throw _refusal;

  @override
  Future<void> write(Uint8List key) async => throw _refusal;

  @override
  Future<void> clear() async => throw _refusal;

  Future<Map<String, Object?>> debugKeystoreFacts() async => throw _refusal;
}
