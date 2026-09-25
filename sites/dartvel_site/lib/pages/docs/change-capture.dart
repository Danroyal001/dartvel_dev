import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel change capture: keep a warehouse in step with your data',
  description: 'Mark a data model as captured, name a destination in '
      'pubspec.yaml, and every insert, update and delete reaches it in the '
      'order it happened, with a destination that was down catching up.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsChangeCapturePage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docschangecapture,
      lead: <String>[
        'Keep a reporting store current with every insert, update and '
            'delete, in the order they happened.',
        'You mark a data model as captured and name where its copies go. '
            'Dartvel records the writes, delivers them, and catches a '
            'destination up after it was down.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'model',
          title: 'Mark a data model as captured',
          children: <Widget>[
            DocsText('Add capture: true to the data model. You read and '
                'write it the same way as before. Saving a record also '
                'records the change.'),
            DocsCode('capture-model'),
          ],
        ),
        DocsSection(
          id: 'destinations',
          title: 'Say where the copies go',
          children: <Widget>[
            DocsText('Destinations go under dartvel.capture in pubspec.yaml. '
                'This is the only other thing you write.'),
            DocsCode('capture-config'),
            Bullets(<String>[
              'connection is the name of a secret. The value stays out of the '
                  'pubspec, and the server reads WAREHOUSE_URL from its environment when it starts. A '
                  'URL written into the pubspec stops the build with '
                  'DV-CDC-007.',
              'type: database copies each data model into another database, '
                  'one collection per model, holding the newest version of '
                  'each record.',
              'models is optional. Leave it out and the destination gets '
                  'every captured data model. A name that is not a captured '
                  'data model stops the build with DV-CDC-008.',
              'retention is how long the log keeps a delivered change. It '
                  'defaults to 7d. lagThreshold is optional.',
              'A misspelt setting, an unknown type or a duration without a '
                  'unit stops the build with DV-CDC-006.',
            ]),
          ],
        ),
        DocsSection(
          id: 'order',
          title: 'What a destination receives',
          children: <Widget>[
            Bullets(<String>[
              'Changes arrive in commit order, each with a sequence number, '
                  'the record version, the tenant and the transaction id.',
              'Deletes, soft deletes and restores are changes too, so a copy '
                  'never keeps a record the source removed.',
              'Inside DV.transaction a change is recorded only when the '
                  'transaction commits. A rollback delivers nothing.',
              'A change is applied by record version. A repeat or a late '
                  'arrival cannot replace newer data.',
              'Writes made in Studio, and a device\'s offline writes '
                  'replayed on the server, are captured like any other save.',
            ]),
            DocsNote('Sensitive values never leave',
                'A change names a sensitive field that changed but never '
                    'carries its value. The log does not store it, and no '
                    'destination has a place for it.'),
            DocsText('If a change cannot be recorded, the save is undone and '
                'throws DVCaptureWriteError. A saved record always has its '
                'change in the log.'),
          ],
        ),
        DocsSection(
          id: 'delivery',
          title: 'Delivery, retries and backfill',
          children: <Widget>[
            DocsText('The server delivers on the job queue. Each destination '
                'has its own queue, so one that is down does not hold up the '
                'others.'),
            Bullets(<String>[
              'A refused batch is retried with a backoff and the same change '
                  'ids. Nothing is skipped.',
              'A destination with no copy yet is backfilled from the records '
                  'already stored, in chunks, one job each. So is a data model '
                  'you add to a destination later. The copy then follows new '
                  'changes from where it began.',
              'A destination that was down for longer than the retention '
                  'window is backfilled again, so it never has a gap '
                  '(DV-CDC-002).',
              'If a destination\'s secret is not set, the server says so with '
                  'DV-CDC-009 and delivers to the others. Its changes wait in '
                  'the log until the retention window passes.',
              'A server started without a role runs these jobs itself. In a '
                  'deployment with worker processes, the workers run them.',
            ]),
          ],
        ),
        DocsSection(
          id: 'lag',
          title: 'Watch the lag',
          children: <Widget>[
            DocsText('The server measures how far behind each destination is '
                'and reports it at /metrics as dartvel_dv_capture_lag_seconds and '
                'dartvel_dv_capture_lag_changes. Past lagThreshold it logs '
                'DV-CDC-003, so a copy that is hours old is noticed.'),
          ],
        ),
        DocsSection(
          id: 'erasure',
          title: 'Erasure reaches the copies',
          children: <Widget>[
            DocsText('When DV.Privacy erases a person, the logged values for '
                'their records are removed and every destination drops its '
                'copy at the same time, without waiting for the next '
                'delivery. If a destination cannot be reached, the erasure is '
                'marked incomplete. See Privacy and erasure.'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Change Data Capture and Warehouse Sync',
                missing: <String>[
                  'No ClickHouse, BigQuery, Snowflake or Parquet destination.',
                  'No Studio view of lag or backfill progress.',
                  'A backfill of a data model separated by schema per tenant '
                      'copies only the default tenant\'s records.',
                ]),
          ],
        ),
      ],
    );
