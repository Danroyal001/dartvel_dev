import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'app_key.dart';

/// The application key in a file the user alone can read.
///
/// The fallback for a machine with no platform key store answering -- a
/// headless box, a container, a CI runner -- and the store on platforms
/// Dartvel has no native custody for yet. Mode 0600 in a 0700 directory: the
/// OS still protects it from other users, which is the property the platform
/// stores have; what it lacks is protection from the same user's other
/// programs, and [DVAppKeyStores.describe] says so.
class DVFileAppKeyStore implements DVAppKeyStore {
  final String path;

  const DVFileAppKeyStore(this.path);

  @override
  Future<Uint8List?> read() async {
    final File file = File(path);
    if (!file.existsSync()) return null;
    try {
      final Uint8List bytes = base64Decode(file.readAsStringSync().trim());
      return bytes.length == DVAppKey.lengthBytes ? bytes : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(Uint8List key) async {
    final File file = File(path);
    final Directory dir = file.parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      await _chmod(dir.path, '700');
    }
    file.writeAsStringSync(base64Encode(key), flush: true);
    await _chmod(path, '600');
  }

  @override
  Future<void> clear() async {
    final File file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  static Future<void> _chmod(String target, String mode) async {
    if (Platform.isWindows) return;
    await Process.run('chmod', <String>[mode, target]);
  }
}
