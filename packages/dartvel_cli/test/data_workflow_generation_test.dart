import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('model generator emits import export and report facades', () async {
    final root =
        await Directory.systemTemp.createTemp('dartvel_data_workflow_test_');
    try {
      Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      File(p.join(root.path, 'lib', 'models', 'order.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class Order {
  final String id;
  final String status;

  const Order({
    required this.id,
    required this.status,
  });
}
''');

      await ModelGenerator.generate(
        root: root.path,
        pkgName: 'workflow_app',
        buildId: 'test-build',
      );

      final models = File(
        p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
      );
      final content = models.readAsStringSync();
      expect(content, contains('class OrderImport'));
      expect(content, contains('static DVImportResult<Order> csv'));
      expect(
          content,
          contains(
              'static Future<List<DVJobEnvelope<DVImportChunk>>> resumableCsv'));
      expect(content, contains('static DVImportResult<Order> ndjson'));
      expect(
          content,
          contains(
              'static Future<List<DVJobEnvelope<DVImportChunk>>> resumableNdjson'));
      expect(content, contains('static DVImportResult<Order> excel'));
      expect(content, contains('const DVQueues().dispatch<DVImportChunk>'));
      expect(content, contains('class OrderExport'));
      expect(content, contains('static DVExportResult csv'));
      expect(content, contains('static DVExportResult json'));
      expect(content, contains('static DVExportResult ndjson'));
      expect(content, contains('static DVExportResult excel'));
      expect(content, contains('DVExportOptions<Order> options'));
      expect(content, contains('static Stream<DVExportResult> streamCsv'));
      expect(content, contains('static Stream<DVExportResult> streamNdjson'));
      expect(content, contains('options.apply(items)'));
      expect(content, contains('metadata: options.exportMetadata()'));
      expect(content, contains('application/x-ndjson; charset=utf-8'));
      expect(content, contains('application/vnd.ms-excel; charset=utf-8'));
      expect(content, contains('class OrderReport'));
      expect(content, contains('static DVReportResult monthly'));
      expect(content, contains('static DVScheduledReport scheduleMonthly'));
      expect(
          content,
          contains(
              'static Future<DVJobEnvelope<DVScheduledReport>> dispatchMonthly'));
      expect(content, contains('const DVQueues().dispatch<DVScheduledReport>'));
      final parserStart = content.indexOf('class OrderParser');
      final formStart = content.indexOf('class OrderFormControls');
      final reportStart = content.indexOf('class OrderReport');
      final facetsStart = content.indexOf('List<String> _splitCsvLine');
      expect(parserStart, isNonNegative);
      expect(formStart, isNonNegative);
      expect(reportStart, isNonNegative);
      expect(facetsStart, isNonNegative);
      final parserBlock = content.substring(parserStart, formStart);
      final reportBlock = content.substring(reportStart, facetsStart);
      expect(parserBlock, isNot(contains('scheduleMonthly')));
      expect(reportBlock, contains('static DVScheduledReport scheduleMonthly'));
      expect(
          reportBlock,
          contains(
              'static Future<DVJobEnvelope<DVScheduledReport>> dispatchMonthly'));
      expect(content, contains('const convert.LineSplitter()'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
