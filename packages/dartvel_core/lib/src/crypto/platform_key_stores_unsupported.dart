import 'dart:typed_data';

import 'app_key.dart';

/// No DPAPI without dart:ffi.
class DVDpapiAppKeyStore implements DVAppKeyStore {
  final String path;

  const DVDpapiAppKeyStore(this.path);

  static bool get isAvailable => false;

  @override
  Future<Uint8List?> read() async => null;

  @override
  Future<void> write(Uint8List key) async => throw UnsupportedError('No DPAPI on this platform.');

  @override
  Future<void> clear() async {}
}

/// No Keychain without dart:ffi.
class DVKeychainAppKeyStore implements DVAppKeyStore {
  final String service;
  final String account;

  const DVKeychainAppKeyStore({required this.service, required this.account});

  static bool get isAvailable => false;

  @override
  Future<Uint8List?> read() async => null;

  @override
  Future<void> write(Uint8List key) async => throw UnsupportedError('No Keychain on this platform.');

  @override
  Future<void> clear() async {}
}
