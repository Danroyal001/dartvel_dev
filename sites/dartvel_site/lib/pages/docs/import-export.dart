import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel import and export: CSV, JSON, NDJSON, Excel and reports',
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
              <String>['Article.importJson', 'A JSON array of objects, as '
                  'exportJson writes it'],
              <String>['Article.importExcel', 'The Excel 2003 XML workbook '
                  'exportExcel writes, or tab-separated rows copied from a '
                  'spreadsheet, with a header row'],
            ]),
            Bullets(<String>[
              'A row that does not parse becomes a DVImportRowError. The other '
                  'rows still import.',
              'A row number is the line of the file the row starts on, '
                  'counting blank lines and line breaks inside quotes. In JSON '
                  'it is the position in the array.',
              'A field the file leaves out takes its declared default, so an '
                  'export without its sensitive fields imports back. A required '
                  'field with no default is a row error that names the field.',
              'Import builds models and saves nothing. You decide what to save.',
              'CSV is read the way export writes it: a quoted value keeps its '
                  'commas, quotes and line breaks, so a file you exported '
                  'imports back unchanged.',
              'CSV has no null: an empty cell reads as an empty string. Use '
                  'NDJSON when null and empty must stay different.',
              'A list, a map or another model as a field is rebuilt from '
                  'NDJSON element by element, through that model\'s own parser.',
            ]),
          ],
        ),
        DocsSection(
          id: 'resumable',
          title: 'Import a large file in chunks',
          children: <Widget>[
            DocsCode('import-resumable'),
            Bullets(<String>[
              'importResumableCsv and importResumableNdjson queue one '
                  'DVImportChunk job per chunk.',
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
              'exportCsv, exportJson, exportNdjson and exportExcel return a '
                  'DVExportResult with a file name, content type and bytes.',
              'exportExcel writes an Excel 2003 XML workbook, named .xls, '
                  'which importExcel reads back.',
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
