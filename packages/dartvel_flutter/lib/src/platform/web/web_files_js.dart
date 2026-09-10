/// `files.readBytes`, `files.writeBytes` and `files.delete` in a browser.
///
/// The origin-private file system, through `navigator.storage.getDirectory()`.
/// It is a real filesystem with real directories and real paths; what makes it
/// usable here is that it belongs to the origin rather than to the person, so
/// nothing is prompted for and nothing can reach outside it. Chrome, Firefox
/// and Safari all have it, which is rare enough among the APIs in this
/// directory to be worth saying.
///
/// The comment at the head of `file_bindings.dart` says the web has no
/// filesystem and does not register these. That was true when it was written
/// and is the reason `DV.Platform.files` threw in every browser.
///
/// Paths are confined the same way the native bindings confine theirs, and
/// for the same reason: a path is a string from somewhere, and `..` in it is
/// how a confined file API stops being confined. There is no escape from OPFS
/// to find, so the check is about keeping one contract rather than two — a
/// path that native refuses must not quietly work here.
library dartvel_flutter.platform.web.files;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_interop.dart';

class DVWebFiles {
  const DVWebFiles._();

  static const Set<String> implemented = <String>{
    'files.readBytes',
    'files.writeBytes',
    'files.delete',
  };

  /// Whether this browser has the origin-private file system.
  ///
  /// `navigator.storage` alone is not enough: the quota API shipped years
  /// before `getDirectory`, so a browser can have the first and none of the
  /// second.
  static bool get available {
    final JSObject? navigator = dvNavigator;
    if (navigator == null) return false;
    final JSObject? storage = dvJsObject(navigator, 'storage');
    return storage != null && dvJsMethod(storage, 'getDirectory') != null;
  }

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) register,
  ) {
    register('files.readBytes', (Object? arguments) async {
      final List<String> segments = _segments(arguments);
      final web.FileSystemFileHandle handle =
          await _fileHandle(segments, create: false);
      final web.File file = await handle.getFile().toDart;
      final JSArrayBuffer buffer = await file.arrayBuffer().toDart;
      return buffer.toDart.asUint8List();
    });

    register('files.writeBytes', (Object? arguments) async {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      final Object? bytes = map['bytes'];
      if (bytes is! List<int>) {
        // Refused rather than coerced, exactly as the native binding refuses
        // it. Writing the string form of a list is a file that looks written
        // and holds the wrong thing.
        throw ArgumentError(
          'files.writeBytes needs a List<int> in "bytes", got '
          '${bytes.runtimeType}.',
        );
      }
      final web.FileSystemFileHandle handle =
          await _fileHandle(_segments(arguments), create: true);
      final web.FileSystemWritableFileStream stream =
          await handle.createWritable().toDart;
      // Truncated by createWritable's default, so a short write over a long
      // file does not leave the old tail behind it.
      await stream.write(Uint8List.fromList(bytes).toJS).toDart;
      await stream.close().toDart;
      return true;
    });

    register('files.delete', (Object? arguments) async {
      final List<String> segments = _segments(arguments);
      final web.FileSystemDirectoryHandle? parent =
          await _directory(segments.sublist(0, segments.length - 1),
              create: false);
      // Deleting what is not there is the caller's intent either way, and
      // throwing would make every caller wrap it. The native binding answers
      // false for the same case.
      if (parent == null) return false;
      try {
        await parent.removeEntry(segments.last).toDart;
        return true;
      } on Object {
        return false;
      }
    });
  }

  /// The path segments of [arguments], checked.
  static List<String> _segments(Object? arguments) {
    final Map<Object?, Object?> map =
        arguments is Map ? arguments : const <Object?, Object?>{};
    final Object? path = map['path'];
    if (path is! String || path.isEmpty) {
      throw ArgumentError('A files.* binding needs a "path" string.');
    }
    if (path.startsWith('/')) {
      // An absolute path has no meaning here and letting one through would
      // mean the same call reaches different files on two targets.
      throw ArgumentError(
        'files.* paths are relative to the origin-private root; '
        '"$path" is absolute.',
      );
    }
    final List<String> segments = <String>[
      for (final String segment in path.split('/'))
        if (segment.isNotEmpty && segment != '.') segment,
    ];
    if (segments.isEmpty) {
      throw ArgumentError('"$path" names no file.');
    }
    if (segments.contains('..')) {
      throw ArgumentError(
        'files.* may only touch paths under the origin-private root; '
        '"$path" walks out of it.',
      );
    }
    return segments;
  }

  static Future<web.FileSystemDirectoryHandle> _root() =>
      web.window.navigator.storage.getDirectory().toDart;

  /// The directory named by [segments], or null when it is not there and
  /// [create] is false.
  static Future<web.FileSystemDirectoryHandle?> _directory(
    List<String> segments, {
    required bool create,
  }) async {
    web.FileSystemDirectoryHandle directory = await _root();
    for (final String segment in segments) {
      try {
        directory = await directory
            .getDirectoryHandle(
              segment,
              web.FileSystemGetDirectoryOptions(create: create),
            )
            .toDart;
      } on Object {
        if (create) rethrow;
        return null;
      }
    }
    return directory;
  }

  static Future<web.FileSystemFileHandle> _fileHandle(
    List<String> segments, {
    required bool create,
  }) async {
    final web.FileSystemDirectoryHandle? directory = await _directory(
      segments.sublist(0, segments.length - 1),
      create: create,
    );
    if (directory == null) {
      throw ArgumentError(
        'files.readBytes: "${segments.join('/')}" does not exist.',
      );
    }
    try {
      return await directory
          .getFileHandle(
            segments.last,
            web.FileSystemGetFileOptions(create: create),
          )
          .toDart;
    } on Object {
      if (create) rethrow;
      // The same words the native binding uses, so an application handling a
      // missing file does not need to know which target it is on.
      throw ArgumentError(
        'files.readBytes: "${segments.join('/')}" does not exist.',
      );
    }
  }
}
