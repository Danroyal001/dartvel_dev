import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart' show DVAppKeyStore, DVAppKeyStores;

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
/// for -- Secret Service, DPAPI, Keychain -- else a file only the user can
/// read.
Future<DVAppKeyStore> dvAppKeyStoreFor(String app) => DVAppKeyStores.platform(app);
