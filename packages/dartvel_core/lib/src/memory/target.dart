/// Which target an arena is on, and the memory profile that follows from it.
library;

import 'size.dart';
import 'target_web.dart' if (dart.library.io) 'target_io.dart';

/// The class of device a target belongs to, which decides the default
/// segment size and whether committing pages at startup is allowed.
enum DVMemoryProfile {
  desktop(DVSize.mb(256)),
  mobile(DVSize.mb(64)),
  embedded(DVSize.mb(32)),
  web(DVSize.mb(128));

  const DVMemoryProfile(this.segment);

  /// The default segment size for this profile.
  final DVSize segment;

  /// Whether committing physical pages up front is refused here: the
  /// OOM killer on mobile and embedded devices takes a process that holds
  /// committed pages it is not using.
  bool get refusesTouchPages =>
      this == DVMemoryProfile.mobile || this == DVMemoryProfile.embedded;
}

/// A target an arena can run on.
enum DVMemoryTarget {
  android('android', DVMemoryProfile.mobile),
  ios('ios', DVMemoryProfile.mobile),
  windows('windows', DVMemoryProfile.desktop),
  linux('linux', DVMemoryProfile.desktop),
  macos('macos', DVMemoryProfile.desktop),
  fuchsia('fuchsia', DVMemoryProfile.desktop),
  sonyElinux('sony-elinux', DVMemoryProfile.embedded),
  tizen('tizen', DVMemoryProfile.embedded),
  webos('webos', DVMemoryProfile.embedded),
  webJs('web-js', DVMemoryProfile.web),
  webWasm('web-wasm', DVMemoryProfile.web);

  const DVMemoryTarget(this.id, this.profile);

  /// The name the build and the configuration use, e.g. `sony-elinux`.
  final String id;

  final DVMemoryProfile profile;

  bool get isWeb => profile == DVMemoryProfile.web;

  /// The target named [name], or null when it names none.
  static DVMemoryTarget? fromName(String name) {
    final String wanted = name.trim().toLowerCase();
    for (final DVMemoryTarget t in values) {
      if (t.id == wanted) return t;
    }
    return null;
  }

  static const String _override = String.fromEnvironment('DARTVEL_PLATFORM');

  /// The target this process is running on.
  ///
  /// A build that names its platform with `DARTVEL_PLATFORM` is believed
  /// first, because a Tizen television, a webOS one and a Sony eLinux board
  /// all report `linux` to `dart:io`, and taking them for a desktop would
  /// commit pages on a device with a quarter of a gigabyte to give.
  static DVMemoryTarget get current =>
      fromName(_override) ?? dvDetectMemoryTarget();
}
