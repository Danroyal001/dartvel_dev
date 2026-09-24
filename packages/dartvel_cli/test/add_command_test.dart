// `dartvel add`, for the sources that are already Dartvel projects.
//
// The first rung of the ladder, and the only one that needs no generation: a
// source that is already a Dartvel project is mounted directly. Generating a
// wrapper around a module that is already a module would add a layer whose
// only job is to be walked through.
//
// What the command has to get right is not the happy path. It edits somebody's
// pubspec, which is a file they wrote, so it has to say what it will do before
// it does it, refuse an id that is already taken rather than overwrite a
// mount, and leave the file alone entirely when it refuses.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/add_command.dart';
import 'package:dartvel_cli/src/graph/module_mounts.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:test/test.dart';

String _project({String modules = ''}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_add_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shop
environment:
  sdk: ^3.12.0
dartvel:
  app:
    name: Shop$modules
''');
  // A Dartvel project beside it, which is what `dartvel add ../store` means.
  final Directory store = Directory(p.join(root.path, 'packages', 'store'))
    ..createSync(recursive: true);
  File(p.join(store.path, 'pubspec.yaml')).writeAsStringSync('''
name: store
environment:
  sdk: ^3.12.0
dartvel:
  module:
    id: store
''');
  return root.path;
}

Future<int> _run(String root, List<String> args) async {
  final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
    ..addCommand(AddCommand(root: root));
  try {
    await runner.run(<String>['add', ...args]);
  } on UsageException {
    return 64;
  } on DVAddRefused {
    return 1;
  }
  return 0;
}

String _pubspec(String root) =>
    File(p.join(root, 'pubspec.yaml')).readAsStringSync();

void main() {
  test('a Dartvel project beside the parent is mounted, not wrapped',
      () async {
    final String root = _project();

    expect(await _run(root, <String>['packages/store']), 0);

    final String pubspec = _pubspec(root);
    expect(pubspec, contains('modules:'));
    expect(pubspec, contains('store:'));
    expect(pubspec, contains('path: packages/store'));
    expect(pubspec, contains('mount: /store'));
    // No wrapper package was written anywhere.
    expect(Directory(p.join(root, 'modules')).existsSync(), isFalse);
  });

  test('what it writes is a pubspec that still parses, and a mount that '
      'discovery finds', () async {
    // A command that edits somebody's pubspec by appending text has to leave
    // a file that still reads as YAML, and a mount the rest of the toolchain
    // resolves -- otherwise the project builds until the next command runs.
    final String root = _project();
    expect(await _run(root, <String>['packages/store']), 0);

    final Object? doc = loadYaml(_pubspec(root));
    expect(doc, isA<Map>());
    final Object? modules = ((doc! as Map)['dartvel'] as Map)['modules'];
    expect((modules! as Map)['store'], isNotNull);

    final List<DVModuleMount> mounts = dvDiscoverModuleMounts(root);
    final DVModuleMount store =
        mounts.firstWhere((DVModuleMount m) => m.id == 'store');
    expect(store.sourcePath, 'packages/store');
    expect(store.mount, '/store');
    expect(store.problems, isEmpty);
  });

  test('a second module is added beside the first, not on top of it',
      () async {
    final String root = _project();
    Directory(p.join(root, 'packages', 'billing')).createSync(recursive: true);
    File(p.join(root, 'packages', 'billing', 'pubspec.yaml'))
        .writeAsStringSync('name: billing\n'
            'environment:\n  sdk: ^3.12.0\n'
            'dartvel:\n  module:\n    id: billing\n');

    expect(await _run(root, <String>['packages/store']), 0);
    expect(await _run(root, <String>['packages/billing']), 0);

    final Object? modules =
        ((loadYaml(_pubspec(root))! as Map)['dartvel'] as Map)['modules'];
    expect((modules! as Map).keys.map((Object? k) => '$k').toSet(),
        <String>{'store', 'billing'});
  });

  test('the id comes from the module, and --as overrides it', () async {
    final String root = _project();

    expect(await _run(root, <String>['packages/store', '--as', 'catalogue']),
        0);

    expect(_pubspec(root), contains('catalogue:'));
    expect(_pubspec(root), isNot(contains('\n    store:')));
  });

  test('--dry-run changes nothing at all', () async {
    final String root = _project();
    final String before = _pubspec(root);

    expect(await _run(root, <String>['packages/store', '--dry-run']), 0);

    expect(_pubspec(root), before);
  });

  test('an id already mounted is refused, and the file is left alone',
      () async {
    // Overwriting a mount would repoint an id somebody else's code calls
    // through, and the pubspec is a file a person wrote.
    // The leading newline is explicit: a ''' literal strips the one that
    // opens it, so this would otherwise land as "name: Shop  modules:" on
    // one line and the block would not be a block at all.
    final String root = _project(modules: '\n'
        '  modules:\n'
        '    store:\n'
        '      source:\n'
        '        path: somewhere/else\n'
        '      mount: /shop');
    final String before = _pubspec(root);

    expect(await _run(root, <String>['packages/store']), 1);

    expect(_pubspec(root), before);
  });

  test('a path that is not a Dartvel project is refused', () async {
    final String root = _project();
    Directory(p.join(root, 'not_dartvel')).createSync();
    File(p.join(root, 'not_dartvel', 'pubspec.yaml'))
        .writeAsStringSync('name: plain\nenvironment:\n  sdk: ^3.12.0\n');
    final String before = _pubspec(root);

    expect(await _run(root, <String>['not_dartvel']), 1);
    expect(_pubspec(root), before);
  });

  test('a path that does not exist is refused', () async {
    final String root = _project();
    final String before = _pubspec(root);

    expect(await _run(root, <String>['packages/nothing']), 1);
    expect(_pubspec(root), before);
  });

  test('a refusal says what it found, not just that it failed', () async {
    // DV-MODULE-009 names what is there. "Could not detect the source" tells
    // somebody nothing about what to do next, and the commonest reason a
    // detection fails is that the path is one directory off.
    final String root = _project();
    Directory(p.join(root, 'sdk')).createSync();
    File(p.join(root, 'sdk', 'README.md')).writeAsStringSync('# Scanner');

    late final DVAddRefused refused;
    try {
      AddCommand.planFor(root, 'sdk');
      fail('a directory holding a README is not a source');
    } on DVAddRefused catch (e) {
      refused = e;
    }

    expect(refused.message, contains('DV-MODULE-009'));
    expect(refused.message, contains('README.md'));
  });

  test('a recognised foreign source is named, and still refused', () async {
    // Detection is built and generation is not, so the honest answer names
    // what it is and says the generator does not exist -- rather than
    // pretending not to recognise a Cargo.toml.
    final String root = _project();
    Directory(p.join(root, 'engine')).createSync();
    File(p.join(root, 'engine', 'Cargo.toml')).writeAsStringSync('[package]');
    final String before = _pubspec(root);

    expect(await _run(root, <String>['engine']), 1);
    expect(_pubspec(root), before);
  });

  group('an OpenAPI document', () {
    /// A directory holding a document, beside the parent.
    String describedApi(String root, {String name = 'openapi.yaml'}) {
      final Directory dir = Directory(p.join(root, 'vendor_api'))
        ..createSync(recursive: true);
      File(p.join(dir.path, name)).writeAsStringSync('''
openapi: 3.0.3
info:
  title: Vendor ERP
  version: "1.0.0"
servers:
  - url: https://api.vendor.com
paths:
  /orders/{id}:
    get:
      operationId: getOrder
      parameters:
        - name: id
          in: path
          required: true
          schema: { type: string }
      responses:
        "200":
          content:
            application/json:
              schema: { \$ref: "#/components/schemas/Order" }
components:
  schemas:
    Order:
      type: object
      required: [id]
      properties:
        id: { type: string }
''');
      return dir.path;
    }

    test('becomes a module package the parent mounts', () async {
      final String root = _project();
      describedApi(root);

      expect(await _run(root, <String>['vendor_api', '--as', 'vendorErp']), 0);

      // A package on disk, with the calls the document describes.
      final String library =
          File(p.join(root, 'modules', 'vendor_erp', 'lib', 'vendor_erp.dart'))
              .readAsStringSync();
      expect(library, contains('Future<Order> getOrder({required String id})'));
      expect(
        File(p.join(root, 'modules', 'vendor_erp', 'pubspec.yaml'))
            .readAsStringSync(),
        contains('id: vendorErp'),
      );
      // And mounted, pointing at what was written rather than at the
      // document it came from.
      expect(_pubspec(root), contains('path: modules/vendor_erp'));
      expect(_pubspec(root), contains('vendorErp:'));
    });

    test('a JSON document works the same way', () async {
      final String root = _project();
      final Directory dir = Directory(p.join(root, 'vendor_api'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'openapi.json')).writeAsStringSync(
        '{"openapi":"3.0.3","info":{"title":"Vendor"},'
        '"servers":[{"url":"https://api.vendor.com"}],'
        '"paths":{"/ping":{"get":{"operationId":"ping",'
        '"responses":{"204":{}}}}}}',
      );

      expect(await _run(root, <String>['vendor_api', '--as', 'vendor']), 0);

      expect(
        File(p.join(root, 'modules', 'vendor', 'lib', 'vendor.dart'))
            .readAsStringSync(),
        contains('Future<void> ping()'),
      );
    });

    test('--dry-run writes no package and no mount', () async {
      final String root = _project();
      describedApi(root);
      final String before = _pubspec(root);

      expect(
        await _run(root, <String>['vendor_api', '--as', 'vendorErp', '--dry-run']),
        0,
      );

      expect(_pubspec(root), before);
      expect(Directory(p.join(root, 'modules')).existsSync(), isFalse);
    });

    test('it will not write over a package that is already there', () async {
      // The directory may hold work somebody did, and a generator that
      // overwrote it would take it with no way back.
      final String root = _project();
      describedApi(root);
      Directory(p.join(root, 'modules', 'vendor_erp'))
          .createSync(recursive: true);
      File(p.join(root, 'modules', 'vendor_erp', 'keep.txt'))
          .writeAsStringSync('mine');
      final String before = _pubspec(root);

      // The message, not only the code: this refusal passed before the
      // generator existed, when every described API was refused, and a test
      // that cannot tell those apart proves nothing about either.
      late final DVAddRefused refused;
      try {
        AddCommand.planFor(root, 'vendor_api', id: 'vendorErp');
        fail('generating over an existing package takes what is in it');
      } on DVAddRefused catch (e) {
        refused = e;
      }
      expect(refused.message, contains('modules/vendor_erp is already there'));

      expect(await _run(root, <String>['vendor_api', '--as', 'vendorErp']), 1);

      expect(_pubspec(root), before);
      expect(
        File(p.join(root, 'modules', 'vendor_erp', 'keep.txt'))
            .readAsStringSync(),
        'mine',
      );
    });

    test('a document it cannot read is refused before anything is written',
        () async {
      final String root = _project();
      final Directory dir = Directory(p.join(root, 'vendor_api'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'openapi.yaml'))
          .writeAsStringSync('swagger: "2.0"\ninfo:\n  title: Old\n');
      final String before = _pubspec(root);

      late final DVAddRefused refused;
      try {
        AddCommand.planFor(root, 'vendor_api', id: 'vendor');
        fail('a Swagger 2 document is not one this reads');
      } on DVAddRefused catch (e) {
        refused = e;
      }
      expect(refused.message, contains('openapi.yaml'));
      expect(refused.message, contains('not an OpenAPI document'));

      expect(await _run(root, <String>['vendor_api', '--as', 'vendor']), 1);

      expect(_pubspec(root), before);
      expect(Directory(p.join(root, 'modules')).existsSync(), isFalse);
    });

    test('the plan says what will be written before it is', () async {
      final String root = _project();
      describedApi(root);

      final DVAddPlan plan =
          AddCommand.planFor(root, 'vendor_api', id: 'vendorErp');

      expect(plan.lines.join('\n'), contains('modules/vendor_erp'));
      expect(plan.lines.join('\n'), contains('a described API'));
      // Nothing was written by planning it.
      expect(Directory(p.join(root, 'modules')).existsSync(), isFalse);
    });
  });

  group('a GraphQL schema', () {
    void writeSchema(String root) {
      final Directory dir = Directory(p.join(root, 'vendor_api'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'schema.graphql')).writeAsStringSync('''
type Query {
  order(id: ID!): Order
}

type Order {
  id: ID!
  total: Float
}
''');
    }

    test('becomes a module when it is told where to post', () async {
      // A schema does not name its own server, so the endpoint is the one
      // thing that cannot be read out of the document.
      final String root = _project();
      writeSchema(root);

      expect(
        await _run(root, <String>[
          'vendor_api',
          '--as',
          'vendorErp',
          '--url',
          'https://api.vendor.com/graphql',
        ]),
        0,
      );

      final String library =
          File(p.join(root, 'modules', 'vendor_erp', 'lib', 'vendor_erp.dart'))
              .readAsStringSync();
      expect(library, contains('Future<OrderResult?> order('));
      expect(library, contains("const String endpoint = '/graphql';"));
      expect(_pubspec(root), contains('path: modules/vendor_erp'));
    });

    test('without --url it is refused, and says what is missing', () async {
      final String root = _project();
      writeSchema(root);
      final String before = _pubspec(root);

      late final DVAddRefused refused;
      try {
        AddCommand.planFor(root, 'vendor_api', id: 'vendorErp');
        fail('a schema with no endpoint is not enough to generate a client');
      } on DVAddRefused catch (e) {
        refused = e;
      }

      expect(refused.message, contains('--url'));
      expect(_pubspec(root), before);
      expect(Directory(p.join(root, 'modules')).existsSync(), isFalse);
    });
  });

  test('--url overrides the server an OpenAPI document names', () async {
    // A document published with its production server, used against a
    // staging one. Editing the document would be editing somebody else's
    // file.
    final String root = _project();
    final Directory dir = Directory(p.join(root, 'vendor_api'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'openapi.json')).writeAsStringSync(
      '{"openapi":"3.0.3","info":{"title":"Vendor"},'
      '"servers":[{"url":"https://api.vendor.com"}],'
      '"paths":{"/ping":{"get":{"operationId":"ping",'
      '"responses":{"204":{}}}}}}',
    );

    expect(
      await _run(root, <String>[
        'vendor_api',
        '--as',
        'vendor',
        '--url',
        'https://staging.vendor.com',
      ]),
      0,
    );

    expect(
      File(p.join(root, 'modules', 'vendor', 'pubspec.yaml'))
          .readAsStringSync(),
      contains('baseUrl: "https://staging.vendor.com"'),
    );
  });

  test('a plain Dart package is sent to dart pub add', () async {
    final String root = _project();
    Directory(p.join(root, 'intl')).createSync();
    File(p.join(root, 'intl', 'pubspec.yaml')).writeAsStringSync('name: intl');

    late final DVAddRefused refused;
    try {
      AddCommand.planFor(root, 'intl');
      fail('a package with no dartvel section is not a module');
    } on DVAddRefused catch (e) {
      refused = e;
    }

    expect(refused.message, contains('dart pub add'));
  });

  test('a foreign scheme says so rather than half-doing it', () async {
    // Every other scheme is specified and unbuilt. Answering "maven is not
    // supported yet" is the honest failure; writing a mount that resolves to
    // nothing would be a project that no longer builds.
    final String root = _project();
    final String before = _pubspec(root);

    expect(await _run(root, <String>['maven:com.vendor:scanner']), 1);
    expect(_pubspec(root), before);
  });
}
