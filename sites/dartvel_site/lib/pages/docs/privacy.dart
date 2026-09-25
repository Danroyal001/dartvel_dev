import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel privacy: export and erase personal data',
  description: 'Answer an export or deletion request with one call across '
      'every model that holds a person\'s data, and honour a browser '
      'that sends Sec-GPC.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsPrivacyPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsprivacy,
      lead: <String>[
        'Answer an export or deletion request with one call, across every model '
            'that holds the person\'s data.',
        'Declare on each model whose data it is and how long to keep it.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'declare',
          title: 'Declare the subject and retention',
          children: <Widget>[
            DocsCode('privacy-model'),
            DocsTable(columns: <String>[
              'Subject',
              'Means',
            ], rows: <List<String>>[
              <String>['DVSubject.self', 'The row is the person'],
              <String>["DVSubject.field('authorId')", 'A column holds the '
                  'person\'s id'],
              <String>["DVSubject.through('orderId', parent: 'Order')", 'The row '
                  'belongs to a row that belongs to the person'],
            ]),
            Bullets(<String>[
              'retain is DVRetention.days(n, from:, then:) or '
                  'DVRetention.indefinite.',
              'A model with personal data and no retention gets a '
                  'DV-PRIVACY-002 warning.',
            ]),
          ],
        ),
        DocsSection(
          id: 'erase',
          title: 'Export and erase a person\'s data',
          children: <Widget>[
            DocsCode('privacy-erase'),
            Bullets(<String>[
              'erase deletes rows, or keeps and anonymizes the ones a retention '
                  'holds.',
              'The result lists what was deleted, anonymized and kept, with a '
                  'receipt.',
              'It needs a database and DARTVEL_PRIVACY_KEY, 32 bytes or more as '
                  'hex or base64.',
            ]),
          ],
        ),
        DocsSection(
          id: 'opt-out',
          title: 'Honour a browser that says no to tracking',
          children: <Widget>[
            Bullets(<String>[
              'Every generated route reads Sec-GPC before the handler runs, so '
                  'a consent category declared tracking: true is already '
                  'denied while the header is in force.',
              'dvPrivacyOptOut is for what the application decides on top: what '
                  'it personalises, and what it hands to somebody else.',
              'It is a signal from the reader, so a page that ignores it is '
                  'making a choice, and the log line says which was served.',
            ]),
            DocsCode('privacy-opt-out'),
          ],
        ),
        DocsSection(
          id: 'cli',
          title: 'Do it from the CLI',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel privacy check',
              'dartvel privacy export --subject user:1042 --out user-1042.json',
              'dartvel privacy erase --subject user:1042 --reason "account '
                  'closed"',
              'dartvel privacy retention --plan',
            ]),
            Bullets(<String>[
              'The commands read DATABASE_URL, or the SQLite file '
                  'dartvel.database names. Erasing also needs '
                  'DARTVEL_PRIVACY_KEY.',
              'erase asks you to type yes at a terminal. In CI, or anywhere '
                  'nobody can answer, pass --yes. It refuses before deleting '
                  'anything when a table it reaches is missing.',
              'export will not replace a file already at --out unless you pass '
                  '--force.',
              'retention only runs with --plan, which changes nothing. The '
                  'sweep itself runs as a job.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Data Compliance and Lifecycle', missing: <String>[
              'Retention sweeps run on a fixed schedule.',
              'Export is a single JSON file and does not decrypt encrypted '
                  'fields.',
              'File storage, cache and crash data are not reached.',
            ]),
          ],
        ),
      ],
    );
