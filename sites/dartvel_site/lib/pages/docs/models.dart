import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel models: storage, forms, tables, admin and pages', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsModelsPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsmodels,
      lead: <String>[
        'Declare a class once and get storage, a form, a table, an admin '
            'screen and public pages.',
        'Every generated name is public, so your code never touches the '
            'private class.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'declare',
          title: 'Declare a model',
          children: <Widget>[
            DocsCode('models-article'),
            Bullets(<String>[
              'Put it under lib/models, one model per file, as a private class '
                  'with final fields.',
              'The key is the slug field, else id, else the first String '
                  'field.',
              'Rows live in a table named after the class in lower case plus '
                  's: articles.',
            ]),
            DocsNote('Pick a name Dartvel does not use',
                'Dartvel exports Get, Post, Put, Patch and Delete. A model with '
                'one of those names clashes with them in your code, so call it '
                'Article or BlogPost.'),
          ],
        ),
        DocsSection(
          id: 'options',
          title: 'Model options',
          children: <Widget>[
            DocsTable(columns: <String>[
              'Parameter',
              'What it does',
            ], rows: <List<String>>[
              <String>['generatePublicPages: true', 'A public page per record, '
                  'at /articles/:slug'],
              <String>['publicPathsResolver: fn', 'Your function lists the '
                  'paths to render statically'],
              <String>['history: DVHistory(...)', 'Keeps each version, with '
                  'history() and revert()'],
              <String>['softDelete: true', 'destroy() hides the row and '
                  'restore() brings it back'],
              <String>['version: false', 'Turns off the stale-write check'],
              <String>['searchable: true', 'Generates ArticleSearch'],
              <String>['tenantScoped: true', 'Rows belong to the current '
                  'tenant'],
              <String>['subject:, retain:', 'Who the data is about and how long '
                  'to keep it'],
            ]),
          ],
        ),
        DocsSection(
          id: 'fields',
          title: 'Field annotations',
          children: <Widget>[
            DocsTable(columns: <String>[
              'Annotation',
              'Effect',
            ], rows: <List<String>>[
              <String>['@DVModel.pageTitle()', 'The title on its public page'],
              <String>['@DVModel.mainContent()', 'The body of its public page'],
              <String>['@DVModel.featuredImage()', 'The image for the page and '
                  'link previews'],
              <String>['@DVModel.pageOrder(n)', 'Where the field sits on the '
                  'page'],
              <String>['@DVModel.hideFromPage()', 'Leaves the field off the '
                  'page'],
              <String>['@DVModel.searchableField()', 'Indexes the field for '
                  'search'],
              <String>['@DVModel.sensitiveField()', 'Kept out of logs, tables, '
                  'pages and public JSON'],
              <String>['@DVModel.model3dField()', 'A 3D asset with a poster'],
              <String>['@DVModel.retain(years:, because:)', 'Keeps one field '
                  'longer, with the reason'],
            ]),
          ],
        ),
        DocsSection(
          id: 'crud',
          title: 'Save, find and delete records',
          children: <Widget>[
            DocsCode('models-crud'),
            Bullets(<String>[
              'Model.all(), Model.find(key) and model.save() read and write '
                  'through DV.Database.',
              'copyWith keeps the version you read, so save() can spot a newer '
                  'write.',
              'Create tables with dartvel db migrate. See Database.',
            ]),
          ],
        ),
        DocsSection(
          id: 'widgets',
          title: 'Use the generated form, table and page',
          children: <Widget>[
            DocsCode('models-widgets'),
            Bullets(<String>[
              'Article.Form(model, onSubmit) edits every field. Without onSubmit '
                  'it shows no buttons.',
              'Article.Table(rows) sorts by column and skips sensitive fields.',
              'Article.Page has .sync, .async, .signal and .fromId.',
            ]),
          ],
        ),
        DocsSection(
          id: 'admin',
          title: 'Add an admin screen',
          children: <Widget>[
            DocsCode('models-admin-page'),
            Bullets(<String>[
              'Article.Admin() lists, creates, edits and deletes rows.',
              'It checks the Article.create, Article.update and Article.delete '
                  'policies.',
              'dartvel admin generate writes admin pages to '
                  'lib/pages/_dartvel_admin.',
            ]),
          ],
        ),
        DocsSection(
          id: 'model-pages',
          title: 'Serve a public page per record',
          children: <Widget>[
            DocsText('With generatePublicPages: true, each record gets a page '
                'at the plural kebab-case path of the model, and dartvel build '
                'web renders published ones statically.'),
            DocsCode('models-page-from-id'),
            DocsSubheading('List the static paths yourself'),
            DocsCode('models-paths-resolver'),
            DocsStatus('Generated Model Pages', missing: <String>[
              'A favicon taken from a record\'s featured image is not built.',
            ]),
          ],
        ),
        DocsSection(
          id: 'versions',
          title: 'Catch stale writes',
          children: <Widget>[
            DocsText('Each save checks the version you read. A newer write in '
                'between throws DVConflictError.'),
            DocsCode('models-conflict'),
            DocsText('DVConflict also has serverWins, fieldMerge and '
                'DVConflict.resolver(...).'),
          ],
        ),
        DocsSection(
          id: 'history',
          title: 'Keep and revert record history',
          children: <Widget>[
            DocsCode('models-history'),
            DocsStatus('Record History and Optimistic Concurrency',
                missing: <String>[
                  'Forms do not reload and merge on a conflict yet.',
                  'No Studio history view, scheduled prune or database-level '
                      'atomic transactions.',
                ]),
          ],
        ),
        DocsSection(
          id: 'soft-delete',
          title: 'Soft delete and restore',
          children: <Widget>[
            DocsCode('models-soft-delete'),
          ],
        ),
        DocsSection(
          id: 'search',
          title: 'Search records',
          children: <Widget>[
            DocsCode('models-search'),
            Bullets(<String>[
              'Set a provider before you query. With none, a query throws.',
              'DVPostgresSearchProvider searches with Postgres full text.',
            ]),
          ],
        ),
        DocsSection(
          id: 'sensitive',
          title: 'Protect sensitive fields',
          children: <Widget>[
            Bullets(<String>[
              'A sensitive field needs subject: on the model, or the build '
                  'stops with DV-PRIVACY-001.',
              'encrypted: true encrypts a String field with keys from '
                  'DARTVEL_FIELD_KEYS.',
              'onErase: DVErase.anonymize keeps the row and blanks the field '
                  'on erasure.',
            ]),
            DocsStatus('Sensitive Model Fields', missing: <String>[
              'Raw SQL, imports and backfills store encrypted fields as plain '
                  'text.',
              'No key rotation, and showInAdmin does not gate anything yet.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Models'),
          ],
        ),
      ],
    );
