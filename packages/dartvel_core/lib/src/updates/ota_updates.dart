import 'ota.dart';

/// OTA Update Manager
class OtaUpdateManager {
  final bool Function()? updateChecker;
  final Future<void> Function()? updateInstaller;

  OtaUpdateManager({this.updateChecker, this.updateInstaller});

  /// Check for updates
  Future<bool> checkForUpdates() async {
    final checker = updateChecker;
    if (checker != null) return checker();
    return ShorebirdUpdater.checkForUpdate();
  }

  /// Download and install update
  Future<void> update() async {
    final installer = updateInstaller;
    if (installer != null) {
      await installer();
      return;
    }
    await ShorebirdUpdater.downloadUpdate();
  }
}
