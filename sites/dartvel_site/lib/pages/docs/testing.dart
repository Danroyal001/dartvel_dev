import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Testing Dartvel apps with DV.Test fakes',
  description: 'Test mail, HTTP calls, jobs and models without a network or a '
      'server. Each DV.Test fake returns an object you can assert on.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsTestingPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docstesting,
      lead: <String>[
        'Test mail, HTTP calls, jobs and models without a network or a server.',
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
              'There is no cache fake: in a test DV.Cache is in memory. Call '
                  'DV.Cache.delete(DVCache.all) in setUp.',
            ]),
          ],
        ),
        DocsSection(
          id: 'factories',
          title: 'Make records with generated factories',
          children: <Widget>[
            DocsCode('testing-factories'),
            Bullets(<String>[
              'Every @DVModel gets a Factory class with create, createMany and '
                  'admin.',
              'Ids, emails and slugs carry a sequence, so two records never '
                  'share one.',
              'resetSequence starts the count again, so a snapshot comes out '
                  'the same on every run.',
            ]),
          ],
        ),
        DocsSection(
          id: 'modes',
          title: 'Run one kind of test',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel test e2e',
              'dartvel test golden --update-goldens',
              'dartvel test --total-shards 4 --shard-index 0',
            ]),
            DocsTable(columns: <String>[
              'Mode',
              'Looks in',
            ], rows: <List<String>>[
              <String>['unit (the default)', 'test'],
              <String>['e2e', 'test/e2e, then integration_test'],
              <String>['golden', 'test/golden or test/goldens'],
              <String>['native', 'test/native, test/ffi or test/jni'],
              <String>['accessibility', 'test/accessibility or test/a11y'],
              <String>['release', 'test/release, then the e2e folders, then '
                  'test'],
            ]),
            DocsText('A mode with no tests says so and lists where it looked. '
                'It never runs the whole suite under that mode\'s name.'),
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
