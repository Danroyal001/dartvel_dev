/// Where the native server library is loaded from.
///
/// Under `dart run` the library is a file in this package and
/// Isolate.resolvePackageUri finds it. A program compiled with
/// `dart compile exe` has no packages to resolve against, so that answers
/// null there, and a backend compiled to one binary could not start. Such a
/// binary carries the library's bytes instead and hands them over with
/// [embedNativeServerLibrary] before it serves.
library;

import 'dart:ffi' as ffi;
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkgffi;
import 'package:path/path.dart' as p;

List<int>? _embedded;

/// Where the library lies inside a file, when it was given that way.
({String path, int offset, int length})? _embeddedAt;

/// The library once it is open: a second [serve] in the same process opens
/// nothing again, and the bytes it was opened from are not kept.
({ffi.DynamicLibrary library, String origin})? _opened;

/// Gives this process the native server library as bytes.
///
/// For a compiled executable, which carries the library inside itself: the
/// next [serve] loads these rather than looking for a file in a package that
/// is not there. Call it before serving.
void embedNativeServerLibrary(List<int> bytes) {
  if (bytes.isEmpty) {
    throw ArgumentError.value(bytes, 'bytes', 'the library is empty');
  }
  _embedded = bytes;
  _embeddedAt = null;
  _opened = null;
}

/// Gives this process the native server library as [length] bytes at
/// [offset] in the file at [path]: where a web-server binary carries it,
/// inside itself.
///
/// Nothing is read until [serve] opens it, and then it is copied a piece at
/// a time into an anonymous in-memory file (a private temporary file where
/// the platform has none) and opened from there. No copy of it is kept in
/// the Dart heap.
void embedNativeServerLibraryAt(String path, {required int offset, required int length}) {
  if (length <= 0) {
    throw ArgumentError.value(length, 'length', 'the library is empty');
  }
  _embeddedAt = (path: path, offset: offset, length: length);
  _embedded = null;
  _opened = null;
}

/// The platform directory and file name the package ships the library under,
/// for this process.
///
/// Throws [UnsupportedError] on a host the server is not built for, rather
/// than naming another host's library.
({String subdir, String name}) nativeServerLibraryLocation() {
  final ({String subdir, String name})? location =
      nativeServerLibraryFor(Abi.current());
  if (location == null) {
    throw UnsupportedError(
        'dartvel: no native server library is built for ${Abi.current()}.');
  }
  return location;
}

/// The directory and file name of the server library for [abi], or null for
/// an ABI the server is not built for.
///
/// Read from the ABI, never from Platform.version: that string says
/// `linux_arm64` and `windows_arm64`, and a check for `aarch64` or `ARM64`
/// sent both arm64 hosts to the x64 library.
({String subdir, String name})? nativeServerLibraryFor(Abi abi) =>
    switch (abi) {
      Abi.linuxX64 => (subdir: 'linux-x64', name: 'libdartvel_shelf.so'),
      Abi.linuxArm64 => (subdir: 'linux-arm64', name: 'libdartvel_shelf.so'),
      Abi.macosArm64 => (subdir: 'macos-arm64', name: 'libdartvel_shelf.dylib'),
      Abi.macosX64 => (subdir: 'macos-x64', name: 'libdartvel_shelf.dylib'),
      Abi.windowsX64 => (subdir: 'windows-x64', name: 'dartvel_shelf.dll'),
      Abi.windowsArm64 => (subdir: 'windows-arm64', name: 'dartvel_shelf.dll'),
      _ => null,
    };

/// Opens the native server library, and says where it came from.
///
/// Embedded bytes first, then the package's own file. Finding neither throws
/// a [StateError] naming what is missing, because what it replaced was a null
/// check failing on the first line of a binary that looked built.
Future<({ffi.DynamicLibrary library, String origin})>
    openNativeServerLibrary() async {
  final ({ffi.DynamicLibrary library, String origin})? opened = _opened;
  if (opened != null) return opened;
  final ({String path, int offset, int length})? at = _embeddedAt;
  if (at != null) {
    return _opened = (library: _openRange(at), origin: 'embedded in this binary');
  }
  final List<int>? embedded = _embedded;
  if (embedded != null) {
    final ffi.DynamicLibrary library = _openBytes(embedded);
    // Open now; the bytes it came from are garbage.
    _embedded = null;
    return _opened = (library: library, origin: 'embedded in this binary');
  }
  final location = nativeServerLibraryLocation();
  final Uri? uri = await Isolate.resolvePackageUri(Uri.parse(
    'package:dartvel_shelf/native/${location.subdir}/${location.name}',
  ));
  if (uri == null) {
    throw StateError(
      'dartvel: the native server library is not in this program. A compiled '
      'backend carries it inside the binary, and this one was compiled '
      'without it: build the backend with `dartvel build web-server`, which '
      'embeds ${location.subdir}/${location.name}.',
    );
  }
  return (
    library: ffi.DynamicLibrary.open(uri.toFilePath()),
    origin: uri.toFilePath(),
  );
}

