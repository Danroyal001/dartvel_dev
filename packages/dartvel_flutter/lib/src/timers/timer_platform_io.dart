/// A device or desktop: the timers in a small file in the application's
/// state directory (Android, iOS), else under the user's home. Android swaps
/// in its own delivery when its bindings register.
library;

import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show dvHostHome;

import '../platform/device_runtime.dart';
import 'timer_basic_delivery.dart';
import 'timer_delivery.dart';

DVTimerStore dvPlatformTimerStore(String app) => _FileStore(() {
      final String? state = DVDeviceRuntime.stateDirectory;
      return state != null
          ? '$state/timers/$app.json'
          : '${dvHostHome() ?? Directory.systemTemp.path}/.dartvel/timers/$app.json';
    });

DVTimerDelivery dvPlatformTimerDelivery({required bool declared}) => DVBasicTimerDelivery();

void dvTimerWatchStore(String app, void Function() changed) {}

final class _FileStore implements DVTimerStore {
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
      // timers or the new ones, never half of either.
      final File partial = File('${file.path}.partial')..writeAsStringSync(value, flush: true);
      partial.renameSync(file.path);
    } on FileSystemException {
      // A read-only home: the timers hold for this run.
    }
  }
}
