// `dartvel test --impacted`: only the tests a diff can reach.
//
// Testing: the impacted set is a query against the project, not an inference
// from last run's coverage, and it is refused on a dirty generated tree
// (DV-GEN-001) because an impact map from a stale graph is confidently wrong
// about what it skipped. The silent failure to guard against is a test that
// should have run and did not: so every doubt widens the set, and a change
// the query cannot place -- a migration, a pubspec, a config file -- runs
// everything.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/test_command.dart';
import 'package:dartvel_cli/src/testing/impacted_tests.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory project(Map<String, String> files) {
  final Directory root = Directory.systemTemp.createTempSync('dv_impacted_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
    'name: shop\nenvironment:\n  sdk: ">=3.13.0 <4.0.0"\n',
  );
  files.forEach((String path, String source) {
    File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(source);
  });
  return root;
}

const Map<String, String> _shop = <String, String>{
  'lib/models/order.dart': '''
import 'package:dartvel_core/dartvel.dart';
@DVModel()
class const _Order({required final String id});
''',
  'lib/models/product.dart': '''
import 'package:dartvel_core/dartvel.dart';
@DVModel()
class const _Product({required final String id});
''',
  'lib/pricing/tax.dart': "import '../models/product.dart';\nint tax() => 1;\n",
  'lib/pricing/cart.dart': "import 'tax.dart';\nint total() => tax();\n",
  'lib/backend/functions/orders/refund.post.dart':
      'Future<bool> refund(String id) async => true;\n',
  'test/cart_test.dart':
      "import 'package:shop/pricing/cart.dart';\nvoid main() {}\n",
  'test/order_test.dart':
      "import 'package:shop/models/order.dart';\nvoid main() {}\n",
  'test/refund_test.dart':
      "// Calls the function over HTTP, so it imports nothing of it.\n"
      "void main() { final path = '/orders/refund'; }\n",
  'test/unrelated_test.dart': 'void main() {}\n',
};

Future<Set<String>?> impacted(Directory root, List<String> changed) =>
    DartvelImpactedTests.select(root: root.path, changed: changed);

void main() {
  test('a test reaches what it imports, through every import between', () async {
    final Directory root = project(_shop);

    expect(await impacted(root, <String>['lib/models/product.dart']),
        <String>{'test/cart_test.dart'});
  });

  test('a changed test runs itself and nothing else', () async {
    final Directory root = project(_shop);

    expect(await impacted(root, <String>['test/unrelated_test.dart']),
        <String>{'test/unrelated_test.dart'});
  });

  test('a backend function is reached by the tests that call its path',
      () async {
    // No import names it: a function test calls it over HTTP. Coverage would
    // not see it either. The project graph knows the function's path.
    final Directory root = project(_shop);

    expect(
      await impacted(
          root, <String>['lib/backend/functions/orders/refund.post.dart']),
      <String>{'test/refund_test.dart'},
    );
  });

  test('a model is reached by the tests that name it', () async {
    final Directory root = project(<String, String>{
      ..._shop,
      'test/report_test.dart':
          "// Through the generated barrel, which is not on disk here.\n"
          'void main() { Order; }\n',
    });

    expect(await impacted(root, <String>['lib/models/order.dart']),
        <String>{'test/order_test.dart', 'test/report_test.dart'});
  });

  test('a change it cannot place runs everything', () async {
    // A migration, the pubspec, configuration: none of them is imported, and
    // each can change what every test sees.
    final Directory root = project(_shop);

    expect(await impacted(root, <String>['pubspec.yaml']), isNull);
    expect(await impacted(root, <String>['db/migrations/0002_add_sku.sql']),
        isNull);
  });

  test('a deleted file still reaches the tests that imported it', () async {
    final Directory root = project(_shop);
    File(p.join(root.path, 'lib/pricing/tax.dart')).deleteSync();

    expect(await impacted(root, <String>['lib/pricing/tax.dart']),
        <String>{'test/cart_test.dart'});
  });

  test('nothing changed is nothing to run', () async {
    expect(await impacted(project(_shop), const <String>[]), isEmpty);
  });

  group('the command', () {
    Future<String> run(Directory root,
        {required List<String> changed, required bool stale}) async {
      final StringBuffer out = StringBuffer();
      final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
        ..addCommand(TestCommand(
          root: root.path,
          impact: DartvelImpactSource(
            changed: (_) async => changed,
            staleGenerated: (_) async =>
                stale ? <String>['lib/dartvel_client/models.g.dart'] : <String>[],
          ),
        ));
      await IOOverrides.runZoned(
        () => runner.run(<String>['test', '--impacted', '--dry-run']),
        stdout: () => _Capture(out),
      );
      return out.toString();
    }

    test('runs the impacted tests', () async {
      final Directory root = project(_shop);
      final String command =
          await run(root, changed: <String>['lib/pricing/tax.dart'], stale: false);
      expect(command.trim(), 'dart test test/cart_test.dart');
    });

    test('is refused on a dirty generated tree with DV-GEN-001', () async {
      final Directory root = project(_shop);
      await expectLater(
        run(root, changed: <String>['lib/pricing/tax.dart'], stale: true),
        throwsA(isA<UsageException>().having(
            (UsageException e) => e.message, 'message', contains('DV-GEN-001'))),
      );
    });

    test('a change it cannot place runs the whole suite', () async {
      final Directory root = project(_shop);
      final String command =
          await run(root, changed: <String>['pubspec.yaml'], stale: false);
      expect(command.trim(), 'dart test test');
    });

    test('nothing impacted runs nothing and says so', () async {
      final Directory root = project(_shop);
      final String command =
          await run(root, changed: <String>['README.md'], stale: false);
      expect(command, isNot(contains('dart test')));
      expect(command, contains('No tests'));
    });
  });
}

class _Capture implements Stdout {
  _Capture(this._out);
  final StringBuffer _out;

  @override
  void writeln([Object? object = '']) => _out.writeln(object);

  @override
  void write(Object? object) => _out.write(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
