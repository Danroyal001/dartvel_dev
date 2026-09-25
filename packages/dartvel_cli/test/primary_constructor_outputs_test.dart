// Generated classes are written with primary constructors.
//
// A generated model is the class an application reads most, in its editor
// and in a stack trace, and it restated every field three times: once as a
// field, once as `required this.name`, and once in the input it came from.
// Declared in the header it is stated once, as the samples and the scaffold
// now write their own classes. Nothing about how it is called changes:
// named, required, const where the input is const.
import 'dart:io';

import 'package:dartvel_cli/src/generators/job_generator.dart';
import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> _generate(
  String relative,
  String source,
  Future<void> Function(String root) run,
  String output,
) async {
  final Directory root = await Directory.systemTemp.createTemp(
    'dartvel_primary_out_',
  );
  addTearDown(() => root.deleteSync(recursive: true));
  final File input = File(
    p.joinAll(<String>[root.path, ...relative.split('/')]),
  );
  input.parent.createSync(recursive: true);
  input.writeAsStringSync(source);
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  await run(root.path);
  return File(p.join(root.path, 'lib', 'dartvel_client', output))
      .readAsStringSync();
}

Future<String> _models(String source) => _generate(
  'lib/models/model.dart',
  source,
  (String root) => ModelGenerator.generate(
    root: root,
    pkgName: 'shop',
    buildId: 'test-build',
  ),
  'models.g.dart',
);

void main() {
  group('a generated data model', () {
    late String generated;
    setUpAll(() async {
      final Directory root = await Directory.systemTemp.createTemp(
        'dartvel_primary_out_',
      );
      try {
        Directory(p.join(root.path, 'lib', 'models'))
            .createSync(recursive: true);
        Directory(p.join(root.path, 'lib', 'dartvel_client'))
            .createSync(recursive: true);
        File(p.join(root.path, 'lib', 'models', 'order.dart'))
            .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class const _Order({
  required final String id,
  @DVModel.searchableField() required final String status,
  final String? note,
});
''');
        await ModelGenerator.generate(
          root: root.path,
          pkgName: 'shop',
          buildId: 'test-build',
        );
        generated = File(
          p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
        ).readAsStringSync();
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('declares its fields in a const primary constructor', () {
      expect(generated, contains('class const Order({'));
      expect(generated, contains('  required final String id,'));
      expect(generated, contains('  required final String? note,'));
      expect(generated, isNot(contains('required this.id')));
    });

    test('the test factory and the facets are declared the same way', () {
      expect(generated, contains('class const OrderFactory({'));
      expect(generated, contains('  final String? id,'));
      expect(generated, isNot(contains('    this.id,')));
      expect(
        generated,
        contains('class const OrderFacets({final List<String>? status});'),
      );
    });

    test('a model whose input is not const is not const', () async {
      final String plain = await _models('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Tag(final String id);
''');
      expect(plain, contains('class Tag({'));
      expect(plain, isNot(contains('class const Tag(')));
    });
  });

  test('a generated job payload is declared in its header', () async {
    final String jobs = await _generate(
      'lib/jobs/jobs.dart',
      '''
import 'package:dartvel_core/dartvel.dart';

@DVJob(queue: 'mail')
class const _SendReceipt({required final String orderId});
''',
      (String root) => JobGenerator.generate(root: root, pkgName: 'shop'),
      'jobs.g.dart',
    );
    expect(
      jobs,
      contains('class const SendReceipt({required final String orderId}) {'),
    );
    expect(jobs, isNot(contains('required this.orderId')));
  });
}
