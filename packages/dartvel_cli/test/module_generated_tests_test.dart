// A generated module's tests run under its id, and skip by target.
//
// Testing: "a module's tests run in the parent's suite under the module's own
// id, so a failure names which module it came from. A binding kind that
// cannot run on the host is skipped by target rather than failed, and the
// skip is reported." The generated test file named nothing but the
// operation, so a failure in a parent with three modules did not say which
// one, and it never called a carrier at all.
import 'package:dartvel_cli/src/modules/foreign/dart_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/module_writer.dart';
import 'package:dartvel_core/dartvel.dart' show DVModuleEnvironment, DVModuleOutcome;
import 'package:test/test.dart';

DVForeignModuleSpec spec(String kind) => DVForeignModuleSpec(
      id: 'slugify',
      kind: kind,
      source: 'npm:slugify@1.6.6',
      operations: const <DVModuleOperation>[
        DVModuleOperation(name: 'version', returnType: 'Future<String>', params: <DVModuleParam>[]),
        DVModuleOperation(
          name: 'slug',
          returnType: 'Future<String>',
          params: <DVModuleParam>[DVModuleParam(name: 'text', type: 'String')],
        ),
        DVModuleOperation(name: 'locales', returnType: 'Future<List<String>>', params: <DVModuleParam>[]),
      ],
      outcomes: <String, Map<DVModuleEnvironment, DVModuleOutcome>>{
        for (final String op in <String>['version', 'slug'])
          op: <DVModuleEnvironment, DVModuleOutcome>{
            DVModuleEnvironment.native: DVModuleOutcome.real,
            DVModuleEnvironment.web: DVModuleOutcome.real,
            DVModuleEnvironment.backend: DVModuleOutcome.real,
          },
        'locales': <DVModuleEnvironment, DVModuleOutcome>{
          DVModuleEnvironment.native: DVModuleOutcome.real,
          DVModuleEnvironment.web: DVModuleOutcome.real,
          DVModuleEnvironment.backend: DVModuleOutcome.unavailable,
        },
      },
      carriers: <DVModuleEnvironment, DVCarrierSource>{
        for (final DVModuleEnvironment env in DVModuleEnvironment.values)
          env: DVCarrierSource(body: (DVModuleOperation op) => "Future<String>.value('x') as dynamic"),
      },
    );

String generatedTest(String kind) {
  final Map<String, String> files = dvWriteForeignModule(spec(kind)).files;
  return files.entries
      .firstWhere((MapEntry<String, String> e) => e.key.startsWith('test/'))
      .value;
}

void main() {
  test('every test sits in a group named by the module id', () {
    final String source = generatedTest('npm');
    expect(source, contains("group('slugify', () {"));
    // Opened before the first test, so no test escapes the group.
    expect(source.indexOf("group('slugify'"), lessThan(source.indexOf('test(')));
  });

  test('an operation real on the backend that needs no argument is called', () {
    final String source = generatedTest('npm');
    expect(source, contains("test('version answers on the backend'"));
    expect(source, contains('await const SlugifyModule().version();'));
    // One that needs an argument has nothing to be called with.
    expect(source, isNot(contains("test('slug answers")));
  });

  test('the call is skipped by target, with the reason, where the host '
      'cannot carry it', () {
    final String source = generatedTest('npm');
    expect(source, contains("dvModuleHostRefusal('npm')"));
    expect(source, contains('skip: host'));
    expect(source, contains("import 'package:dartvel_core/framework.dart' show dvModuleHostRefusal;"));
  });

  test('the surface and unavailable checks need no host and are never skipped', () {
    final String source = generatedTest('npm');
    final int unavailable = source.indexOf("test('locales is unavailable on the backend'");
    expect(unavailable, isNot(-1));
    final String block = source.substring(unavailable, source.indexOf('});', unavailable) + 3);
    expect(block, isNot(contains('skip:')));
  });

  test('the module can run its own tests: it declares package:test', () {
    final Map<String, String> files = dvWriteForeignModule(spec('npm')).files;
    expect(files['pubspec.yaml'], contains('dev_dependencies:\n  test: '));
  });
}
