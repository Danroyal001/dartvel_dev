import 'dart:typed_data';

import 'app_key.dart';

/// No Secret Service without dart:ffi and a session bus.
class DVSecretServiceAppKeyStore implements DVAppKeyStore {
  final String service;
  final String account;
  final String? collection;

  const DVSecretServiceAppKeyStore({
    required this.service,
    required this.account,
    this.collection,
  });

  static Future<bool> isAvailable() async => false;

  @override
  Future<Uint8List?> read() async => null;

  @override
  Future<void> write(Uint8List key) async =>
      throw UnsupportedError('No Secret Service on this platform.');

  @override
  Future<void> clear() async {}
}
