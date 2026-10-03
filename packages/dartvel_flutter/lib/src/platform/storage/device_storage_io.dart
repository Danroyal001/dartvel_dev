/// Device storage where there is a filesystem: the application's own
/// directories, per operating system.
library dartvel_flutter.platform.storage.device_storage_io;

import 'dart:io' as io;

import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;

import '../file_bindings.dart';

/// The local adapter for [area] (`files` or `cache`).
DVFileStorageAdapter dvDeviceStorageAdapter(String area, String? appId) {
  final String? directory = dvDeviceStorageDirectory(area, appId);
  if (directory == null) {
    throw StateError(
      'DV.Platform.fileStorage has no application directory on this device: '
      'the operating system did not say where this app may write.',
    );
  }
  return DVLocalFileStorageAdapter(root: directory);
}

/// Where [area] lives on this device, or null when the OS does not say.
///
/// Each is the directory the platform gives an application for its own data,
/// which needs no permission anywhere:
/// - Android: `dartvel-files` in the app's private files directory
///   (`getFilesDir()`), and `dartvel` in its cache directory.
/// - iOS: `Documents` in the app container (shown in the Files app when
///   `shareAppFiles` is on), and `Library/Caches`.
/// - macOS: `~/Library/Application Support/<app>` (the container when
///   sandboxed), and `~/Library/Caches/<app>`.
/// - Windows: `%LOCALAPPDATA%\<app>`.
/// - Linux and Linux-based embedded devices: `$XDG_DATA_HOME/<app>` and
///   `$XDG_CACHE_HOME/<app>`, with the XDG defaults under `~`.
String? dvDeviceStorageDirectory(
  String area, String? appId, {
  String? operatingSystem,
  Map<String, String>? environment,
  String? androidFilesDirectory,
}) {
  final String os = operatingSystem ?? io.Platform.operatingSystem;
  final Map<String, String> env = environment ?? io.Platform.environment;
  final String app = (appId == null || appId.isEmpty) ? _executableName() : appId;
  final bool cache = area == 'cache';
  String? usable(String? value) {
    if (value == null) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty || trimmed == '/' ? null : trimmed;
  }

  switch (os) {
    case 'android':
      // getFilesDir(), as the JNI bindings found it at startup. App files
      // are the directory the deprecated `files.*` bindings use, so what was
      // written with DV.Platform.files is where fileStorage reads it.
      final String? files = usable(androidFilesDirectory) ??
          (DVFileBindings.isRegistered ? p.dirname(DVFileBindings.root) : null);
      if (files == null) return null;
      // getCacheDir() is the sibling of getFilesDir() in the app's data
      // directory.
      return cache ? p.join(p.dirname(files), 'cache', 'dartvel') : p.join(files, 'dartvel-files');
    case 'ios':
      final String? home = usable(env['HOME']);
      if (home == null) return null;
      return cache ? p.join(home, 'Library', 'Caches', 'dartvel') : p.join(home, 'Documents');
    case 'macos':
      final String? home = usable(env['HOME']);
      if (home == null) return null;
      return cache
          ? p.join(home, 'Library', 'Caches', app)
          : p.join(home, 'Library', 'Application Support', app);
    case 'windows':
      final String? base = usable(env['LOCALAPPDATA']) ?? usable(env['APPDATA']);
      if (base == null) return null;
      return cache ? p.windows.join(base, app, 'Cache') : p.windows.join(base, app, 'Files');
    default:
      final String? home = usable(env['HOME']);
      final String? data = usable(env[cache ? 'XDG_CACHE_HOME' : 'XDG_DATA_HOME']) ??
          (home == null ? null : p.join(home, cache ? '.cache' : p.join('.local', 'share')));
      return data == null ? null : p.join(data, app);
  }
}

String _executableName() {
  final String name = p.basenameWithoutExtension(io.Platform.resolvedExecutable);
  return name.isEmpty ? 'dartvel_app' : name;
}

/// The bytes of a file a picker returned by path.
Future<List<int>> dvReadPickedPath(String path) => io.File(path).readAsBytes();

/// Whether folders are picked through the browser rather than a binding.
const bool dvBrowserFolderPicker = false;

Future<DVFileStorageAdapter?> dvPickBrowserFolder() async => null;
