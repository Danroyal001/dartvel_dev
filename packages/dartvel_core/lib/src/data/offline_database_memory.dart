import '../database/adapter.dart';

/// Neither dart:io nor a browser: nowhere that survives a restart.
Future<DVDatabaseAdapter> dvOpenLocalOfflineDatabase(
  String appId, {
  String? directory,
  String? os,
  Map<String, String>? environment,
  String? androidStateDirectory,
}) async =>
    MemoryDVDatabaseAdapter();
