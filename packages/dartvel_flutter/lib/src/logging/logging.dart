/// `DV.log` on a device: where its records go, and how a person sends them.
library;

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/dv.dart' as core show DV;

import '../../dartvel_flutter.dart' show DV;
import '../crashes/crash_platform_none.dart'
    if (dart.library.io) '../crashes/crash_platform_io.dart'
    if (dart.library.js_interop) '../crashes/crash_platform_web.dart'
    as crash_platform;
import 'log_platform_none.dart'
    if (dart.library.io) 'log_platform_io.dart'
    if (dart.library.js_interop) 'log_platform_web.dart' as platform;
import 'native_log_sink.dart';

export 'log_directory.dart' show dvLogDirectoryFor;

/// Sending the logs from the application.
extension DVLogShare on DVLog {
  /// Opens the platform's share sheet with the newest records that fit in
  /// [maxBytes], one JSON object per line.
  ///
  /// Cut to the newest rather than sent whole: a share intent carrying
  /// megabytes of text fails on Android, and the end of the log is the part
  /// that explains what the person just saw.
  Future<void> share({int maxBytes = 100 * 1024}) async {
    final List<String> lines = (await export()).split('\n')
      ..removeWhere((String line) => line.isEmpty);
    final List<String> kept = <String>[];
    int size = 0;
    for (final String line in lines.reversed) {
      size += line.length + 1;
      if (size > maxBytes) break;
      kept.add(line);
    }
    await DV.Platform.share.shareText(kept.reversed.join('\n'));
  }
}

/// What [dvInstallApplicationLogging] set up.
final class DVLogInstallation {
  DVLogInstallation._({this.file, this.native, this.shipper});

  /// The device's log file, when one could be opened.
  final DVLogFile? file;

  /// The platform log, when one is mirrored.
  final DVLogSink? native;

  /// The batch sender, when shipping is on.
  final DVLogShipper? shipper;
}

/// Feeds warn and above into the crash reporter's breadcrumbs, so a crash
/// report carries the log lines leading up to it.
final class _CrashBreadcrumbSink implements DVLogSink {
  @override
  void write(DVLogRecord record) {
    if (!record.level.atLeast(DVLogLevel.warn)) return;
    DV.Crashes.installation?.reporter.breadcrumbs.add(
      record.tag ?? 'log',
      record.message,
      data: record.context,
    );
  }
}

DVLogInstallation? _installed;

/// Installs DV.log's destinations for the application [appId] at [release]
/// from `dartvel.logging`: the platform log, the device's capped log file,
/// the crash reporter's breadcrumbs and, when declared, shipping to the
/// backend [api] reaches. What the generated runtime calls at startup.
///
/// Null under `flutter test` unless [evenUnderTest]. Never throws: a log
/// that cannot be set up is not a reason for the application not to start.
DVLogInstallation? dvInstallApplicationLogging({
  required String appId,
  required String release,
  required DVLogConfig config,
  Uri Function(String path)? api,
  bool evenUnderTest = false,
}) {
  if (_installed != null) return _installed;
  if (!evenUnderTest && platform.dvLogHostedByTestRunner()) return null;
  try {
    DVLogFile? file;
    if (config.file) {
      try {
        file = platform.dvDefaultLogFile(appId, config);
      } on Object {
        file = null;
      }
      if (file != null) core.DV.ObservabilityAndLogging.useLogFile(file);
    }
    final DVLogSink? native = config.native ? dvNativeLogSink(appId: appId) : null;
    DVLogShipper? shipper;
    if (config.ship && api != null) {
      shipper = DVLogShipper.toBackend(
        endpoint: () => api(DVLogIngest.path),
        installId: crash_platform.dvInstallId(appId),
        release: release,
        platform: platform.dvLogPlatformName(),
        level: config.shipLevel,
        batch: config.shipBatch,
      );
    }
    core.DV.ObservabilityAndLogging.useLogging(
      sinks: <DVLogSink>[?native, ?shipper, _CrashBreadcrumbSink()],
      level: config.level,
    );
    return _installed =
        DVLogInstallation._(file: file, native: native, shipper: shipper);
  } on Object {
    return null;
  }
}

/// Forgets the installation. For tests.
void dvResetApplicationLogging() {
  _installed?.shipper?.close();
  _installed = null;
  core.DV.ObservabilityAndLogging.resetLogging();
}
