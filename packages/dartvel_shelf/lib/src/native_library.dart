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
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkgffi;
import 'package:path/path.dart' as p;

List<int>? _embedded;

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
}

/// The platform directory and file name the package ships the library under.
({String subdir, String name}) nativeServerLibraryLocation() => (
      subdir: Platform.isMacOS
          ? (Platform.version.contains('arm64') ? 'macos-arm64' : 'macos-x64')
          : Platform.isLinux
              ? (Platform.version.contains('aarch64')
                  ? 'linux-arm64'
                  : 'linux-x64')
              : (Platform.version.contains('ARM64')
                  ? 'windows-arm64'
                  : 'windows-x64'),
      name: Platform.isWindows
          ? 'dartvel_shelf.dll'
          : Platform.isMacOS
              ? 'libdartvel_shelf.dylib'
              : 'libdartvel_shelf.so',
    );

/// Opens the native server library, and says where it came from.
///
/// Embedded bytes first, then the package's own file. Finding neither throws
/// a [StateError] naming what is missing, because what it replaced was a null
/// check failing on the first line of a binary that looked built.
Future<({ffi.DynamicLibrary library, String origin})>
    openNativeServerLibrary() async {
  final List<int>? embedded = _embedded;
  if (embedded != null) {
    return (library: _openBytes(embedded), origin: 'embedded in this binary');
  }
  final location = nativeServerLibraryLocation();
  final Uri? uri = await Isolate.resolvePackageUri(Uri.parse(
    'package:dartvel_shelf/native/${location.subdir}/${location.name}',
  ));
  if (uri == null) {
    throw StateError(
      'dartvel: the native server library is not in this program. A compiled '
      'backend carries it inside the binary, and this one was compiled '
      'without it: build the backend with `dartvel build server`, which '
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
