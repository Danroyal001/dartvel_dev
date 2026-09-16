import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Testing Dartvel apps with DV.Test fakes', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsTestingPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docstesting,
      lead: <String>[
        'Test mail, HTTP calls and jobs without a network or a server.',
        'Each DV.Test fake returns an object you can assert on.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'example',
          title: 'A test with fakes',
          children: <Widget>[
            DocsCode('testing-fakes'),
            DocsShell(<String>[
              'dartvel test',
              'dartvel test --watch',
            ]),
          ],
        ),
        DocsSection(
          id: 'fakes',
          title: 'The fakes',
          children: <Widget>[
            DocsTable(columns: <String>[
              'Call',
              'Gives you',
            ], rows: <List<String>>[
              <String>['DV.Test.fakeMail()', 'DVMemoryMailProvider, with .sent'],
              <String>['DV.Test.fakeNotifications()',
                  'DVMemoryNotificationProvider, with .sent'],
              <String>['DV.Test.fakeHttp({...})', 'DVHttpFake, with .calls, '
                  'answering from DVHttpStub'],
              <String>['DV.Test.fakeQueue()', 'An in-memory queue'],
              <String>['DV.Test.fakeDatabase()', 'MemoryDVDatabaseAdapter'],
              <String>['DV.Test.fakeStorage()', 'DVMemoryFileStorageAdapter'],
              <String>['DV.Test.fakeAuthUser()', 'A DVAuthUser for asUser(...)'],
              <String>['DV.Test.withSecrets({...}, body)', 'Secrets for the '
                  'length of body'],
            ]),
            Bullets(<String>[
              'DVHttpStub has json, text, status, timeout, error and sequence.',
              'A host with no stub fails the call, so a test never reaches the '
                  'network.',
              'There is no cache fake. Configure DVMemoryCacheAdapter instead.',
            ]),
          ],
        ),
        DocsSection(
          id: 'reset',
          title: 'Reset between tests',
          children: <Widget>[
            DocsText('DV.Test has resetQueues, resetMail, resetNotifications, '
                'resetPolicies, resetCacheTags, resetAuth and resetStorage. '
                'Call DVHttp.reset after an HTTP fake.'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Testing'),
          ],
        ),
      ],
    );
