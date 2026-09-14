import 'dart:io';

import '../database/adapter.dart';
import '../database/sqlite_adapter_ffi.dart';
import '../observability/observability.dart';
import 'analytics_directory.dart';

Future<DVDatabaseAdapter> dvOpenLocalAnalyticsDatabase(
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
    if (env['FLUTTER_TEST'] == 'true') return MemoryDVDatabaseAdapter();
    dir = dvAnalyticsDirectoryFor(
      appId: appId,
      os: system,
      environment: env,
      androidStateDirectory: androidStateDirectory,
    );
    if (dir == null) {
      DVObservability.log(
        'analytics has no per-user data directory on $system, so consent is '
        'kept in memory and asked again next launch; set '
        'DARTVEL_ANALYTICS_DIR to keep it',
        level: DVLogLevel.warn,
      );
      return MemoryDVDatabaseAdapter();
    }
  }
  await Directory(dir).create(recursive: true);
  final String separator = system == 'windows' ? r'\' : '/';
  return SqliteDVDatabaseAdapter.file('$dir$separator$appId.analytics.sqlite');
}
