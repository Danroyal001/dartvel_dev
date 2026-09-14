/// The database a device keeps its own consent and analytics outbox in.
///
/// Consent belongs to the install and is asked before anybody signs in, so it
/// is kept on the device rather than in whatever database the application
/// talks to.
library dartvel_core.analytics.local_database;

import 'dart:async';

import '../database/adapter.dart';
import 'local_database_memory.dart'
    if (dart.library.io) 'local_database_io.dart' as platform;

export 'analytics_directory.dart' show dvAnalyticsDirectoryFor;

/// Opens this application's device-local analytics database.
///
/// A SQLite file in [directory], or where [dvAnalyticsDirectoryFor] says for
/// this platform, on platforms with `dart:io`. It is held in memory instead,
/// writing nothing, on the web (no SQLite), when the platform gives no
/// directory that survives a restart, and under `flutter test`, where an
/// application's widget tests would otherwise write into the developer's own
/// data directory. A database in memory loses the choice at exit, so the
/// person is asked again: the direction that records no consent nobody gave.
///
/// [environment] and [os] default to the running process's; [appId] names
/// the file and must be a plain name.
Future<DVDatabaseAdapter> dvLocalAnalyticsDatabase(
  String appId, {
  String? directory,
  String? os,
  Map<String, String>? environment,
  String? androidStateDirectory,
}) {
  if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(appId) ||
      appId == '.' ||
      appId == '..') {
    throw ArgumentError.value(appId, 'appId', 'must be a plain name');
  }
  return platform.dvOpenLocalAnalyticsDatabase(
    appId,
    directory: directory,
    os: os,
    environment: environment,
    androidStateDirectory: androidStateDirectory,
  );
}
