import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel database: SQLite, Postgres, MySQL and migrations',
  description:
      'Start on a SQLite file and move to Postgres or MySQL with one '
      'line. Your models create their own tables through dartvel db '
      'migrate.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsDatabasePage(BuildContext context) => const DocsArticle(
  page: DVRoutes.docsdatabase,
  lead: <String>[
    'Start on a SQLite file and move to Postgres or MySQL with one line.',
    'Your models create their tables through `dartvel db migrate`.',
  ],
  sections: <DocsSection>[
    DocsSection(
      id: 'sqlite',
      title: 'Use SQLite locally',
      children: <Widget>[
        DocsText(
          'A web-server binary opens local SQLite automatically. '
          'To choose a different file, put '
          'DATABASE_URL in .env and the generated backend opens it for '
          'your data models, jobs and schedules.',
        ),
        DocsShell(<String>['# .env', 'DATABASE_URL=sqlite:dartvel.db']),
        Bullets(<String>[
          'SQLite turns on WAL mode and foreign keys.',
          'A binary from `dartvel build web-server` needs no '
              'DATABASE_URL. It keeps a SQLite file in dartvel_data beside '
              'itself, and DARTVEL_DATA_DIR moves that folder.',
          '`dartvel db migrate` reads dartvel.database in pubspec.yaml, '
              'shown under the migrate section below.',
        ]),
      ],
    ),
    DocsSection(
      id: 'postgres-mysql',
      title: 'Connect to Postgres or MySQL',
      children: <Widget>[
        DocsText(
          'Moving is one line. Set DATABASE_URL where the backend '
          'runs, and set the same engine as dartvel.database.provider so '
          '`dartvel db migrate` writes statements for it.',
        ),
        DocsShell(<String>[
          'DATABASE_URL=postgres://shop:secret@db.internal/shop?sslmode=require',
        ]),
        DocsTable(
          columns: <String>[
            'Engine',
            'DATABASE_URL',
            'dartvel.database.provider',
          ],
          rows: <List<String>>[
            <String>['SQLite', 'sqlite:path/to/file.db', 'sqlite'],
            <String>['PostgreSQL', 'postgres:// or postgresql://', 'postgres'],
            <String>['MySQL and MariaDB', 'mysql:// or mariadb://', 'mysql'],
          ],
        ),
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
        DocsText(
          'Every read and write goes through a data model. The '
          'same calls run on every engine above.',
        ),
        DocsCode('models-crud'),
        DocsText(
          'Use the generated data model for every create, update '
          'and delete. Storage configuration belongs to the framework.',
        ),
      ],
    ),
    DocsSection(
      id: 'migrate',
      title: 'Create tables with `dartvel db migrate`',
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
        DocsStatus(
          'Schema Evolution',
          missing: <String>[
            'No command captures a production snapshot yet.',
            'Expand and contract steps are planned, and not run as SQL.',
          ],
        ),
      ],
    ),
    DocsSection(
      id: 'records',
      title: 'Storage engine reference',
      children: <Widget>[
        DocsText(
          'Application data is read and written through generated '
          'data models. The framework keeps storage engine contracts '
          'behind those calls.',
        ),
        DocsStatus(
          'Storage-Neutral Records',
          missing: <String>[
            'Routing generated data models through the storage-neutral '
                'engine contract is Planned. The SQLite, Postgres and '
                'MySQL data model paths are built.',
            'A MongoDB engine is Planned.',
          ],
        ),
      ],
    ),
    DocsSection(
      id: 'tenants',
      title: 'Add a tenant column to existing rows',
      children: <Widget>[
        DocsShell(<String>['dartvel db migrate --tenant acme']),
        DocsText(
          'Adding tenantScoped: true to a model with rows needs to '
          'know whose rows they are. --orphan-existing-rows hides them '
          'instead, for a staging database.',
        ),
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
        DocsStatus(
          'Database',
          missing: <String>[
            '`dartvel db migrate` applies changes to SQLite only.',
          ],
        ),
      ],
    ),
  ],
);
