/// Recordings in a directory only this application's account can read.
///
/// Mode 0700 on the directory, 0600 on every file, set by the call that
/// creates them rather than tightened afterwards: a file created with the
/// process's default mode and then chmodded is world-readable for the moment
/// in between, and a device that has already opened it keeps that access.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';

import 'capture_backend.dart';

final class DVPrivateCaptureFiles implements DVCaptureFiles {
  DVPrivateCaptureFiles(this.directory);

  /// Owned by the capture runtime: it is created 0700, and tightened to 0700
  /// if it already exists. Do not point this at a directory shared with
  /// anything else.
  final String directory;

  static final Random _random = Random.secure();

  @override
  Future<String> reserve(String extension) async {
    _ensureDirectory();
    for (int attempt = 0; attempt < 8; attempt++) {
      final String name = 'capture-${DateTime.now().microsecondsSinceEpoch}-'
          '${_random.nextInt(1 << 32).toRadixString(16)}.$extension';
      final String path = '$directory${Platform.pathSeparator}$name';
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        continue;
      }
      if (Platform.isWindows) {
        // No POSIX modes. The per-user profile directory's ACL is what keeps
        // other accounts out.
        File(path).createSync(exclusive: true);
      } else {
        _Libc.instance.createPrivate(path);
      }
      return path;
    }
    throw FileSystemException('could not reserve a capture file', directory);
  }

  @override
  Future<int> seal(String path) async {
    final File file = File(path);
    final FileStat stat = file.statSync();
    if (stat.type == FileSystemEntityType.notFound) {
      throw FileSystemException('the recording is missing', path);
    }
    // A device that deleted and recreated its output made a new file with the
    // default mode. Tighten it before anything else can learn its name.
    if (!Platform.isWindows && stat.mode & 0x3F != 0) {
      _Libc.instance.chmod(path, 0x180); // 0600
    }
    return stat.size;
  }

  @override
  Future<void> discard(String path) async {
    final File file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  void _ensureDirectory() {
    final Directory dir = Directory(directory);
    if (Platform.isWindows) {
      dir.createSync(recursive: true);
      return;
    }
    if (!dir.existsSync()) {
      dir.parent.createSync(recursive: true);
      _Libc.instance.mkdirPrivate(directory);
    }
    if (dir.statSync().mode & 0x3F != 0) {
      _Libc.instance.chmod(directory, 0x1C0); // 0700
    }
  }
}

/// The three libc calls Dart's file API has no mode argument for.
final class _Libc {
  _Libc._() {
    final DynamicLibrary libc = DynamicLibrary.process();
    // mode_t is 32 bits on Linux and Android, 16 on Apple platforms.
    if (Platform.isMacOS || Platform.isIOS) {
      _creat = libc
          .lookupFunction<Int32 Function(Pointer<Utf8>, Uint16),
              int Function(Pointer<Utf8>, int)>('creat');
      _mkdir = libc
          .lookupFunction<Int32 Function(Pointer<Utf8>, Uint16),
              int Function(Pointer<Utf8>, int)>('mkdir');
      _chmod = libc
          .lookupFunction<Int32 Function(Pointer<Utf8>, Uint16),
              int Function(Pointer<Utf8>, int)>('chmod');
    } else {
      _creat = libc
          .lookupFunction<Int32 Function(Pointer<Utf8>, Uint32),
              int Function(Pointer<Utf8>, int)>('creat');
      _mkdir = libc
          .lookupFunction<Int32 Function(Pointer<Utf8>, Uint32),
              int Function(Pointer<Utf8>, int)>('mkdir');
      _chmod = libc
          .lookupFunction<Int32 Function(Pointer<Utf8>, Uint32),
              int Function(Pointer<Utf8>, int)>('chmod');
    }
    _close = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'close');
  }

  static final _Libc instance = _Libc._();

  late final int Function(Pointer<Utf8>, int) _creat;
  late final int Function(Pointer<Utf8>, int) _mkdir;
  late final int Function(Pointer<Utf8>, int) _chmod;
  late final int Function(int) _close;

  void createPrivate(String path) {
    final Pointer<Utf8> native = path.toNativeUtf8();
    try {
      final int fd = _creat(native, 0x180); // 0600
      if (fd < 0) {
        throw FileSystemException('could not create the recording', path);
      }
      _close(fd);
    } finally {
      malloc.free(native);
    }
  }

  void mkdirPrivate(String path) {
    final Pointer<Utf8> native = path.toNativeUtf8();
    try {
      if (_mkdir(native, 0x1C0) != 0 && !Directory(path).existsSync()) {
        throw FileSystemException('could not create the capture directory',
            path);
      }
    } finally {
      malloc.free(native);
    }
  }

  void chmod(String path, int mode) {
    final Pointer<Utf8> native = path.toNativeUtf8();
    try {
      if (_chmod(native, mode) != 0) {
        throw FileSystemException('could not restrict permissions', path);
      }
    } finally {
      malloc.free(native);
    }
  }
}
