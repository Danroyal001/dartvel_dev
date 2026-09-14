import '../database/adapter.dart';

Future<DVDatabaseAdapter> dvOpenLocalAnalyticsDatabase(
  String appId, {
  String? directory,
  String? os,
  Map<String, String>? environment,
  String? androidStateDirectory,
}) async =>
    MemoryDVDatabaseAdapter();
