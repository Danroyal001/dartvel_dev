import 'dart:typed_data';

import 'app_key.dart';

/// No file system here; the web keeps its key in IndexedDB.
class DVFileAppKeyStore implements DVAppKeyStore {
  final String path;

  const DVFileAppKeyStore(this.path);

  @override
  Future<Uint8List?> read() async => null;

  @override
  Future<void> write(Uint8List key) async =>
      throw UnsupportedError('No file key store on this platform.');

  @override
  Future<void> clear() async {}
}

String dvHostOperatingSystem() => 'web';

String? dvHostHome() => null;
