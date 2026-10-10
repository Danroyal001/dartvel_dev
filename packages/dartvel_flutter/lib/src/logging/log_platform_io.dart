import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show DVLogConfig, DVLogFile, DVRotatingLogFile;

import '../platform/device_runtime.dart';
import 'log_directory.dart';

DVLogFile? dvDefaultLogFile(String appId, DVLogConfig config) {
  final String? directory = dvLogDirectoryFor(
    appId: appId,
    os: Platform.operatingSystem,
    environment: Platform.environment,
    androidStateDirectory: DVDeviceRuntime.stateDirectory,
  );
  if (directory == null) return null;
  return DVRotatingLogFile(
    directory,
    maxBytes: config.fileMaxBytes,
    files: config.fileCount,
    retention: config.fileRetention,
  );
}

bool dvLogHostedByTestRunner() => Platform.environment['FLUTTER_TEST'] == 'true';
String dvLogPlatformName() => Platform.operatingSystem;
