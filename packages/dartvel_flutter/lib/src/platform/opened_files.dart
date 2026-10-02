/// The files an application is opened with, delivered the same way on every
/// target.
///
/// What the build registers -- `dartvel.fileAssociations` -- decides which
/// files the system offers to the application. This is where they arrive:
///
/// | Target | How a file gets here |
/// |---|---|
/// | Linux, Windows, macOS, Sony eLinux | the launch arguments, handed to the running instance by a second launch |
/// | Android | `DartvelOpenActivity`, which the build writes, copies it into the cache; taken at start and on resume |
/// | iOS | the app delegate block copies it out of its security scope; taken at start and on resume |
/// | Web (installed PWA) | `launchQueue`, with the file's bytes |
///
/// Everything else -- a browser tab, webOS, a terminal build -- has no way
/// to be opened with a file, so [DVOpenedFiles.pick] is the fallback: the
/// platform's own picker, feeding the same stream.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart' show DVNativeBridge;
import 'opened_file_read_io.dart' if (dart.library.js_interop) 'opened_file_read_web.dart' as reader;

/// One file the application was opened with, shared, or picked.
class DVOpenedFile {
  DVOpenedFile({required this.name, this.path, this.mimeType, this.size, this.uri, List<int>? bytes}) : _bytes = bytes;

  /// A file at [path], named after its last segment.
  factory DVOpenedFile.atPath(String path, {String? mimeType}) {
    final String normalised = path.replaceAll(r'\', '/');
    return DVOpenedFile(name: normalised.substring(normalised.lastIndexOf('/') + 1), path: path, mimeType: mimeType);
  }

  /// What a binding reports: `{path, name, mimeType, size or bytes, uri}`.
  /// Null for a shape with neither a path nor bytes, which opens nothing.
  static DVOpenedFile? fromMap(Map<Object?, Object?> map) {
    final Object? path = map['path'];
    final Object? bytes = map['bytes'];
    final List<int>? content = bytes is List ? bytes.cast<int>() : null;
    if ((path is! String || path.isEmpty) && content == null) return null;
    final Object? name = map['name'];
    final Object? mimeType = map['mimeType'];
    final Object? size = map['size'] ?? (bytes is int ? bytes : null);
    final Object? uri = map['uri'];
    final DVOpenedFile? fromPath = path is String && path.isNotEmpty ? DVOpenedFile.atPath(path) : null;
    return DVOpenedFile(
      name: name is String && name.isNotEmpty ? name : (fromPath?.name ?? 'file'),
      path: path is String && path.isNotEmpty ? path : null,
      mimeType: mimeType is String && mimeType.isNotEmpty ? mimeType : null,
      size: size is int ? size : content?.length,
      uri: uri is String && uri.isNotEmpty ? uri : null,
      bytes: content,
    );
  }

  /// The file's name, `march.order`.
  final String name;

  /// Where it is on disk, or null in a browser, where a file has no path.
  final String? path;

  /// Its type as the platform reported it, or null when it did not.
  final String? mimeType;

  /// Its size in bytes, when known before reading it.
  final int? size;

  /// The `content://` URI it came from on Android, before it was copied.
  final String? uri;

  final List<int>? _bytes;

  /// The extension, lower-case and without its dot; empty when there is none.
  String get extension {
    final int dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// Its contents.
  Future<List<int>> read() async {
    final List<int>? bytes = _bytes;
    if (bytes != null) return bytes;
    final String? at = path;
    if (at == null) throw StateError('$name came with neither a path nor its bytes.');
    return reader.dvReadOpenedFile(at);
  }

  @override
  String toString() => 'DVOpenedFile($name${path == null ? '' : ', $path'})';
}

/// Where every source hands its files, and where an application reads them.
class DVOpenedFiles {
  DVOpenedFiles._();

  static final StreamController<DVOpenedFile> _controller = StreamController<DVOpenedFile>.broadcast(
    onListen: _flush,
  );
  static final List<DVOpenedFile> _waiting = <DVOpenedFile>[];
  static final List<DVOpenedFile> _launch = <DVOpenedFile>[];
  static Future<void>? _started;
  static AppLifecycleListener? _resumes;
  static bool _launchClosed = false;

  /// Every file the application is opened with, from now on, and the ones
  /// that arrived before anything listened -- the file it was launched with
  /// is delivered to the first listener rather than lost to a page that
  /// subscribed a frame late.
  static Stream<DVOpenedFile> get opened {
    unawaited(start());
    return _controller.stream;
  }

  /// The files the application was started with; empty when it was started
  /// from its icon.
  static Future<List<DVOpenedFile>> initial() async {
    await start();
    _launchClosed = true;
    return List<DVOpenedFile>.unmodifiable(_launch);
  }

  /// Hands [files] to the application. What each platform's source calls.
  static void deliver(Iterable<DVOpenedFile> files) {
    for (final DVOpenedFile file in files) {
      if (!_launchClosed) _launch.add(file);
      if (_controller.hasListener) {
        _controller.add(file);
      } else {
        _waiting.add(file);
      }
    }
  }

  /// Takes what the platform has collected since the last time: at start, and
  /// whenever the application comes back to the front, which is when Android
  /// and iOS hand over a file opened while it was running.
  static Future<void> start() => _started ??= () async {
        WidgetsFlutterBinding.ensureInitialized();
        await _take();
        // Files arriving later are not part of the launch.
        scheduleMicrotask(() => _launchClosed = true);
        _resumes ??= AppLifecycleListener(onResume: () => unawaited(_take()));
      }();

  static Future<void> _take() async {
    if (!DVNativeBridge.isRegistered('associations.opened')) return;
    final Object? taken = await DVNativeBridge.invoke<Object?>('associations.opened');
    deliver(dvOpenedFilesFrom(taken));
  }

  static void _flush() {
    final List<DVOpenedFile> pending = List<DVOpenedFile>.of(_waiting);
    _waiting.clear();
    // After the listener is attached, which onListen runs before.
    scheduleMicrotask(() => pending.forEach(_controller.add));
  }

  /// Forgets everything. For tests.
  @visibleForTesting
  static void resetForTest() {
    _waiting.clear();
    _launch.clear();
    _started = null;
    _resumes?.dispose();
    _resumes = null;
    _launchClosed = false;
  }
}

/// The files in what a binding answered: a list of maps, or that list as
/// JSON text (what Android's `take()` and iOS's defaults key hold).
List<DVOpenedFile> dvOpenedFilesFrom(Object? answer) {
  Object? decoded = answer;
  if (answer is String) {
    if (answer.trim().isEmpty) return const <DVOpenedFile>[];
    try {
      decoded = jsonDecode(answer);
    } on FormatException {
      return const <DVOpenedFile>[];
    }
  }
  if (decoded is! List) return const <DVOpenedFile>[];
  return <DVOpenedFile>[
    for (final Object? entry in decoded)
      if (entry is Map)
        if (DVOpenedFile.fromMap(entry) case final DVOpenedFile file) file,
  ];
}
