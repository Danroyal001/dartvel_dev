/// `DV.FileStorage` on the filesystem this process is standing on.
///
/// On a server that is the server's disk. On a device it is the directory the
/// application owns, which is what a file manager writes into. It is the same
/// surface either way: a bucket on S3, Google Cloud Storage or Azure is one
/// more adapter behind these calls, and local is not a lesser case reached
/// some other way.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'adapters.dart';

/// Files under one directory, addressed by key.
///
/// A key is a relative path inside [root]. It is data, and often somebody
/// else's data — a request names the file it wants — so a key that climbs out
/// of the root is refused rather than resolved. Without that, `../` in a key
/// reads or overwrites anything the process can reach.
class DVLocalFileStorageAdapter implements DVFileStorageAdapter {
  DVLocalFileStorageAdapter({required this.root});

  /// The directory every key is inside. Created on first write.
  final String root;

  String _pathFor(String key, String operation) {
    final String resolved = p.normalize(p.join(root, key));
    final String inside = p.normalize(root);
    if (resolved != inside && !p.isWithin(inside, resolved)) {
      throw DVFileStorageException(
        'local',
        operation,
        key,
        // The same answer a bucket gives a key it will not serve, so a caller
        // handling one handles the other.
        statusCode: 403,
      );
    }
    return resolved;
  }

  @override
  Future<void> put(String key, List<int> bytes, {String? contentType}) async {
    final File file = File(_pathFor(key, 'put'));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<List<int>> get(String key) async {
    final File file = File(_pathFor(key, 'get'));
    if (!file.existsSync()) {
      throw DVFileStorageException('local', 'get', key, statusCode: 404);
    }
    return file.readAsBytes();
  }

  @override
  Future<void> delete(String key) async {
    final File file = File(_pathFor(key, 'delete'));
    // Deleting what is not there is how a caller makes sure it is gone, and
    // every other adapter answers that way.
    if (file.existsSync()) await file.delete();
  }

  @override
  Future<bool> exists(String key) async =>
      File(_pathFor(key, 'exists')).existsSync();

  @override
  Future<List<String>> list({String prefix = ''}) async {
    final Directory directory = Directory(root);
    if (!directory.existsSync()) return const <String>[];
    final List<String> keys = <String>[
      for (final FileSystemEntity entity
          in directory.listSync(recursive: true, followLinks: false))
        if (entity is File)
          // Keys are posix-shaped whatever the platform writes, so the same
          // key reaches the same file on Windows as on Linux.
          p.posix.joinAll(p.split(p.relative(entity.path, from: root))),
    ];
    keys.sort();
    return <String>[
      for (final String key in keys)
        if (key.startsWith(prefix)) key,
    ];
  }
}
