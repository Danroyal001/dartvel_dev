/// Device storage on a target with neither a filesystem nor a browser.
library dartvel_flutter.platform.storage.device_storage_stub;

import 'package:dartvel_core/dartvel.dart';

DVFileStorageAdapter dvDeviceStorageAdapter(String area, String? appId) =>
    DVLocalFileStorageAdapter(root: area);

String? dvDeviceStorageDirectory(String area, String? appId) => null;

Future<List<int>> dvReadPickedPath(String path) async =>
    throw UnsupportedError('This target has no filesystem to read "$path" from.');

/// Whether folders are picked through the browser rather than a binding.
const bool dvBrowserFolderPicker = false;

Future<DVFileStorageAdapter?> dvPickBrowserFolder() async => null;
