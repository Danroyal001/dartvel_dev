import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// The server answers a DVExportResult with the file itself, so the client
// gets the file back: no `required fromJson` mapper (there is no JSON to map),
// the bytes, type and name read from the response, and an error answer thrown
// rather than returned as the file. generated_client_analyzes_test compiles
// the same shape against the real API.
void main() {
  test('a DVExportResult function gives the caller the file', () async {
    final root = await Directory.systemTemp.createTemp('dartvel_export_client_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions')).createSync(recursive: true);
      File(p.join(root.path, 'lib', 'backend', 'functions', 'tracker.csv.get.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<DVExportResult> _trackerCsv() async => const DVExportResult(
      fileName: 'job-tracker.csv',
      contentType: 'text/csv',
      bytes: <int>[],
    );
''');
      File(p.join(root.path, 'lib', 'backend', 'functions', 'invoice.get.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
DVExportResult _invoice(String id) => DVExportResult(
      fileName: '\$id.pdf',
      contentType: 'application/pdf',
      bytes: const <int>[],
    );
''');
      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'export_client_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );
      final content = File(p.join(root.path, 'lib', 'dartvel_client', 'functions.g.dart')).readAsStringSync();
      final tracker = RegExp(r'Future<DVExportResult> trackerCsv\((.*)\) async \{').firstMatch(content);
      expect(tracker, isNotNull, reason: content);
      expect(tracker!.group(1), isNot(contains('fromJson')));
      expect(content, contains("return DVExportResult.fromHttpResponse(r, fallbackFileName: 'tracker.csv');"));
      final invoice = RegExp(r'Future<DVExportResult> invoice\((.*)\) async \{').firstMatch(content);
      expect(invoice, isNotNull, reason: content);
      expect(invoice!.group(1), isNot(contains('fromJson')));
      expect(content, contains("return DVExportResult.fromHttpResponse(r, fallbackFileName: 'invoice');"));
    } finally {
      await root.delete(recursive: true);
    }
  });
}
