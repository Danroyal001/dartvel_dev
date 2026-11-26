/// Small values kept for one visitor between visits: settings a page needs
/// before its first frame (text size, contrast, where voice mode sits).
///
/// Read and written synchronously, unlike [DVDeviceStorage], which is
/// file-shaped and asynchronous: a setting read after the first frame is a
/// page drawn once in the wrong settings and again in the right ones.
///
/// - A browser: `localStorage`, under the key as given, so the SSR-first head
///   can read the same value before the first paint.
/// - A device or desktop: one small file per key in the app's storage
///   directory (`preferences/<key>.json`).
/// - Anywhere else: memory, for this run.
///
/// Application code rarely names this: a model declared with
/// `@DVModel(storage: DVModelStorage.device)` is kept here, and
/// `Model.kept` / `model.keep()` are how it is read and written.
library;

import 'dart:io' if (dart.library.js_interop) 'preference_store_no_io.dart';

import 'preference_store_stub.dart'
    if (dart.library.js_interop) 'preference_store_web.dart'
    if (dart.library.io) 'preference_store_io.dart' as platform;

/// Where small per-visitor values are kept. See the library documentation.
abstract interface class DVPreferenceStore {
  /// The value kept under [key], or null.
  String? read(String key);

  /// Keeps [value] under [key]. A store that cannot keep it (a private
  /// window, a read-only home) leaves it for this run; it never throws.
  void write(String key, String value);

  /// Forgets [key].
  void remove(String key);

  static DVPreferenceStore? _instance;

  /// The store every caller uses: the platform's own until a test replaces it.
  static DVPreferenceStore get instance => _instance ??= platform.dvPlatformPreferenceStore();

  static set instance(DVPreferenceStore store) => _instance = store;

  /// Back to the platform's store. For tests.
  static void reset() => _instance = null;
}

/// Kept in memory: tests, and a platform with nowhere to keep it.
final class DVMemoryPreferenceStore implements DVPreferenceStore {
  final Map<String, String> _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String value) => _values[key] = value;

  @override
  void remove(String key) => _values.remove(key);
}

final RegExp _plainKey = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

/// One file per key in [directory]: `<directory>/<key>.json`. A key is a
/// plain name (letters, digits, `.`, `_`, `-`), never a path.
final class DVFilePreferenceStore implements DVPreferenceStore {
  DVFilePreferenceStore(this.directory);

  /// Where the files are.
  final String directory;

  String _path(String key) {
    if (!_plainKey.hasMatch(key) || key.contains('..')) {
      throw ArgumentError.value(key, 'key', 'must be a plain name: letters, digits, ".", "_" or "-"');
    }
    return '$directory/$key.json';
  }

  @override
  String? read(String key) {
    final String path = _path(key);
    try {
      final File file = File(path);
      return file.existsSync() ? file.readAsStringSync() : null;
    } on FileSystemException {
      return null;
    }
  }

  @override
  void write(String key, String value) {
    final String path = _path(key);
    try {
      final File file = File(path);
      file.parent.createSync(recursive: true);
      // Beside it and renamed over it: a crash mid-write leaves the old value
      // or the new one, never half of either.
      final File partial = File('$path.partial')..writeAsStringSync(value, flush: true);
      partial.renameSync(path);
    } on FileSystemException {
      // Kept for this run only.
    }
  }

  @override
  void remove(String key) {
    final String path = _path(key);
    try {
      final File file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Nothing to forget.
    }
  }
}
