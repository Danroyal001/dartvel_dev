/// `DV.Platform.fileStorage`: `DV.FileStorage` on the device's own disk.
///
/// The same calls as `DV.FileStorage` (`put`, `get`, `delete`, `exists`,
/// `list`), bound to the local adapter whatever adapter the app's default
/// storage uses. Keys live in the directory each platform gives an app for
/// its own files, which needs no permission anywhere:
///
/// | Target | App files | Cache |
/// |---|---|---|
/// | Android | `<filesDir>/dartvel-files` | `<cacheDir>/dartvel` |
/// | iOS | `Documents` in the app container | `Library/Caches/dartvel` |
/// | macOS | `~/Library/Application Support/<app>` | `~/Library/Caches/<app>` |
/// | Windows | `%LOCALAPPDATA%\<app>\Files` | `%LOCALAPPDATA%\<app>\Cache` |
/// | Linux, embedded Linux | `$XDG_DATA_HOME/<app>` | `$XDG_CACHE_HOME/<app>` |
/// | Web | the origin private file system | `.dartvel-cache` in it |
///
/// Files outside that directory come in two ways. [DVDeviceStorage.pick] and
/// [DVDeviceStorage.pickDirectory] open the platform's picker; what the
/// person chooses is a grant on that file, so no permission is needed. Wider
/// access (photos, media, all files) is declared under `dartvel.fileStorage`
/// in pubspec.yaml, written into each platform's own files at build time,
/// and asked for at run time with [DVDeviceStorage.requestAccess].
library dartvel_flutter.platform.storage.device_storage;

import 'package:dartvel_core/dartvel.dart';

import '../../../dartvel_flutter.dart' show DVNativeBridge, DVStorage;
import 'device_storage_stub.dart'
    if (dart.library.io) 'device_storage_io.dart'
    if (dart.library.js_interop) 'device_storage_web.dart' as platform;

/// A file the person picked.
class DVPickedFile {
  const DVPickedFile({required this.name, this.path, this.bytes, this.type = 'file'});

  /// The file's name, without a directory.
  final String name;

  /// Where it is on disk, on targets whose pickers answer with a path
  /// (Android, where it is a private copy; macOS, Windows, Linux). Null in a
  /// browser, which hands back a file and never a path.
  final String? path;

  /// The contents, when the picker handed them over directly (the web).
  final List<int>? bytes;

  /// image, video, audio or file.
  final String type;

  /// The contents, read from [path] when they were not handed over.
  Future<List<int>> readBytes() async {
    if (bytes != null) return bytes!;
    if (path == null) throw StateError('The picked file "$name" carries neither bytes nor a path.');
    return platform.dvReadPickedPath(path!);
  }

  static DVPickedFile fromBinding(Map<Object?, Object?> item) {
    final Object? bytes = item['bytes'];
    final String? path = item['path'] is String ? item['path']! as String : null;
    return DVPickedFile(
      name: '${item['name'] ?? (path ?? '').split(RegExp(r'[\\/]')).last}',
      path: path,
      bytes: bytes is List ? bytes.cast<int>() : null,
      type: '${item['type'] ?? 'file'}',
    );
  }
}

/// The person refused, or the platform cannot give, access that
/// `dartvel.fileStorage` declared.
class DVFileAccessDenied implements Exception {
  const DVFileAccessDenied(this.access, this.reason);

  final DVDeviceFileAccess access;
  final String reason;

  @override
  String toString() => 'DVFileAccessDenied(${access.key}): $reason';
}

/// `DV.Platform.fileStorage`.
class DVDeviceStorage extends DVStorage {
  DVDeviceStorage._(super.adapter, this._area) : super.bound();

  final String _area;

  static String? _appId;
  static DVFileStorageConfig _config = const DVFileStorageConfig();
  static DVDeviceStorage? _instance;
  static DVDeviceStorage? _cache;

  /// What the generated runtime says at startup: the app's id (its directory
  /// name on desktops) and its `dartvel.fileStorage` declaration.
  static void declare({String? appId, DVFileStorageConfig config = const DVFileStorageConfig()}) {
    _appId = appId;
    _config = config;
    _instance = null;
    _cache = null;
  }

  /// The declaration in force.
  static DVFileStorageConfig get config => _config;

  /// Replaces the device adapters, for tests. [cache] defaults to [files].
  static void useAdapters(DVFileStorageAdapter files, {DVFileStorageAdapter? cache}) {
    _instance = DVDeviceStorage._(files, 'files');
    _cache = DVDeviceStorage._(cache ?? files, 'cache');
  }