ffi.DynamicLibrary _openBytes(List<int> bytes) {
  if (Platform.isLinux) {
    // An anonymous in-memory file: nothing written to disk, nothing another
    // user could swap between the write and the open, and gone with the
    // process. A kernel that refuses executable memfds falls through to the
    // file below.
    final ffi.DynamicLibrary? inMemory = _openMemfd(bytes);
    if (inMemory != null) return inMemory;
  }
  // A directory of this process's own, made by mkdtemp and so enterable by
  // this user alone: a shared, predictable path is one somebody else can
  // create first and fill with their own library.
  final Directory dir =
      Directory.systemTemp.createTempSync('dartvel-native-');
  final File file = File(p.join(dir.path, nativeServerLibraryLocation().name))
    ..writeAsBytesSync(bytes, flush: true);
  return ffi.DynamicLibrary.open(file.path);
}

/// The library at [at], copied a piece at a time into where it is opened
/// from: an anonymous in-memory file on Linux, a private temporary file
/// elsewhere.
ffi.DynamicLibrary _openRange(({String path, int offset, int length}) at) {
  void copyInto(RandomAccessFile out) {
    final RandomAccessFile source = File(at.path).openSync();
    try {
      source.setPositionSync(at.offset);
      int left = at.length;
      while (left > 0) {
        final Uint8List piece = source.readSync(left < (1 << 20) ? left : 1 << 20);
        if (piece.isEmpty) {
          throw StateError('dartvel: ${at.path} ends inside the native server library');
        }
        out.writeFromSync(piece);
        left -= piece.length;
      }
    } finally {
      source.closeSync();
    }
  }

  if (Platform.isLinux) {
    final int? fd = _memfd();
    if (fd != null) {
      final String path = '/proc/self/fd/$fd';
      try {
        final RandomAccessFile out = File(path).openSync(mode: FileMode.writeOnly);
        try {
          copyInto(out);
        } finally {
          out.closeSync();
        }
        return ffi.DynamicLibrary.open(path);
      } on Object {
        // A kernel that refuses executable memfds: the file below.
      }
    }
  }
  final Directory dir = Directory.systemTemp.createTempSync('dartvel-native-');
  final File file = File(p.join(dir.path, nativeServerLibraryLocation().name));
  final RandomAccessFile out = file.openSync(mode: FileMode.writeOnly);
  try {
    copyInto(out);
  } finally {
    out.closeSync();
  }
  return ffi.DynamicLibrary.open(file.path);
}

/// An anonymous in-memory file, or null where there is none.
int? _memfd() {
  try {
    final int Function(ffi.Pointer<pkgffi.Utf8>, int) memfdCreate =
        ffi.DynamicLibrary.process().lookupFunction<
            ffi.Int32 Function(ffi.Pointer<pkgffi.Utf8>, ffi.Uint32),
            int Function(ffi.Pointer<pkgffi.Utf8>, int)>('memfd_create');
    final ffi.Pointer<pkgffi.Utf8> name =
        'dartvel_shelf'.toNativeUtf8(allocator: pkgffi.calloc);
    // MFD_CLOEXEC: a child process this server starts does not inherit it.
    final int fd = memfdCreate(name, 1);
    pkgffi.calloc.free(name);
    return fd < 0 ? null : fd;
  } on Object {
    return null;
  }
}

ffi.DynamicLibrary? _openMemfd(List<int> bytes) {
  try {
    final int Function(ffi.Pointer<pkgffi.Utf8>, int) memfdCreate =
        ffi.DynamicLibrary.process().lookupFunction<
            ffi.Int32 Function(ffi.Pointer<pkgffi.Utf8>, ffi.Uint32),
            int Function(ffi.Pointer<pkgffi.Utf8>, int)>('memfd_create');
    final ffi.Pointer<pkgffi.Utf8> name =
        'dartvel_shelf'.toNativeUtf8(allocator: pkgffi.calloc);
    // MFD_CLOEXEC: a child process this server starts does not inherit it.
    final int fd = memfdCreate(name, 1);
    pkgffi.calloc.free(name);
    if (fd < 0) return null;
    final String path = '/proc/self/fd/$fd';
    File(path).writeAsBytesSync(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      flush: true,
    );
    return ffi.DynamicLibrary.open(path);
  } on Object {
    return null;
  }
}
