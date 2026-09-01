// Replacing a library that something has mapped.
//
// The build hook wrote the compiled library with File.copy, which opens the
// destination and truncates it. When a process has that file mapped -- which
// is exactly what dlopen does, and what native_symbols_test does in the same
// run -- truncating the inode pulls the backing out from under the mapping.
// Touching those pages then raises SIGBUS with BUS_ADRERR, and the VM aborted
// at exit with code 134 after every test had already passed.
//
// CI found it and a local run did not, because the crash needs cargo present
// so the hook actually rebuilds.
//
// A rename replaces the directory entry instead. Existing mappings keep the
// old inode, which stays alive until the last reference goes.
import 'dart:io';

import 'package:dartvel_shelf/src/atomic_copy.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('dv_atomic_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the destination ends up with the source content', () async {
    final File source = File('${dir.path}/source.bin')
      ..writeAsStringSync('new');
    final String destination = '${dir.path}/dest.bin';

    await dvAtomicCopy(source, destination);

    expect(File(destination).readAsStringSync(), 'new');
  });

  test('a missing destination is created', () async {
    final File source = File('${dir.path}/source.bin')
      ..writeAsStringSync('first');
    await dvAtomicCopy(source, '${dir.path}/fresh.bin');
    expect(File('${dir.path}/fresh.bin').readAsStringSync(), 'first');
  });

  test('the destination is replaced, not written through', () async {
    // The property that matters. A truncating write keeps the same inode and
    // destroys what any mapping of it was pointing at; a rename gives a new
    // one and leaves the old alive for whoever still holds it.
    final File source = File('${dir.path}/source.bin')
      ..writeAsStringSync('new');
    final String destination = '${dir.path}/dest.bin';
    File(destination).writeAsStringSync('old');

    final int before = _inodeOf(destination);
    await dvAtomicCopy(source, destination);
    final int after = _inodeOf(destination);

    expect(after, isNot(before),
        reason: 'the file must be replaced so existing mappings stay valid');
  });

  test('a reader holding the old file still reads the old bytes', () async {
    // The crash condition, modelled directly: something opened the library
    // before the rebuild. With a truncating copy it sees its content vanish;
    // with a rename it keeps reading what it opened.
    final String destination = '${dir.path}/dest.bin';
    File(destination).writeAsStringSync('old');
    final RandomAccessFile held = File(destination).openSync();

    final File source = File('${dir.path}/source.bin')
      ..writeAsStringSync('new');
    await dvAtomicCopy(source, destination);

    held.setPositionSync(0);
    expect(String.fromCharCodes(held.readSync(3)), 'old');
    held.closeSync();
  });

  test('it leaves no temporary behind', () async {
    final File source = File('${dir.path}/source.bin')
      ..writeAsStringSync('new');
    await dvAtomicCopy(source, '${dir.path}/dest.bin');

    final List<String> names = dir
        .listSync()
        .map((FileSystemEntity e) => e.uri.pathSegments.last)
        .toList();
    expect(names, unorderedEquals(<String>['source.bin', 'dest.bin']));
  });

  test('the destination directory is created if it does not exist', () async {
    final File source = File('${dir.path}/source.bin')
      ..writeAsStringSync('new');
    await dvAtomicCopy(source, '${dir.path}/nested/deep/dest.bin');
    expect(File('${dir.path}/nested/deep/dest.bin').readAsStringSync(), 'new');
  });
}

int _inodeOf(String path) {
  final ProcessResult result =
      Process.runSync('stat', <String>['-c', '%i', path]);
  return int.parse('${result.stdout}'.trim());
}
