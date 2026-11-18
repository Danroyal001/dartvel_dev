/// A browser's analytics database: consent and the install id in IndexedDB,
/// so the banner asks once rather than on every page load; the rest in
/// memory, as before.
library;

import '../data/offline_database_web.dart' show DVIndexedDbSnapshots;
import '../database/adapter.dart';
import '../observability/logging.dart' show DVLogLevel;
import '../observability/observability.dart' show DVObservability;
import 'local_database_snapshots.dart';

Future<DVDatabaseAdapter> dvOpenLocalAnalyticsDatabase(
  String appId, {
  String? directory,
  String? os,
  Map<String, String>? environment,
  String? androidStateDirectory,
}) async {
  try {
    return await dvAnalyticsSnapshotDatabase(
      await DVIndexedDbSnapshots.open('$appId.analytics'),
    );
  } catch (error) {
    // A private window in some browsers, or storage the visitor turned off.
    // Consent is then asked again on the next page load, which is the most
    // a page that may keep nothing can do.
    DVObservability.log(
      'IndexedDB could not be opened ($error); consent is kept in memory and '
      'asked again on the next page load.',
      level: DVLogLevel.warn,
    );
    return MemoryDVDatabaseAdapter();
  }
}
