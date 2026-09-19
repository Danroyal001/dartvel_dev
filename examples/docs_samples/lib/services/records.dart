import '../dartvel_client/dartvel_client.dart';

/// Records: the storage-neutral way framework code and application code keep
/// data that is not a model — a page, a saved report, an audit entry.
///
/// Nothing here says SQL, so it runs on SQLite, PostgreSQL and MySQL today,
/// and on a document database when one is configured.

// docs:start records-shape
const DVRecordShape reports = DVRecordShape(
  collection: 'weekly_reports',
  key: 'id',
  fields: <String, DVFieldType>{
    'id': DVFieldType.text,
    'team': DVFieldType.text,
    'week': DVFieldType.integer,
    'hours': DVFieldType.real,
    'signedOff': DVFieldType.boolean,
  },
);
// docs:end

Future<void> writeReport() async {
  // docs:start records-write
  final DVRecordAdapter records = DV.Database.records;
  await records.ensure(reports);

  await records.insert('weekly_reports', <String, Object?>{
    'id': 'r-2026-38-design',
    'team': 'design',
    'week': 38,
    'hours': 121.5,
    'signedOff': false,
  });

  // An optimistic write: the filter names what was read, and nought changed
  // is the conflict.
  final int changed = await records.update(
    'weekly_reports',
    <String, Object?>{'signedOff': true},
    where: DVFilter.all(<DVFilter>[
      DVFilter.equals('id', 'r-2026-38-design'),
      DVFilter.equals('signedOff', false),
    ]),
  );
  if (changed == 0) {
    throw StateError('Somebody signed that week off first.');
  }
  // docs:end
}

Future<List<Map<String, Object?>>> teamReports(String team) async {
  // docs:start records-read
  final List<Map<String, Object?>> rows = await DV.Database.records.find(
    'weekly_reports',
    where: DVFilter.all(<DVFilter>[
      DVFilter.equals('team', team),
      DVFilter.compare('week', DVCompare.greaterOrEqual, 30),
    ]),
    orderBy: const <DVSort>[DVSort('week', descending: true)],
    limit: 10,
    fields: const <String>['id', 'week', 'hours'],
  );

  final int open = await DV.Database.records
      .count('weekly_reports', where: DVFilter.equals('signedOff', false));
  // docs:end
  if (open > 0) return rows;
  return rows;
}
