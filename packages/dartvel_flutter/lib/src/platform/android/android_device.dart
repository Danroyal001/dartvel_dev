/// How the shared device runtime reads its numbers on Android.
///
/// Most of them come from procfs, which is the kernel's and not the desktop's:
/// `/proc/meminfo`, `/proc/uptime` and `/proc/loadavg` are the same files in
/// the same format on a phone as on a server, so the parsers are the Linux
/// ones rather than a second copy that drifts. What is genuinely different is
/// overridden below, and each override is there because the Linux answer is
/// wrong on a device rather than merely unavailable:
///
///   * Free space. `df --output=avail` is a GNU coreutils spelling; Android's
///     df is toybox and does not take it, so the Linux probe would report
///     zero free bytes and the health verdict would call every phone
///     unhealthy.
///   * The display. Linux decides from `DISPLAY` and `WAYLAND_DISPLAY`, and
///     Android sets neither. An Android device with a screen would report
///     that it has none.
///   * Touch. Linux walks `/sys/class/input` looking for a device whose name
///     contains "touch"; that directory is not readable by an ordinary app on
///     Android, so it would answer false on a touchscreen.
///   * Temperature. The thermal zone often exists and is not readable, and
///     `existsSync` says true either way — the read then throws, out of
///     `device.health`, which is a call that should not be able to fail.
library dartvel_flutter.platform.android.device;

import 'dart:io';

import 'package:jni/jni.dart';

import '../linux/linux_device.dart';
import 'generated/android/content/Context.dart';
import 'generated/android/content/pm/PackageManager.dart';
import 'generated/android/os/StatFs.dart';

/// The feature string Android answers "is there a touchscreen" with.
const String dvAndroidTouchFeature = 'android.hardware.touchscreen';

class DVAndroidDeviceProbes extends DVLinuxDeviceProbes {
  const DVAndroidDeviceProbes(this._context);

  final Context _context;

  /// Free bytes on the filesystem holding [path], through `StatFs`.
  ///
  /// Android's own class rather than `statvfs` through dart:ffi. The struct
  /// differs between bionic and glibc on 32-bit, and reading the wrong offset
  /// gives a figure that is wrong by orders of magnitude and still looks like
  /// a number — which the health verdict would then act on.
  @override
  int diskFreeBytes(String path) {
    try {
      return StatFs(path.toJString()).availableBytes;
    } on Object {
      // A path StatFs cannot stat. Zero is what the shared runtime already
      // treats as "unknown", and it errs towards reporting unhealthy.
      return 0;
    }
  }

  /// Whether this device has a touchscreen, as its package manager says.
  ///
  /// Android TV and a headless box answer false, and that is the point: the
  /// manifest is read by whoever decides what interface to draw.
  @override
  bool hasTouch() {
    try {
      final PackageManager? packages = _context.packageManager;
      if (packages == null) return false;
      return packages.hasSystemFeature(dvAndroidTouchFeature.toJString());
    } on Object {
      return false;
    }
  }

  /// An Android application always has a display to draw on; there is no
  /// headless mode in which one runs.
  @override
  bool hasDisplay() => true;

  @override
  String displayServer() => 'android';

  /// The thermal zone, when it can be read at all.
  ///
  /// Guarded rather than trusted. The file usually exists and is usually not
  /// readable by an ordinary application, and `existsSync` cannot tell those
  /// apart — so the Linux probe's read throws out of `device.health`, and a
  /// health check that can throw is a health check nothing can rely on.
  @override
  String? temperatureC() {
    try {
      return super.temperatureC();
    } on FileSystemException {
      return null;
    }
  }
}
