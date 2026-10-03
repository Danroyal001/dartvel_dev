/// Device storage in a browser: the origin private file system.
///
/// It belongs to the origin, needs no prompt and cannot reach outside
/// itself, which is what the application's own directory is on every other
/// target. Chrome, Edge, Firefox and Safari have it; where a browser does
/// not, every call answers with a 501 [DVFileStorageException] naming why,
/// the same shape a bucket gives for a refusal.
library dartvel_flutter.platform.storage.device_storage_web;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:web/web.dart' as web;

import '../web/web_interop.dart';

/// [name] on [object], called with no arguments, without awaiting.
JSObject _call(JSObject object, String name) =>
    dvJsMethod(object, name)!.callAsFunction(object)! as JSObject;

// App files are the origin private root itself, the same place the
// deprecated `files.*` bindings write, so data written with
// DV.Platform.files is where DV.Platform.fileStorage reads it.
const String _cacheDirectory = '.dartvel-cache';

DVFileStorageAdapter dvDeviceStorageAdapter(String area, String? appId) =>
    DVOriginPrivateFileStorageAdapter(area == 'cache' ? _cacheDirectory : '');

/// Browsers have no directory path to give.
String? dvDeviceStorageDirectory(String area, String? appId) => null;

Future<List<int>> dvReadPickedPath(String path) async => throw UnsupportedError(
    'A browser hands back picked files as bytes, never as a path; "$path" cannot be read.');

/// `DV.FileStorage`'s calls over the origin private file system, under one
/// directory per area (`files`, `cache`).
class DVOriginPrivateFileStorageAdapter extends DVDirectoryHandleFileStorageAdapter {
  DVOriginPrivateFileStorageAdapter(String area)
      : super(() async {
          if (!available) return null;
          return web.window.navigator.storage.getDirectory().toDart;
        }, area: area, hidden: area.isEmpty ? const <String>{_cacheDirectory} : const <String>{});

  static bool get available {
    final JSObject? navigator = dvNavigator;
    if (navigator == null) return false;
    final JSObject? storage = dvJsObject(navigator, 'storage');
    return storage != null && dvJsMethod(storage, 'getDirectory') != null;
  }
}

/// `DV.FileStorage`'s calls over a browser directory handle: the origin
/// private root, or a folder the person picked with `showDirectoryPicker`.
class DVDirectoryHandleFileStorageAdapter implements DVFileStorageAdapter {
  DVDirectoryHandleFileStorageAdapter(this._root, {this.area = '', this.hidden = const <String>{}});

  /// The root, or null when this browser has none (answered as a 501).
  final Future<web.FileSystemDirectoryHandle?> Function() _root;

  /// A directory under the root this adapter keeps to, or '' for the root.
  final String area;

  /// Top-level names [list] leaves out (the cache, beside the app files).
  final Set<String> hidden;

  List<String> _segments(String key, String operation) {
    final List<String> segments = <String>[
      for (final String segment in key.split('/'))
        if (segment.isNotEmpty && segment != '.') segment,
    ];
    // The same answer the disk adapter gives a key that climbs out.
    if (segments.isEmpty || segments.contains('..') || key.startsWith('/')) {
      throw DVFileStorageException('local', operation, key, statusCode: 403);
    }
    return segments;
  }

  Future<web.FileSystemDirectoryHandle?> _directory(
    List<String> segments, {
    required bool create,
    required String operation,
    required String key,
  }) async {
    final web.FileSystemDirectoryHandle? root = await _root();
    if (root == null) {
      throw DVFileStorageException('local', operation, key, statusCode: 501);
    }
    web.FileSystemDirectoryHandle directory = root;
    for (final String segment in <String>[if (area.isNotEmpty) area, ...segments]) {
      try {
        directory = await directory
            .getDirectoryHandle(segment, web.FileSystemGetDirectoryOptions(create: create))
            .toDart;
      } on Object {
        if (create) rethrow;
        return null;
      }
    }
    return directory;
  }

  Future<web.FileSystemFileHandle?> _file(String key, String operation, {required bool create}) async {
    final List<String> segments = _segments(key, operation);
    final web.FileSystemDirectoryHandle? directory = await _directory(
        segments.sublist(0, segments.length - 1),
        create: create, operation: operation, key: key);
    if (directory == null) return null;
    try {
      return await directory
          .getFileHandle(segments.last, web.FileSystemGetFileOptions(create: create))
          .toDart;
    } on Object {
      if (create) rethrow;
      return null;
    }
  }

  @override
  Future<void> put(String key, List<int> bytes, {String? contentType}) async {
    final web.FileSystemFileHandle handle = (await _file(key, 'put', create: true))!;
    final web.FileSystemWritableFileStream stream = await handle.createWritable().toDart;
    await stream.write(Uint8List.fromList(bytes).toJS).toDart;
    await stream.close().toDart;
  }

