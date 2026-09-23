import '../dartvel_client/dartvel_client.dart';

Future<void> importCsv(String csv) async {
  // docs:start import-csv
  final DVImportResult<Article> result = Article.importCsv(csv);

  for (final DVImportRowError error in result.errors) {
    DV.log('Row ${error.row}: ${error.message}');
  }
  for (final Article article in result.items) {
    await article.save();
  }
  // docs:end
}

Future<void> resumableImport(String csv) async {
  // docs:start import-resumable
  // Handle each chunk in a worker. Every chunk carries the header row.
  DV.Jobs.register<DVImportChunk>((DVImportChunk chunk) async {
    final String rows = <String>[chunk.header!, ...chunk.rows].join('\n');
    for (final Article article in Article.importCsv(rows).items) {
      await article.save();
    }
  });

  // Split a large file into jobs of 500 rows on the imports queue.
  await Article.importResumableCsv(csv, queue: 'imports', chunkSize: 500);
  // docs:end
}

Future<void> exports(List<Article> articles) async {
  // docs:start export-files
  final DVExportResult csv = Article.exportCsv(
    articles,
    options: DVExportOptions<Article>(
      policyFilter: (Article article) => article.published,
    ),
  );
  await DV.FileStorage.put(csv.fileName, csv.bytes, contentType: csv.contentType);

  // Large exports in parts of 1,000 rows each.
  await for (final DVExportResult part in Article.exportStreamNdjson(articles)) {
    await DV.FileStorage.put('exports/${part.fileName}', part.bytes);
  }
  // docs:end
}

Future<void> reports(List<Article> articles) async {
  // docs:start export-reports
  final DVReportResult report = ArticleReport.monthly(articles);
  DV.log('${report.name}: ${report.metrics['count']} this month');

  // Queue a report job. The cron is parsed here and travels in the payload.
  await ArticleReport.dispatchMonthly(cron: '0 8 1 * *', queue: 'reports');
  // docs:end
}