  /// Back to the real device directories.
  static void reset() {
    _instance = null;
    _cache = null;
  }

  static DVDeviceStorage get instance =>
      _instance ??= DVDeviceStorage._(platform.dvDeviceStorageAdapter('files', _appId), 'files');

  /// The app's cache: the same calls, in the directory the OS may clear
  /// when space runs low.
  DVDeviceStorage get cache =>
      _cache ??= DVDeviceStorage._(platform.dvDeviceStorageAdapter('cache', _appId), 'cache');

  /// The directory keys resolve in, or null in a browser, which has none.
  String? get directory => platform.dvDeviceStorageDirectory(_area, _appId);

  /// Opens the platform's file picker. Empty when the person cancels.
  ///
  /// [type] is image, video, audio or any. No permission is needed on any
  /// target: choosing a file is the grant. Android's system picker
  /// (ACTION_OPEN_DOCUMENT) answers a private copy by path; the desktop
  /// dialogs answer the file's own path; a browser answers the bytes from a
  /// file input, which every browser has.
  Future<List<DVPickedFile>> pick({String type = 'any', bool multiple = false}) async {
    final Object? items = await DVNativeBridge.invoke<Object?>('media.pick', <String, Object?>{'type': type, 'multiple': multiple});
    if (items == null && !DVNativeBridge.isRegistered('media.pick')) {
      throw UnsupportedError('DV.Platform.fileStorage.pick: this target has no file picker binding (media.pick).');
    }
    return <DVPickedFile>[
      for (final Object? item in items is List ? items : const <Object?>[])
        if (item is Map) DVPickedFile.fromBinding(item),
    ];
  }

  /// Opens the platform's folder picker and answers the folder as a storage
  /// with the same calls, or null when the person cancels.
  ///
  /// macOS, Windows and Linux use the native folder dialog. Chromium
  /// browsers use the File System Access API (`showDirectoryPicker`), which
  /// can read and write the folder. Firefox and Safari fall back to a folder
  /// file input: the files are read in, the storage is read-only, and a
  /// write answers a 405 [DVFileStorageException]. Android and iOS answer
  /// folders as content trees rather than paths and throw
  /// [UnsupportedError], rather than answering null as if the person had
  /// cancelled.
  Future<DVStorage?> pickDirectory({String? title}) async {
    if (platform.dvBrowserFolderPicker) {
      final DVFileStorageAdapter? adapter = await platform.dvPickBrowserFolder();
      return adapter == null ? null : DVStorage.bound(adapter);
    }
    if (!DVNativeBridge.isRegistered('dialogs.chooseDirectory')) {
      throw UnsupportedError(
        'DV.Platform.fileStorage.pickDirectory: this target has no folder picker binding '
        '(dialogs.chooseDirectory); it exists on macOS, Windows, Linux and Chromium browsers.',
      );
    }
    final Object? result = await DVNativeBridge.require<Object?>(
        'dialogs.chooseDirectory', <String, Object?>{if (title != null) 'title': title});
    final Object? path = result is Map ? result['path'] : result;
    if (path is! String || path.isEmpty) return null;
    return DVStorage.bound(DVLocalFileStorageAdapter(root: path));
  }

  /// Asks for [access], which must be declared under `dartvel.fileStorage`.
  ///
  /// Answers when it is held. Throws [DVFileAccessDenied] when the person
  /// refuses or the platform has no such access, and [StateError] when the
  /// project never declared it -- asking for an undeclared permission is
  /// refused without a dialog on Android, and ends the app on iOS.
  Future<void> requestAccess(DVDeviceFileAccess access) async {
    if (!_config.allows(access)) {
      throw StateError(
        'DV.Platform.fileStorage.requestAccess(${access.key}): add ${access.key} to '
        'dartvel.fileStorage.access in pubspec.yaml so the build declares it.',
      );
    }
    // A picked document is granted by being picked.
    if (access == DVDeviceFileAccess.documents) return;
    if (!DVNativeBridge.isRegistered('permissions.request')) {
      throw DVFileAccessDenied(access, 'this target has no permissions binding to ask with.');
    }
    final bool? granted =
        await DVNativeBridge.invoke<bool>('permissions.request', <String, Object?>{'permission': access.key});
    if (granted != true) {
      throw DVFileAccessDenied(
        access,
        access == DVDeviceFileAccess.allFiles
            ? 'all-files access was not switched on for this app in Settings.'
            : 'the person refused ${access.key} access.',
      );
    }
  }
}
