// docs:start backend-file
// lib/backend/functions/articles.csv.get.dart
import 'package:dartvel_core/dartvel.dart';

import '../../dartvel_client/dartvel_server.dart';

// GET /api/articles.csv downloads articles.csv.
@DVBackendFunction()
Future<DVExportResult> _articlesCsv() async =>
    Article.exportCsv(await Article.all(), fileName: 'articles.csv');
// docs:end
