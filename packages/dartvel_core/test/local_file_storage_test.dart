// DV.FileStorage on the filesystem it is standing on.
//
// The adapters were S3, Google Cloud Storage, Azure and a map in memory, so
// the one place every application already has -- a disk -- was the one place
// DV.FileStorage could not write. On a server that is the server's
// filesystem; on a device it is the directory the application owns. A bucket
// is one more adapter behind the same calls, and local is not a lesser case
// reached some other way.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late DVFileStorageAdapter storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dartvel_local_storage_');
    storage = DVLocalFileStorageAdapter(root: root.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('puts, gets, lists and deletes a file under the root', () async {
    await storage.put('notes/one.txt', <int>[104, 105]);

    expect(await storage.exists('notes/one.txt'), isTrue);
    expect(await storage.get('notes/one.txt'), <int>[104, 105]);
    expect(await storage.list(), <String>['notes/one.txt']);
    expect(await storage.list(prefix: 'other/'), isEmpty);

    await storage.delete('notes/one.txt');
    expect(await storage.exists('notes/one.txt'), isFalse);
  });

  test('a missing file is a 404, the way a bucket answers one', () async {
    expect(
      () => storage.get('nothing.txt'),
      throwsA(isA<DVFileStorageException>()
          .having((DVFileStorageException e) => e.statusCode, 'statusCode', 404)),
    );
  });

  test('a key cannot climb out of the root', () async {
    // The whole risk of a filesystem adapter: a key is data, often from a
    // request, and ../ in one would read or overwrite anything the process
    // can reach. Refused rather than resolved.
    for (final String key in <String>[
      '../escape.txt',
      'notes/../../escape.txt',
      '/etc/passwd',
    ]) {
      expect(
        () => storage.put(key, <int>[1]),
        throwsA(isA<DVFileStorageException>()),
        reason: '$key climbs out of the root',
      );
    }
    expect(File(p.join(p.dirname(root.path), 'escape.txt')).existsSync(), isFalse);
  });

  test('deleting what is not there is not an error', () async {
    // Same as every other adapter: delete is how you make sure it is gone.
    await storage.delete('never-existed.txt');
  });
}
