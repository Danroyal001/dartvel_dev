import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel database: SQLite, Postgres, MySQL and migrations',
  description: 'Start on a SQLite file and move to Postgres or MySQL with one '
      'line. Your models create their own tables through dartvel db '
      'migrate.',
  showAppBar: false,
)
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
            DocsText('The database is configuration, not code. Put '
                'DATABASE_URL in .env and the generated backend opens it for '
                'your data models, jobs and schedules.'),
            DocsShell(<String>[
              '# .env',
              'DATABASE_URL=sqlite:dartvel.db',
            ]),
            Bullets(<String>[
              'SQLite turns on WAL mode and foreign keys.',
              'A web-server binary from dartvel build needs no DATABASE_URL. '
                  'It creates a SQLite file beside itself on its first run.',
              'dartvel db migrate reads dartvel.database in pubspec.yaml, '
                  'shown under the migrate section below.',
            ]),
          ],
        ),
        DocsSection(
          id: 'postgres-mysql',
          title: 'Connect to Postgres or MySQL',
          children: <Widget>[
            DocsText('Moving is one line. Set DATABASE_URL where the backend '
                'runs, and set the same engine as dartvel.database.provider so '
                'dartvel db migrate writes statements for it.'),
            DocsShell(<String>[
              'DATABASE_URL=postgres://shop:secret@db.internal/shop?sslmode=require',
            ]),
            DocsTable(columns: <String>[
              'Engine',
              'DATABASE_URL',
              'dartvel.database.provider',
            ], rows: <List<String>>[
              <String>['SQLite', 'sqlite:path/to/file.db', 'sqlite'],
              <String>['PostgreSQL', 'postgres:// or postgresql://',
                  'postgres'],
              <String>['MySQL and MariaDB', 'mysql:// or mariadb://', 'mysql'],
            ]),
            Bullets(<String>[
              'sslmode defaults to prefer. It also takes disable, require, '
                  'verify-ca and verify-full.',
              'DATABASE_URL is read from the environment, then the '
                  'supervisor\'s credentials, then .env, like any secret.',
              'Web, worker and cron processes all open it, so they share '
                  'your data, your jobs and your schedules.',
            ]),
          ],
        ),
        DocsSection(
          id: 'queries',
          title: 'Read and write through your data models',
          children: <Widget>[
            DocsText('Every read and write goes through a data model. The '
                'same calls run on every engine above.'),
            DocsCode('models-crud'),
            DocsNote('Raw SQL is leaving the application surface',
                'DV.Database.query and execute take a SQL string, which no '
                'engine but SQL can run. They are being removed in favour of '
                'model queries. Until those land, use Model.all, Model.find, '
                'save and destroy.'),
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
            DocsNote('Being replaced by data model queries',
                'Records are the framework\'s contract with its engines, not '
                'a way for an application to write data. They are leaving the '
                'application surface, and this section will be rewritten '
                'around model queries. Write through a data model instead.'),
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
              'Data models do not go through records yet, so a model runs '
                  'only on the engines in the table above.',
              'There is no model query API yet, so records are still in the '
                  'application surface.',
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
