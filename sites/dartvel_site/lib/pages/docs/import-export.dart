import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel import and export: CSV, NDJSON, Excel and reports',
  description: 'Load a spreadsheet into a model and get back the rows that did '
      'not fit, with their row numbers. Export to CSV, JSON, NDJSON '
      'or Excel with sensitive fields left out.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsImportExportPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsimportexport,
      lead: <String>[
        'Load a spreadsheet into a model and get a list of the rows that did '
            'not fit, with their row numbers.',
        'Export the same model to CSV, JSON, NDJSON or Excel, with sensitive '
            'fields left out unless you ask for them.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'import',
          title: 'Import a CSV file',
          children: <Widget>[
            DocsCode('import-csv'),
            DocsTable(columns: <String>[
              'Call',
              'Reads',
            ], rows: <List<String>>[
              <String>['Article.importCsv', 'CSV with a header row'],
              <String>['Article.importNdjson', 'One JSON object per line'],
              <String>['Article.importExcel', 'Tab-separated rows copied from a '
                  'spreadsheet, with a header row'],
            ]),
            Bullets(<String>[
              'A row that does not parse becomes a DVImportRowError. The other '
                  'rows still import.',
              'Import builds models and saves nothing. You decide what to save.',
            ]),
          ],
        ),
        DocsSection(
          id: 'resumable',
          title: 'Import a large file in chunks',
          children: <Widget>[
            DocsCode('import-resumable'),
            Bullets(<String>[
              'resumableCsv and resumableNdjson queue one DVImportChunk job per '
                  'chunk.',
              'Each chunk carries its first row number and the header, so any '
                  'worker can take any chunk.',
              'Dartvel does not register the chunk handler. Register it as '
                  'above.',
            ]),
          ],
        ),
        DocsSection(
          id: 'export',
          title: 'Export to a file',
          children: <Widget>[
            DocsCode('export-files'),
            Bullets(<String>[
              'csv, json, ndjson and excel return a DVExportResult with a file '
                  'name, content type and bytes.',
              'excel writes an Excel 2003 XML workbook, named .xls.',
              'Sensitive fields are left out unless includeSensitiveFields: '
                  'true.',
            ]),
            DocsNote('Read and export as the same tenant',
                'An export whose tenantId differs from the current tenant is '
                'refused. Run the query and the export inside '
                'DV.withTenant(...) so the file holds the rows its label says.'),
          ],
        ),
        DocsSection(
          id: 'reports',
          title: 'Build a monthly report',
          children: <Widget>[
            DocsCode('export-reports'),
            Bullets(<String>[
              'monthly counts the records you pass for a month.',
              'scheduleMonthly and dispatchMonthly refuse a cron that does not '
                  'parse, at the line that declares it.',
              'You register the handler that builds a queued report.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Data Import, Export, and Reporting', missing: <String>[
              'No PDF export.',
              'No streaming import: a file is read whole before its rows '
                  'are chunked onto the queue.',
            ]),
          ],
        ),
      ],
    );
