import 'dart:io';

import '../analytics/analytics_directory.dart';
import '../database/adapter.dart';
import '../database/sqlite_adapter_ffi.dart';

Future<DVDatabaseAdapter> dvOpenLocalOfflineDatabase(
  String appId, {
  String? directory,
  String? os,
  Map<String, String>? environment,
  String? androidStateDirectory,
}) async {
  final Map<String, String> env = environment ?? Platform.environment;
  final String system = os ?? Platform.operatingSystem;
  String? dir = directory;
  if (dir == null) {
    // The store reports itself memory-backed (DV-OFFLINE-001) when it is
    // handed one, so nothing here needs to say so again.
    if (env['FLUTTER_TEST'] == 'true') return MemoryDVDatabaseAdapter();
    dir = dvAnalyticsDirectoryFor(
      appId: appId,
      os: system,
      environment: env,
      androidStateDirectory: androidStateDirectory,
      leaf: 'dartvel-offline',
      variable: 'DARTVEL_OFFLINE_DIR',
    );
    if (dir == null) return MemoryDVDatabaseAdapter();
  }
  await Directory(dir).create(recursive: true);
  final String separator = system == 'windows' ? r'\' : '/';
  return SqliteDVDatabaseAdapter.file('$dir$separator$appId.offline.sqlite');
}
