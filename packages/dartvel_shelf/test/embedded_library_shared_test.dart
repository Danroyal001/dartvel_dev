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
Future<int> _revisionAddress(String path) async {
  embedNativeServerLibraryAt(path, offset: 0, length: File(path).lengthSync());
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

void main() {
  test('isolates of one process open one copy of the embedded library',
      () async {
    final String path = File(_library).absolute.path;
    final int here = await _revisionAddress(path);
    final List<int> there = await Future.wait(<Future<int>>[
      for (var i = 0; i < 3; i++) Isolate.run(() => _revisionAddress(path)),
    ]);
    expect(there, everyElement(here),
        reason: 'every isolate must call into the same loaded library');
    expect(_memfdCount(), 1,
        reason: 'one in-memory copy of the library, not one per isolate');
  });
}
