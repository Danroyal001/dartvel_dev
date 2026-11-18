// A web-server binary carries the native library inside itself and opens it
// from an anonymous in-memory file. Each isolate that serves opened its own
// copy: a server on four isolates loaded the library four times, with four
// sets of its memory and four times its start-up cost, where a library opened
// from a file path is loaded once per process. Every isolate of a process now
// opens the one copy the first one made.
@TestOn('linux')
library;

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_shelf/src/native_library.dart';
import 'package:test/test.dart';

const String _library = 'lib/native/linux-x64/libdartvel_shelf.so';

/// Where this isolate's copy of the library keeps its source revision: the
/// same address in two isolates is the same loaded library.
Future<int> _revisionAddress(String path, {int offset = 0, int? length}) async {
  embedNativeServerLibraryAt(path,
      offset: offset, length: length ?? File(path).lengthSync() - offset);
  final ffi.DynamicLibrary library = (await openNativeServerLibrary()).library;
  final ffi.Pointer<ffi.Uint8> Function() revision = library.lookupFunction<
      ffi.Pointer<ffi.Uint8> Function(),
      ffi.Pointer<ffi.Uint8> Function()>('aw_source_revision');
  return revision().address;
}

int _memfdCount() => Directory('/proc/self/fd')
    .listSync(followLinks: false)
    .whereType<Link>()
    .where((Link fd) {
      try {
        return fd.targetSync().contains('memfd:dartvel_shelf');
      } on FileSystemException {
        return false;
      }
    })
    .length;

/// The library inside a larger file, at an offset, as a web-server binary
/// carries it.
(String, int, int) _carried() {
  final Directory dir = Directory.systemTemp.createTempSync('carried');
  final List<int> library = File(_library).readAsBytesSync();
  final File binary = File('${dir.path}/server')
    ..writeAsBytesSync(<int>[...List<int>.filled(4096, 7), ...library, 1, 2, 3]);
  return (binary.path, 4096, library.length);
}

void main() {
  test('isolates of one process open one copy of the embedded library',
      () async {
    final (String path, int offset, int length) = _carried();
    final int here = await _revisionAddress(path, offset: offset, length: length);
    final List<int> there = await Future.wait(<Future<int>>[
      for (var i = 0; i < 3; i++)
        Isolate.run(() => _revisionAddress(path, offset: offset, length: length)),
    ]);
    expect(there, everyElement(here),
        reason: 'every isolate must call into the same loaded library');
    expect(_memfdCount(), 1,
        reason: 'one in-memory copy of the library, not one per isolate');
  });
  test('a library given as a whole file is opened from that file, uncopied',
      () async {
    final Directory dir = Directory.systemTemp.createTempSync('whole');
    final String path = '${dir.path}/libdartvel_shelf.so';
    File(_library).copySync(path);
    final int before = _memfdCount();
    final int here = await _revisionAddress(path);
    final int there = await Isolate.run(() => _revisionAddress(path));
    expect(there, here);
    expect(_memfdCount(), before,
        reason: 'no in-memory copy: the loader maps the file itself, so only '
            'the pages that run are resident');
    expect(
        File('/proc/self/maps').readAsStringSync().contains(path), isTrue);
  });
}
