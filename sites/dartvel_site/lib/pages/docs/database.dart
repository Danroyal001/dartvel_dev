import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel database: SQLite, Postgres, MySQL and migrations', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsDatabasePage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsdatabase,
      lead: <String>[
        'Start on a SQLite file and move to Postgres or MySQL with one line.',
        'Your models create their tables through dartvel db migrate.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'sqlite',
          title: 'Use SQLite locally',
          children: <Widget>[
            DocsCode('database-configure'),
            Bullets(<String>[
              'SqliteDVDatabaseAdapter.file(path) turns on WAL mode and foreign '
                  'keys by default.',
              'SqliteDVDatabaseAdapter.memory() is a database for tests.',
              'MemoryDVDatabaseAdapter() needs no SQLite and understands simple '
                  'queries only.',
            ]),
          ],
        ),
        DocsSection(
          id: 'postgres-mysql',
          title: 'Connect to Postgres or MySQL',
          children: <Widget>[
            DocsCode('database-postgres'),
            DocsCode('database-mysql'),
            Bullets(<String>[
              'Both take sslMode, which defaults to prefer.',
              'DVDatabaseConnection.parse(url) opens postgres://, mysql://, '
                  'mariadb:// and sqlite:// URLs.',
            ]),
            DocsNote('The backend reads DATABASE_URL for queues and schedules',
                'A server process opens DATABASE_URL for its job queue and '
                'schedule leases. Configure DV.Database yourself for your '
                'models.'),
          ],
        ),
        DocsSection(
          id: 'queries',
          title: 'Run SQL directly',
          children: <Widget>[
            DocsCode('database-query'),
            Bullets(<String>[
              'Values are always bound parameters.',
              'On a tenant-scoped table, a query without dv_tenant is refused.',
            ]),
          ],
        ),
        DocsSection(
          id: 'migrate',
          title: 'Create tables with dartvel db migrate',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel db migrate            # apply to the SQLite file',
              'dartvel db migrate --plan     # classify each change, apply none',
              'dartvel db migrate --dry-run  # plan and gate, apply nothing',
            ]),
            Bullets(<String>[
              'Generation writes each model\'s schema. You write no migration '
                  'files.',
              'On SQLite it creates missing tables and adds missing columns. It '
                  'never drops a column.',
              'On Postgres and MySQL it writes .dart_tool/dartvel_migration.sql '
                  'for you to apply.',
            ]),
            DocsShell(<String>[
              '# pubspec.yaml',
              'dartvel:',
              '  database:',
              '    provider: sqlite     # the default',
              '    path: dartvel.db     # the default',
            ]),
          ],
        ),
        DocsSection(
          id: 'production',
          title: 'Migrate production safely',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel db migrate --production',
              'dartvel db migrate --dry-run --against snapshot',
              'dartvel db migrate --production --allow-blocking="backfill window"',
            ]),
            Bullets(<String>[
              '--production refuses a blocking change unless you pass '
                  '--allow-blocking with a reason.',
              'The reason is logged to .dartvel/db/schema_overrides.jsonl.',
              '--against snapshot rehearses against '
                  '.dartvel/db/production.snapshot.json.',
            ]),
            DocsStatus('Schema Evolution', missing: <String>[
              'No command captures a production snapshot yet.',
              'Expand and contract steps are planned, and not run as SQL.',
            ]),
          ],
        ),
        DocsSection(
          id: 'records',
          title: 'Store records without writing SQL',
          children: <Widget>[
            DocsText('A page, a saved report, an audit entry: data that is '
                'not a model still has to be stored. Records are how the '
                'framework stores its own, and they name no SQL, so the same '
                'code runs on SQLite, PostgreSQL, MySQL and, when it lands, '
                'MongoDB.'),
            DocsCode('records-shape'),
            DocsText('Write through DV.Database.records. An update carries '
                'the version it read in its filter. A lost update comes back '
                'as a count of nought, and nothing is overwritten:'),
            DocsCode('records-write'),
            DocsText('Reads take the same filters, with order, paging and a '
                'count:'),
            DocsCode('records-read'),
            DocsStatus('Storage-Neutral Records', missing: <String>[
              'Models still go through DVRecordTable, which writes SQL.',
              'There is no MongoDB engine yet.',
            ]),
          ],
        ),
        DocsSection(
          id: 'tenants',
          title: 'Add a tenant column to existing rows',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel db migrate --tenant acme',
            ]),
            DocsText('Adding tenantScoped: true to a model with rows needs to '
                'know whose rows they are. --orphan-existing-rows hides them '
                'instead, for a staging database.'),
          ],
        ),
        DocsSection(
          id: 'seed',
          title: 'Seed data and inspect schemas',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel db seed          # runs lib/database/seed.dart or tool/seed.dart',
              'dartvel db pull --local  # suggests @DVModel classes from drift, '
                  'isar or sqflite',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Database', missing: <String>[
              'dartvel db migrate applies changes to SQLite only.',
            ]),
          ],
        ),
      ],
    );
