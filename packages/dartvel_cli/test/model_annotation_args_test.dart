// Two ways a model annotation was read wrongly, both silent.
//
// The first is the one @DVPage had: `@DVModel\s*\([^)]*\)` stops at the first
// close parenthesis, and a string argument can contain one --
// `schemaType: 'Product (beta)'`. The model is then not discovered at all:
// no generated class, no table, no admin row, on a build that succeeds.
//
// The second is worse, because it changes what a model that was found does.
// tenantScoped was read from the whole file rather than from the model's own
// arguments, so one tenant-scoped model made every model in the file
// tenant-scoped. The generator's own comment names the case it breaks -- "a
// currency list, a country table" -- and the symptom is not a leak but the
// opposite: rows written before the column existed belong to no tenant, so
// every one of them disappears for every tenant.
import 'dart:io';
import 'dart:math' show min;

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> _generate(String source) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_model_args_');
  try {
    Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
    Directory(
      p.join(root.path, 'lib', 'dartvel_client'),
    ).createSync(recursive: true);
    File(
      p.join(root.path, 'lib', 'models', 'catalogue.dart'),
    ).writeAsStringSync(source);

    await ModelGenerator.generate(
      root: root.path,
      pkgName: 'model_args_app',
      buildId: 'test-build',
    );

    return File(
      p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
    ).readAsStringSync();
  } finally {
    root.deleteSync(recursive: true);
  }
}

void main() {
  test('a parenthesis inside a string argument does not end the annotation',
      () async {
    // Otherwise the model is not found: no class, no table, no error.
    final String generated = await _generate('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(schemaType: 'Product (beta)')
class _Product {
  final String id;
  const _Product({required this.id});
}
''');

    expect(generated, contains('class Product'));
  });

  test('one tenant-scoped model does not scope its neighbours', () async {
    // A currency table is the generator's own example of what a predicate
    // it never asked for would break, and it is in this file only because
    // somebody put two models in one file.
    final String generated = await _generate('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(tenantScoped: true)
class _Order {
  final String id;
  const _Order({required this.id});
}

@DVModel()
class _Currency {
  final String code;
  const _Currency({required this.code});
}
''');

    final int currency = generated.indexOf('class Currency');
    final int order = generated.indexOf('class Order');
    expect(currency, greaterThan(-1));
    expect(order, greaterThan(-1));

    // Bounded to each model's own generated code, because dv_tenant appears
    // legitimately for the model that asked for it and a whole-file search
    // would answer for both at once -- which is the bug.
    String sourceOf(int at) {
      final List<int> others = <int>[currency, order]
          .where((int other) => other > at)
          .toList();
      final int end = others.isEmpty ? generated.length : others.reduce(min);
      return generated.substring(at, end);
    }

    expect(sourceOf(order), contains('dv_tenant'));
    expect(sourceOf(currency), isNot(contains('dv_tenant')));
  });
}
