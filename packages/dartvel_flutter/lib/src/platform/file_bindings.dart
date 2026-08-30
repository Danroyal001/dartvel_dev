/// `files.readBytes`, `files.writeBytes` and `files.delete`.
///
/// These are the same on every platform with a filesystem, so they are plain
/// Dart rather than five FFI implementations of `open`, `read` and `unlink`.
/// The web has no filesystem and does not register them, which is the right
/// answer there: `DV.Platform` reports the binding as unavailable instead of
/// returning a plausible lie.
///
/// What is *not* the same everywhere is what a path is allowed to reach. A
/// binding that writes wherever it is told is a file-write primitive handed to
/// whatever can reach it, so this confines every path to a root the
/// application names.
library dartvel_flutter.platform.files;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Registers the file bindings against [register].
///
/// [root] is the only directory these may touch. Passing the filesystem root
/// is possible and is a decision the application has to make explicitly rather
/// than get by default.
class DVFileBindings {
  const DVFileBindings._();

  static bool _registered = false;
  static late String _root;

  static bool get isRegistered => _registered;

  /// The directory every path resolves inside.
  static String get root => _root;

  /// Registers the three bindings, confined to [root].
  ///
  /// Returns false where there is no filesystem to bind to, leaving the
  /// bindings unregistered rather than half-registered.
  static bool register(
    String root,
    void Function(String name, Object? Function(Object?) handler) register,
  ) {
    if (_registered) return true;

    final Directory directory = Directory(root);
    try {
      if (!directory.existsSync()) directory.createSync(recursive: true);
    } on FileSystemException {
      return false;
    }
    _root = directory.absolute.path;

    register('files.readBytes', (Object? arguments) {
      final File file = File(_resolve(_pathOf(arguments)));
      if (!file.existsSync()) {
        throw ArgumentError('files.readBytes: "${_pathOf(arguments)}" '
            'does not exist.');
      }
      return file.readAsBytesSync();
    });

    register('files.writeBytes', (Object? arguments) {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      final Object? bytes = map['bytes'];
      if (bytes is! List<int>) {
        // Refused rather than coerced. Writing the string form of a list is a
        // file that looks written and contains the wrong thing.
        throw ArgumentError(
          'files.writeBytes needs a List<int> in "bytes", got '
          '${bytes.runtimeType}.',
        );
      }
      final File file = File(_resolve(_pathOf(arguments)));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(Uint8List.fromList(bytes), flush: true);
      return bytes.length;
    });

    register('files.delete', (Object? arguments) {
      final File file = File(_resolve(_pathOf(arguments)));
      // Deleting what is not there is the caller's intent either way, and
      // throwing would make every caller wrap it.
      if (!file.existsSync()) return false;
      file.deleteSync();
      return true;
    });

    _registered = true;
    return true;
  }

  /// For tests: forgets the registration so a different root can be used.
  static void reset() {
    _registered = false;
  }

  static String _pathOf(Object? arguments) {
    final Map<Object?, Object?> map =
        arguments is Map ? arguments : const <Object?, Object?>{};
    final Object? path = map['path'];
    if (path is! String || path.isEmpty) {
      throw ArgumentError('A files.* binding needs a "path" string.');
    }
    return path;
  }

  /// Resolves [path] inside [root] and refuses anything that escapes it.
  ///
  /// The check is on the *canonical* path, after `..` and any symlink have
  /// been resolved. Checking the string as given would pass `a/../../etc/passwd`
  /// -- it starts with the root -- and pass a symlink pointing anywhere, which
  /// is how a confined file API stops being confined.
  static String _resolve(String path) {
    final String lexical = p.isAbsolute(path)
        ? p.canonicalize(path)
        : p.canonicalize(p.join(_root, path));
    final String canonicalRoot = p.canonicalize(_root);

    void check(String candidate) {
      // Compared as a path rather than as a string prefix: `/data-other`
      // starts with `/data` and is a different directory.
      if (candidate != canonicalRoot && !p.isWithin(canonicalRoot, candidate)) {
        throw ArgumentError(
          'files.* may only touch paths under $canonicalRoot; '
          '"$path" resolves to $candidate.',
        );
      }
    }

    check(lexical);

    // p.canonicalize is purely lexical: it folds `..` and separators and does
    // not follow symlinks. A link inside the root pointing anywhere passes the
    // check above and then reads or writes wherever it points, which is how a
    // confined file API stops being confined.
    //
    // So the real path is checked too, resolved from the nearest ancestor that
    // exists -- the target of a write does not exist yet, and its parent is
    // what a link would have to be planted in.
    String existing = lexical;
    while (existing != canonicalRoot &&
        FileSystemEntity.typeSync(existing, followLinks: false) ==
            FileSystemEntityType.notFound) {
      final String parent = p.dirname(existing);
      if (parent == existing) break;
      existing = parent;
    }

    try {
      check(p.canonicalize(
        Directory(existing).existsSync() || File(existing).existsSync() ||
                Link(existing).existsSync()
            ? File(existing).resolveSymbolicLinksSync()
            : existing,
      ));
    } on FileSystemException {
      // Nothing there to resolve; the lexical check already stands.
    }

    return lexical;
  }
}
