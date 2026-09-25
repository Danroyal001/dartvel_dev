// Generation inputs written with primary constructors.
//
// Dart 3.13 lets a data model be declared as
//
//     @DVModel()
//     class const _Order({required final String id, final int total = 0});
//
// and that is how every sample and the scaffold now write one. The generator
// reads source text, and every pattern it had looked for `final Type name;`
// in a class body and `class _Name {`. A model written the new way has
// neither, so it produced a public class with no fields, a job with no
// payload and a policy that was never found -- on a build that succeeded.
//
// The assertion that matters is equivalence: the same declaration written
// either way generates the same code, byte for byte.
import 'dart:io';

import 'package:dartvel_cli/src/config/dartvel_config.dart';
import 'package:dartvel_cli/src/generators/page_names.dart';
import 'package:dartvel_cli/src/docs/docs_site.dart';
import 'package:dartvel_cli/src/generators/job_generator.dart';
import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:dartvel_cli/src/generators/policy_classes.dart';
import 'package:dartvel_cli/src/generators/primary_constructors.dart';
import 'package:dartvel_cli/src/generators/privacy_declarations.dart';
import 'package:dartvel_cli/src/graph/project_graph.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _oldModel = '''
import 'package:dartvel_core/dartvel.dart';

/// An order.
@DVModel(subject: DVSubject.field('email'))
@pragma('vm:entry-point')
class _Order {
  final String id;
  @DVModel.searchableField()
  final String reference;
  @DVModel.sensitiveField(showInForms: true)
  final String email;
  final int total;
  final String? note;
  final DateTime placedAt;

  const _Order({
    required this.id,
    required this.reference,
    required this.email,
    this.total = 0,
    this.note,
    required this.placedAt,
  });

  bool get large => total > 100;
}
''';

const String _newModel = '''
import 'package:dartvel_core/dartvel.dart';

