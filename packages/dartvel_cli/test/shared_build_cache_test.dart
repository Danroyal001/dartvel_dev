// What builds keep for each other in ~/.dartvel/cache (fonts subset and
// encoded by content): shared by every project on the machine, so a fresh
// checkout does not redo them, and kept under a size so it cannot fill a disk.
import 'dart:io';

import 'package:dartvel_cli/src/build/server_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('lives in the home directory, one folder a stage, versioned', () {
    expect(
      dvSharedBuildCache('web_fonts', version: '3.47.16', environment: <String, String>{'HOME': '/home/me'})!.path,
      p.join('/home/me', '.dartvel', 'cache', 'web_fonts', '3.47.16'),
    );
    expect(dvSharedBuildCache('web_fonts', version: '1', environment: const <String, String>{}), isNull);
  });

  test('is trimmed to its size, the files used least recently first, other versions before any', () {
    final Directory root = Directory.systemTemp.createTempSync('shared_cache');
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory current = Directory(p.join(root.path, 'web_fonts', '2'))..createSync(recursive: true);
    final Directory old = Directory(p.join(root.path, 'web_fonts', '1'))..createSync(recursive: true);
    final DateTime now = DateTime(2026, 11, 26);
    File write(Directory dir, String name, int size, int ageDays) =>
        File(p.join(dir.path, name))
          ..writeAsBytesSync(List<int>.filled(size, 1))
          ..setLastModifiedSync(now.subtract(Duration(days: ageDays)));
    write(old, 'a', 100, 0);
    write(current, 'oldest', 100, 9);
    write(current, 'middle', 100, 5);
    write(current, 'newest', 100, 1);
    dvTrimSharedBuildCache(current, maxBytes: 250);
    expect(old.existsSync(), isFalse, reason: 'another version is never asked for again');
    expect(current.listSync().map((FileSystemEntity e) => p.basename(e.path)).toSet(), <String>{'middle', 'newest'});
  });
}
