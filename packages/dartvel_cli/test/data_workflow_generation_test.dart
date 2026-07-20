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
      expect(content, contains('class OrderExport'));
      expect(content, contains('static DVExportResult csv'));
      expect(content, contains('static DVExportResult json'));
      expect(content, contains('class OrderReport'));
      expect(content, contains('static DVReportResult monthly'));
      expect(content, contains('const convert.LineSplitter()'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
