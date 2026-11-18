/// The analytics database a browser keeps between page loads.
///
/// The framework's, and not in the barrel an application imports.
library dartvel_core.analytics.local_database_snapshots;

import '../data/offline_database.dart';
import '../database/adapter.dart';
import 'consent.dart';
import 'product_analytics.dart';

/// The tables a browser keeps: the visitor's consent records and the install
/// id they belong to. Without them every page load is a stranger, and the
/// banner asks again on each one.
///
/// The event outbox and the stored events are not kept. They are written on
/// every tracked event, and a snapshot store rewrites a whole table on each
/// write; in a browser they are the session's, as they always were.
const Set<String> dvAnalyticsKeptTables = <String>{
  DVConsent.table,
  DVAnalytics.identityTable,
};

/// The analytics database over [snapshots], keeping [dvAnalyticsKeptTables].
Future<DVDatabaseAdapter> dvAnalyticsSnapshotDatabase(
  DVTableSnapshots snapshots,
) =>
    DVSnapshotDatabaseAdapter.open(snapshots, tables: dvAnalyticsKeptTables);