/// An order.
@DVModel(subject: DVSubject.field('email'))
@pragma('vm:entry-point')
class const _Order({
  required final String id,
  @DVModel.searchableField() required final String reference,
  @DVModel.sensitiveField(showInForms: true) required final String email,
  final int total = 0,
  final String? note,
  required final DateTime placedAt,
}) {
  bool get large => total > 100;
}
''';

Future<Directory> _project(Map<String, String> files) async {
  final Directory root = await Directory.systemTemp.createTemp(
    'dartvel_primary_ctor_',
  );
  addTearDown(() => root.deleteSync(recursive: true));
  files.forEach((String relative, String contents) {
    final File file = File(
      p.joinAll(<String>[root.path, ...relative.split('/')]),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  });
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  return root;
}

Future<String> _models(String source) async {
  final Directory root = await _project(<String, String>{
    'lib/models/order.dart': source,
  });
  await ModelGenerator.generate(
    root: root.path,
    pkgName: 'shop',
    buildId: 'test-build',
  );
  return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
      .readAsStringSync();
}

Future<String> _jobs(String source) async {
  final Directory root = await _project(<String, String>{
    'lib/jobs/jobs.dart': source,
  });
  await JobGenerator.generate(
    root: root.path,
    pkgName: 'shop',
    buildId: 'test-build',
  );
  return File(p.join(root.path, 'lib', 'dartvel_client', 'jobs.g.dart'))
      .readAsStringSync();
}

void main() {
  group('a data model', () {
    test('generates the same code whichever way it is declared', () async {
      final String before = await _models(_oldModel);
      final String after = await _models(_newModel);

      // Not vacuous: the old declaration produced a model with every field.
      expect(before, contains('final String reference'));
      expect(before, contains('final DateTime placedAt'));
      expect(after, before);
    });

    test('a non-const primary constructor is not made const', () async {
      final String generated = await _models('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Tag(final String id, final String label);
''');
      expect(generated, contains('final String label'));
      expect(generated, isNot(contains('const Tag(')));
      expect(generated, isNot(contains('class const Tag(')));
    });

    test('privacy and the project graph read sensitive parameters', () async {
      final Directory root = await _project(<String, String>{
        'lib/models/order.dart': _newModel,
      });

      final DVPrivacyModelDeclaration order = DVPrivacyDeclarations.discover(
        root: root.path,
      ).models.single;
      expect(order.sensitive, <String>{'email'});
      expect(order.columns, containsAll(<String>['id', 'email', 'placedAt']));
      // The line is the declaration's, as it was before.
      expect(order.source, 'lib/models/order.dart:4');

      final DartvelProjectGraph graph = await DartvelProjectGraph.build(
        root: root.path,
        pkgName: 'shop',
      );
      final Map<String, bool> sensitive = <String, bool>{
        for (final DVGraphField f in graph.models.single.fields)
          f.name: f.sensitive,
      };
      expect(sensitive, <String, bool>{
        'id': false,
        'reference': false,
        'email': true,
        'total': false,
        'note': false,
        'placedAt': false,
      });
    });
  });

  test('a job payload generates the same code either way', () async {
    final String before = await _jobs('''
import 'package:dartvel_core/dartvel.dart';

@DVJob(queue: 'mail', maxAttempts: 5)
class _SendReceipt {
  final String orderId;
  final int attempt;

  const _SendReceipt({required this.orderId, required this.attempt});
}
''');
    final String after = await _jobs('''
import 'package:dartvel_core/dartvel.dart';

@DVJob(queue: 'mail', maxAttempts: 5)
class const _SendReceipt({required final String orderId, required final int attempt});
''');
    expect(before, contains('final String orderId'));
    expect(after, before);
  });

  test('a handler beside a primary-constructor payload keeps its const',
      () async {
    // `class const _SendReceipt(` was read as a class named `const`, and the
    // lowered handler body came out as `j0.const Receipt(...)`.
    final String jobs = await _jobs('''
import 'package:dartvel_core/dartvel.dart';

@DVJob(queue: 'mail')
class const _SendReceipt({required final String orderId});

@DVJob.handler()
Future<void> _handleSendReceipt(SendReceipt job) async =>
    print(const Duration(seconds: 1));
''');
    expect(jobs, contains('print(const Duration(seconds: 1))'));
    expect(jobs, isNot(contains('.const ')));
  });

  test('a policy with a primary constructor is still found', () {
    final List<DVPolicyClass> found = dvPolicyClassesIn('''
@DVPolicy(Order)
class const _OrderPolicy() {
  bool view(DVUser user, Order order) => true;
}
''', 'lib/policies/order_policy.dart');
    expect(found.map((DVPolicyClass c) => c.className), <String>[
      '_OrderPolicy',
    ]);
    expect(found.single.methods.map((DVPolicyMethod m) => m.action), <String>[
      'view',
    ]);
  });

  test('the documentation site finds a parameter\'s doc comment', () async {
    final Directory root = await _project(<String, String>{
      'pubspec.yaml': 'name: shop\nenvironment:\n  sdk: ^3.13.0\n',
      'lib/models/customer.dart': '''
import 'package:dartvel_core/dartvel.dart';

/// Someone who buys.
@DVModel()
class const _Customer(
  final String id,

  /// Where receipts are sent.
  final String email, {

  /// What they like to be called.
  final String? nickname,
});
''',
    });
    final DVDocsSite site = await DVDocsSite.build(root: root.path);
    final String models = site.files['models.html']!;
    expect(models, contains('Someone who buys.'));
    expect(models, contains('Where receipts are sent.'));
    expect(models, contains('What they like to be called.'));
  });

  test('a class page written with a primary constructor is a page', () {
    expect(
      dvPageSymbol('''
@DVPage(title: 'Team')
class const TeamPage({super.key, final String? tab}) extends DartvelPage {
  @override
  Widget build(BuildContext context) => const Placeholder();
}
'''),
      'TeamPage',
    );
  });

  test('a Dart config written with a primary constructor is found', () async {
    final Directory root = await _project(<String, String>{
      'lib/config.dart': 'class const AppConfig() extends DartvelConfig {}\n',
    });
    final DartvelDartConfigReference found =
        DartvelDartConfigReference.validate(
          root: root,
          relativePath: 'lib/config.dart',
        );
    expect(found.className, 'AppConfig');
  });

  group('dvDesugarPrimaryConstructors', () {
    test('turns declaring parameters into fields and a constructor', () {
      final String out = dvDesugarPrimaryConstructors(
        'class const _P(final int x, [final int y = 0]);',
      );
      expect(out, contains('final int x;'));
      expect(out, contains('final int y;'));
      expect(out, contains('const _P(this.x, [this.y = 0]);'));
      expect(out, startsWith('class _P {'));
    });

    test('keeps annotations, required, defaults and super parameters', () {
      final String out = dvDesugarPrimaryConstructors('''
class _W({super.key, @Deprecated('x') required final String title, final Map<String, int> m = const {}}) extends Base {
  int get n => 1;
}''');
      expect(out, contains("@Deprecated('x') final String title;"));
      expect(out, contains('final Map<String, int> m;'));
      expect(
        out,
        contains("_W({super.key, required this.title, this.m = const {}});"),
      );
      expect(out, contains('extends Base {'));
      expect(out, contains('int get n => 1;'));
    });

    test('keeps every line where it was', () {
      const String source = '''
class _A(
  final int a,
  @Anno(
    1,
  )
  final String b,
) {
  int get c => a;
}

class _B {}
''';
      final String out = dvDesugarPrimaryConstructors(source);
      expect('\n'.allMatches(out).length, '\n'.allMatches(source).length);
      expect(
        out.split('\n').indexOf('class _B {}'),
        source.split('\n').indexOf('class _B {}'),
      );
    });

    test('leaves ordinary classes, strings, comments and extension types', () {
      const String source = '''
// class _C(final int x);
const String s = 'class _D(final int y);';
extension type const Id(int value);
class _E {
  final int z;
  const _E(this.z);
}
''';
      expect(dvDesugarPrimaryConstructors(source), source);
    });
  });
}
