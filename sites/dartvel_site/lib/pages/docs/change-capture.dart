import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel change capture: keep a warehouse in step with your data',
  description: 'Keep a reporting database in step with every insert, update '
      'and delete, in the order they happened, and let a destination '
      'that was down catch up.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsChangeCapturePage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docschangecapture,
      lead: <String>[
        'Keep a reporting database current with every insert, update and '
            'delete, in the order they happened.',
        'A destination that was down catches up from where it stopped.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'model',
          title: 'Say a model is captured',
          children: <Widget>[
            DocsText('One word on the model. Nothing else about it changes: '
                'you read and write it the way you read and write any other '
                'model, and saving a record is what records the change.'),
            DocsCode('capture-model'),
          ],
        ),
        DocsSection(
          id: 'log',
          title: 'Record every write in order',
          children: <Widget>[
            DocsText('One log for the process, configured where the database '
                'is. A model that says it is captured writes to it; a process '
                'that configured none writes normally and records nothing.'),
            DocsCode('capture-log'),
            Bullets(<String>[
              'Each change gets a sequence number, the record version, the '
                  'tenant and the transaction id.',
              'Inside DV.transaction a change is numbered only after commit. A '
                  'rollback leaves nothing in the log.',
              'If the log write fails, the model write is undone and '
                  'DVCaptureWriteError is thrown.',
            ]),
            DocsNote('Sensitive values stay out of the log',
                'The log names a sensitive field that changed and never stores '
                'its value.'),
          ],
        ),
        DocsSection(
          id: 'consumer',
          title: 'Copy changes to a warehouse',
          children: <Widget>[
            DocsCode('capture-consumer'),
            Bullets(<String>[
              'The checkpoint moves only after the destination accepts a batch. '
                  'A crash in between delivers the batch again with the same '
                  'change ids.',
              'DVWarehouseSink applies changes by record version, so a repeat '
                  'is harmless. It works over any SQL adapter that can add and '
                  'drop columns.',
              'A consumer that fell behind the retention window is refused with '
                  'DV-CDC-002 and needs a backfill.',
            ]),
          ],
        ),
        DocsSection(
          id: 'jobs',
          title: 'Run delivery on the job queue',
          children: <Widget>[
            DocsCode('capture-jobs'),
            DocsText('A refused batch throws inside the job, so the queue '
                'retries it with its backoff. A backfill runs one chunk per '
                'job.'),
          ],
        ),
        DocsSection(
          id: 'erasure',
          title: 'Erase a person from the copies too',
          children: <Widget>[
            DocsText('DVCapturePrivacyAdapter wipes the logged values for the '
                'rows an erasure reached and erases each destination. If one '
                'cannot be reached, the erasure is marked incomplete. See '
                'Privacy and erasure.'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Change Data Capture and Warehouse Sync',
                missing: <String>[
                  'No @DVModel(capture: true), so generated models capture '
                      'nothing until you pass a DVCapture to a record table.',
                  'Raw SQL writes that skip DVRecordTable are not captured.',
                  'No ClickHouse, BigQuery, Snowflake or Parquet destination.',
                ]),
          ],
        ),
      ],
    );
