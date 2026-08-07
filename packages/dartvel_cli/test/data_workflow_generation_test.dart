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
@pragma('vm:entry-point')
class _Order {
  final String id;
  final String status;

  const _Order({
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
      expect(content,
          isNot(contains("export 'package:workflow_app/models/order.dart'")));
      expect(content, contains('class Order {'));
      expect(content, contains('const Order({'));
      expect(content, contains('static Widget Form(Order model, [void Function(Order)? onSubmit])'));
      expect(content, contains('static Widget List('));
      expect(content, contains('static Widget Table('));
      expect(
        content,
        contains('static const OrderPageComponent Page = OrderPageComponent._();'),
      );
      expect(content, contains('class OrderPageComponent'));
      expect(content, contains('static Widget Card(Order model)'));
      expect(content, isNot(contains('Widget OrderForm(Order model)')));
      expect(content, isNot(contains('Widget OrderList(')));
      expect(content, isNot(contains('Widget OrderTable(')));
      expect(content, isNot(contains('Widget OrderPage(')));
      expect(content, contains('class OrderImport'));
      expect(content, contains('class OrderFactory'));
      expect(content, contains('Map<String, Object?> toJson()'));
      expect(
        content,
        contains('static Order fromJson(Map<String, Object?> json)'),
      );
      expect(content, contains('final row = <String, Object?>{};'));
      expect(content, isNot(contains('dynamic')));
      expect(content, isNot(contains('var ')));
      expect(content, contains('final String? id;'));
      expect(content, contains('final String? status;'));
      expect(content,
          contains('bool get statusIsValid => status.trim().isNotEmpty;'));
      expect(content, isNot(contains('statusIsValid => true')));
      expect(content, contains('OrderFactory admin()'));
      expect(content, contains('Order create()'));
      expect(content, contains("status: status ?? 'active'"));
      expect(content, isNot(contains('Unsupported' 'Error')));
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
      expect(content, contains('registerDVModelFactory<Order>'));
      expect(content, contains('registerDVModelSerializer<Order>'));
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

  test('model factory generation supports typed collection defaults', () async {
    final root =
        await Directory.systemTemp.createTemp('dartvel_factory_defaults_test_');
    try {
      Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      File(p.join(root.path, 'lib', 'models', 'metric.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Metric {
  final List<double> scores;
  final Map<String, int> counts;
  final Map<String, bool> flags;

  const _Metric({
    required this.scores,
    required this.counts,
    required this.flags,
  });
}
''');

      await ModelGenerator.generate(
        root: root.path,
        pkgName: 'workflow_app',
        buildId: 'test-build',
      );

      final content = File(
        p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
      ).readAsStringSync();
      expect(content, contains('scores: scores ?? const <double>[1.0]'));
      expect(content,
          contains("counts: counts ?? const <String, int>{'test': 1}"));
      expect(
        content,
        contains("flags: flags ?? const <String, bool>{'test': true}"),
      );
      expect(content, isNot(contains('Unsupported' 'Error')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('model factory generation rejects unsupported required defaults',
      () async {
    final root =
        await Directory.systemTemp.createTemp('dartvel_factory_error_test_');
    try {
      Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      File(p.join(root.path, 'lib', 'models', 'account.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

class Profile {
  const Profile();
}

@DVModel()
class _Account {
  final Profile profile;

  const _Account({
    required this.profile,
  });
}
''');

      // Awaited: generate() is async, and the finally below deletes the
      // fixture out from under it — the read then fails with a path error
      // instead of the StateError this is checking for.
      await expectLater(
        () => ModelGenerator.generate(
          root: root.path,
          pkgName: 'workflow_app',
          buildId: 'test-build',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(
              'Cannot generate AccountFactory default for required field '
              'Account.profile of type Profile',
            ),
          ),
        ),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('model generation rejects public annotated model inputs', () async {
    final root =
        await Directory.systemTemp.createTemp('dartvel_public_model_test_');
    try {
      Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      File(p.join(root.path, 'lib', 'models', 'user.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class User {
  final String id;

  const User({required this.id});
}
''');

      // Awaited: generate() is async, and the finally below deletes the
      // fixture out from under it — the read then fails with a path error
      // instead of the StateError this is checking for.
      await expectLater(
        () => ModelGenerator.generate(
          root: root.path,
          pkgName: 'workflow_app',
          buildId: 'test-build',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Dartvel model generation inputs must be private'),
          ),
        ),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
