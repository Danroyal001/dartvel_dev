/// The device runtime's probes on iOS.
///
/// The Darwin half is macOS's: `sysctlbyname`, `host_statistics64` and
/// `getloadavg` are the same C calls in the same libSystem. What differs is
/// what macOS reaches for outside it -- `df`, which iOS cannot spawn, and
/// CoreGraphics' display list, which an iPhone does not need asked about.
library dartvel_flutter.platform.ios.device;

import '../macos/macos_device_ffi.dart';

class DVIosDeviceProbes extends DVMacosDeviceProbes {
  const DVIosDeviceProbes(this._diskFree);

  /// The shim's `volumeAvailableCapacityForImportantUsage`, or zero without
  /// one -- which the shared runtime already reads as unknown.
  final int Function(String path) _diskFree;

  @override
  int diskFreeBytes(String path) => _diskFree(path);

  @override
  bool hasTouch() => true;

  @override
  bool hasDisplay() => true;

  @override
  String displayServer() => 'uikit';
}
