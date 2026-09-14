import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart' show DVAppKeyStore, DVAppKeyStores;

import 'android/android_keystore_jni.dart';

/// WebCrypto is the browser's; there is none here.
class DVWebCryptoAppKeyStore implements DVAppKeyStore {
  final String app;
  final String database;

  const DVWebCryptoAppKeyStore({required this.app, this.database = 'dartvel-keys'});

  static bool get isAvailable => false;

  @override
  Future<Uint8List?> read() async => null;

  @override
  Future<void> write(Uint8List key) async => throw UnsupportedError('No WebCrypto outside a browser.');

  @override
  Future<void> clear() async {}

  Future<Uint8List?> debugStoredBytes() async => null;

  Future<bool> debugWrappingKeyExtractable() async => false;
}

/// The key store for [app] on this machine: what the platform has custody
/// for -- the Android Keystore, the Keychain on iOS and macOS, DPAPI, the
/// Secret Service -- else, on a desktop with no keyring answering, a file
/// only the user can read. On Android and iOS there is no file: the keyring
/// answers or the key is refused.
///
/// The generated runtime calls this as `dvAppKeyStoreFor('<package>')`.
/// [platform] and [home] are for tests; an application passes neither.
Future<DVAppKeyStore> dvAppKeyStoreFor(
  String app, {
  String? platform,
  String? home,
}) =>
    DVAppKeyStores.platform(
      app,
      platform: platform,
      home: home,
      androidKeystore: (String app) => DVAndroidKeystoreAppKeyStore(app: app),
    );
