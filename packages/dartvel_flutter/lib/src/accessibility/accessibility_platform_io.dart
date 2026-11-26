/// A device or desktop: the settings in a small file in the application's
/// state directory (Android, iOS), else under the user's home. The operating
/// system's reduce-motion and contrast settings come through Flutter's
/// MediaQuery.
library;

import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show dvHostHome;

import '../platform/device_runtime.dart';
import 'accessibility_store.dart';

DVAccessibilityStore dvPlatformAccessibilityStore(String app) => _FileStore(() {
      final String? state = DVDeviceRuntime.stateDirectory;
      return state != null
          ? '$state/accessibility/$app.json'
          : '${dvHostHome() ?? Directory.systemTemp.path}/.dartvel/accessibility/$app.json';
    });

bool dvSystemPrefersContrast() => false;

bool dvSystemPrefersReducedMotion() => false;

void dvWatchSystemPreferences(void Function() changed) {}

final class _FileStore implements DVAccessibilityStore {
  _FileStore(this._path);

  final String Function() _path;

  @override
  String? read() {
    try {
      final File file = File(_path());
      return file.existsSync() ? file.readAsStringSync() : null;
    } on FileSystemException {
      return null;
    }
  }

  @override
  void write(String value) {
    try {
      final File file = File(_path());
      file.parent.createSync(recursive: true);
      // Beside it and renamed over it: a crash mid-write leaves the old
      // settings or the new ones, never half of either.
      final File partial = File('${file.path}.partial')..writeAsStringSync(value, flush: true);
      partial.renameSync(file.path);
    } on FileSystemException {
      // A read-only home is not a reason to stop the app; the settings hold
      // for this run.
    }
  }
}