  @override
  Future<List<int>> get(String key) async {
    final web.FileSystemFileHandle? handle = await _file(key, 'get', create: false);
    if (handle == null) throw DVFileStorageException('local', 'get', key, statusCode: 404);
    final web.File file = await handle.getFile().toDart;
    final JSArrayBuffer buffer = await file.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  @override
  Future<void> delete(String key) async {
    final List<String> segments = _segments(key, 'delete');
    final web.FileSystemDirectoryHandle? parent = await _directory(
        segments.sublist(0, segments.length - 1),
        create: false, operation: 'delete', key: key);
    if (parent == null) return;
    try {
      await parent.removeEntry(segments.last).toDart;
    } on Object {
      // Not there: deleting it is already done, as on every other adapter.
    }
  }

  @override
  Future<bool> exists(String key) async => await _file(key, 'exists', create: false) != null;

  @override
  Future<List<String>> list({String prefix = ''}) async {
    final web.FileSystemDirectoryHandle? root =
        await _directory(const <String>[], create: false, operation: 'list', key: prefix);
    if (root == null) return const <String>[];
    final List<String> keys = <String>[];
    Future<void> walk(web.FileSystemDirectoryHandle directory, String path) async {
      final JSObject iterator = _call(directory, 'values');
      while (true) {
        final JSObject step = (await dvJsAwait(_call(iterator, 'next')))! as JSObject;
        if ((dvJsValue(step, 'done') as JSBoolean?)?.toDart ?? false) break;
        final JSObject entry = dvJsValue(step, 'value')! as JSObject;
        final String name = dvJsString(entry, 'name') ?? '';
        final String kind = dvJsString(entry, 'kind') ?? '';
        final String key = path.isEmpty ? name : '$path/$name';
        if (path.isEmpty && hidden.contains(name)) continue;
        if (kind == 'directory') {
          await walk(entry as web.FileSystemDirectoryHandle, key);
        } else if (key.startsWith(prefix)) {
          keys.add(key);
        }
      }
    }

    await walk(root, '');
    keys.sort();
    return keys;
  }
}

/// Every browser can pick a folder: Chromium with `showDirectoryPicker`,
/// the rest with a folder file input.
const bool dvBrowserFolderPicker = true;

Future<DVFileStorageAdapter?> dvPickBrowserFolder() async {
  final JSFunction? picker = dvJsMethod(web.window, 'showDirectoryPicker');
  if (picker != null) {
    try {
      final JSAny? handle = await dvJsAwait(picker.callAsFunction(
          web.window, <String, Object?>{'mode': 'readwrite'}.jsify()));
      if (handle == null) return null;
      final web.FileSystemDirectoryHandle folder = handle as web.FileSystemDirectoryHandle;
      return DVDirectoryHandleFileStorageAdapter(() async => folder);
    } on Object catch (error) {
      // AbortError is the person closing the picker: a cancel, not a failure.
      if (dvJsReason(error).contains('AbortError')) return null;
      rethrow;
    }
  }
  return _pickFolderWithInput();
}

/// The fallback: `<input type="file" webkitdirectory>`, in Firefox and
/// Safari. The browser hands over the files, not the folder, so they are read
/// in and the storage is read-only.
Future<DVFileStorageAdapter?> _pickFolderWithInput() async {
  final web.HTMLInputElement input = web.document.createElement('input') as web.HTMLInputElement;
  input.type = 'file';
  input.setAttribute('webkitdirectory', '');
  input.style.position = 'fixed';
  input.style.left = '-10000px';
  web.document.body?.append(input);
  final Completer<bool> chosen = Completer<bool>();
  input.addEventListener('change', ((web.Event _) {
    if (!chosen.isCompleted) chosen.complete(true);
  }).toJS);
  input.addEventListener('cancel', ((web.Event _) {
    if (!chosen.isCompleted) chosen.complete(false);
  }).toJS);
  input.click();
  try {
    if (!await chosen.future) return null;
    final web.FileList? files = input.files;
    if (files == null || files.length == 0) return null;
    final Map<String, List<int>> contents = <String, List<int>>{};
    for (int index = 0; index < files.length; index++) {
      final web.File file = files.item(index)!;
      // "holiday/2024/beach.jpg": the picked folder's own name first.
      final String relative = file.webkitRelativePath;
      final int slash = relative.indexOf('/');
      final String key = slash < 0 ? file.name : relative.substring(slash + 1);
      final JSArrayBuffer buffer = await file.arrayBuffer().toDart;
      contents[key] = buffer.toDart.asUint8List();
    }
    return DVReadOnlyFolderFileStorageAdapter(contents);
  } finally {
    input.remove();
  }
}

/// A picked folder whose files a browser read in without a handle to write
/// back with.
class DVReadOnlyFolderFileStorageAdapter implements DVFileStorageAdapter {
  DVReadOnlyFolderFileStorageAdapter(this._files);

  final Map<String, List<int>> _files;

  Never _readOnly(String operation, String key) =>
      throw DVFileStorageException('local', operation, key, statusCode: 405);

  @override
  Future<void> put(String key, List<int> bytes, {String? contentType}) async => _readOnly('put', key);

  @override
  Future<void> delete(String key) async => _readOnly('delete', key);

  @override
  Future<List<int>> get(String key) async =>
      _files[key] ?? (throw DVFileStorageException('local', 'get', key, statusCode: 404));

  @override
  Future<bool> exists(String key) async => _files.containsKey(key);

  @override
  Future<List<String>> list({String prefix = ''}) async =>
      <String>[for (final String key in _files.keys) if (key.startsWith(prefix)) key]..sort();
}
