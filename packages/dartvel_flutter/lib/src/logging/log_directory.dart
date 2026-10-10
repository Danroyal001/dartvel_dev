/// Where a device keeps its log file.
library;

import '../crashes/crash_directory.dart';

/// The directory the log file for [appId] goes in on [os], beside the crash
/// records -- so clearing the application's data clears both -- or null when
/// the platform gives no directory that survives a restart.
///
/// `DARTVEL_LOG_DIR` wins everywhere, for a deployment that mounts one.
String? dvLogDirectoryFor({
  required String appId,
  required String os,
  required Map<String, String> environment,
  String? androidStateDirectory,
}) {
  final String? declared = environment['DARTVEL_LOG_DIR']?.trim();
  if (declared != null && declared.isNotEmpty && declared != '/') {
    return declared;
  }
  final String? crashes = dvCrashDirectoryFor(
    appId: appId,
    os: os,
    // The crash override names the crash directory, not this one.
    environment: <String, String>{
      for (final MapEntry<String, String> entry in environment.entries)
        if (entry.key != 'DARTVEL_CRASH_DIR') entry.key: entry.value,
    },
    androidStateDirectory: androidStateDirectory,
  );
  if (crashes == null) return null;
  return '${crashes.substring(0, crashes.length - 'dartvel-crashes'.length)}'
      'dartvel-logs';
}
