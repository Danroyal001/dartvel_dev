// A mounted module's backend functions, served by the parent.
//
// The specification says a backend-only module contributes models, backend
// functions, cron functions, AI tools, storage behaviour and migrations but
// no pages, and an embedded module compiles into the parent keeping its
// namespace. The parent's backend router was generated from the parent's own
// backend directory alone, so a mounted module's functions were in the build
// and served by nothing.
//
// The failure is silent in the way that matters: an embedded module's
// generated client calls its own paths against whatever application it is
// compiled into, so the module works standing alone and answers 404 mounted.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _reindex = '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _reindex(String term) async => term.toUpperCase();
''';

/// A parent that mounts `store`, with whatever the test wants in each.
///
/// Returns the project root; the generated files are read from it.
Future<Directory> generate({
  String deployment = 'embedded',
  Map<String, String> moduleFunctions = const <String, String>{
    'reindex.post.dart': _reindex,
  },
  Map<String, String> parentFunctions = const <String, String>{},
  Map<String, String> moduleLib = const <String, String>{},
}) async {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_module_backend_');
  addTearDown(() => root.deleteSync(recursive: true));

  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      source: { path: modules/store }
      mount: /store
      deployment: $deployment
''');
  Directory(p.join(root.path, '.dart_tool')).createSync();
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'backend', 'functions'))
      .createSync(recursive: true);
  parentFunctions.forEach((String name, String source) {
    File(p.join(root.path, 'lib', 'backend', 'functions', name))
        .writeAsStringSync(source);
  });

  final Directory module = Directory(p.join(root.path, 'modules', 'store'));
  module.createSync(recursive: true);
  File(p.join(module.path, 'pubspec.yaml')).writeAsStringSync('''
name: store
dartvel:
  module:
    id: store
    version: 1.0.0
''');
  Directory(p.join(module.path, 'lib', 'backend', 'functions'))
      .createSync(recursive: true);
  moduleFunctions.forEach((String name, String source) {
    File(p.join(module.path, 'lib', 'backend', 'functions', name))
        .writeAsStringSync(source);
  });
  moduleLib.forEach((String name, String source) {
    File(p.join(module.path, 'lib', name))
      ..createSync(recursive: true)
      ..writeAsStringSync(source);
  });

  await BackendGenerator.generate(
    root: root.path,
    backendDir: 'lib/backend',
    pkgName: 'shopfront',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    apiBasePath: '/api',
  );

  return root;
}

Future<String> generatedRoutes({
  String deployment = 'embedded',
  Map<String, String> moduleFunctions = const <String, String>{
    'reindex.post.dart': _reindex,
  },
  Map<String, String> parentFunctions = const <String, String>{},
}) async =>
    File(p.join(
      (await generate(
        deployment: deployment,
        moduleFunctions: moduleFunctions,
        parentFunctions: parentFunctions,
      ))
          .path,
      '.dart_tool',
      'dartvel_backend_routes.g.dart',
    )).readAsStringSync();

void main() {
  test('an embedded module\'s function is served by the parent', () async {
    final String routes = await generatedRoutes();

    // At the module's own path, because that is what the module's generated
    // client asks for: it was generated against its own project and knows
    // nothing about a mount.
    expect(routes, contains("router.post(cfg.apiBasePath + '/reindex'"));
    // And its body, which is what answers.
    expect(routes, contains('term.toUpperCase()'));
  });

  test('a function it imports is imported from the module\'s package', () async {
    // A handler-style function stays in its file and is reached through an
    // import. Measured from the parent it would read package:shopfront/, a
    // package that does not contain the file, and the parent would not
    // compile -- which at least fails loudly, unlike a parent that happens
    // to have a file at the same path.
    final String routes = await generatedRoutes(
      moduleFunctions: <String, String>{
        'search.get.dart': '''
import 'package:dartvel_shelf/dartvel_shelf.dart';

Response handler(Request request) => Response(200);
''',
      },
    );

    expect(routes,
        contains("import 'package:store/backend/functions/search.get.dart'"));
    expect(routes, contains("router.get(cfg.apiBasePath + '/search'"));
  });

  test('a backend-only module\'s function is served too', () async {
    // It has no pages; functions are the whole of what it contributes.
    final String routes = await generatedRoutes(deployment: 'backend-only');

    expect(routes, contains("router.post(cfg.apiBasePath + '/reindex'"));
  });

  test('a split-backend module\'s function is not', () async {
    // It deploys as its own service and its client calls that address.
    // Serving it here too would answer with a second copy, built from source
    // beside the parent, that nobody deployed.
    final String routes = await generatedRoutes(deployment: 'split-backend');

    expect(routes, isNot(contains("cfg.apiBasePath + '/reindex'")));
  });

  test('a federated module\'s function is not', () async {
    final String routes = await generatedRoutes(deployment: 'federated');

    expect(routes, isNot(contains("cfg.apiBasePath + '/reindex'")));
  });

  test('a function that would shadow the parent\'s own is refused', () async {
    // Same method, same path, one router. Whichever lost would be a 404 or,
    // worse, the wrong answer -- and the build has both in front of it.
    expect(
      generatedRoutes(parentFunctions: <String, String>{'reindex.post.dart': _reindex}),
      throwsA(isA<StateError>().having((StateError e) => e.message, 'message',
          allOf(contains('store'), contains('/reindex')))),
    );
  });

  test('a module\'s cron function is in the parent\'s schedule', () async {
    // A backend-only module contributes cron functions in the specification's
    // own list. The schedule was generated from the parent's lib alone, so a
    // module's never ran and nothing said so.
    final Directory root = await generate(
      deployment: 'backend-only',
      moduleFunctions: const <String, String>{},
      moduleLib: const <String, String>{
        'jobs/nightly.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendCron('0 3 * * *')
Future<void> reindexNightly() async {}
''',
      },
    );

    final String schedules = File(p.join(
            root.path, 'lib', 'dartvel_client', 'schedules.g.dart'))
        .readAsStringSync();

    expect(schedules, contains("name: 'reindexNightly'"));
    expect(schedules, contains("cron: '0 3 * * *'"));
    // Imported from the module, not from a parent path that has no such file.
    expect(schedules, contains("importUri: 'package:store/jobs/nightly.dart'"));
  });

  test('a module\'s AI tool is in the parent\'s tools', () async {
    final Directory root = await generate(
      deployment: 'backend-only',
      moduleFunctions: const <String, String>{},
      moduleLib: const <String, String>{
        'ai/lookup.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVAITool(description: 'Look a product up')
Future<String> lookUpProduct(String sku) async => sku;
''',
      },
    );

    final String tools =
        File(p.join(root.path, 'lib', 'dartvel_client', 'ai_tools.g.dart'))
            .readAsStringSync();

    expect(tools, contains("'lookUpProduct'"));
    expect(tools, contains('package:store/ai/lookup.dart'));
  });

  test('a federated module contributes neither', () async {
    // It runs its own schedule in its own deployment. Running it here too
    // would do the work twice, which for a cron job is the failure.
    final Directory root = await generate(
      deployment: 'federated',
      moduleFunctions: const <String, String>{},
      moduleLib: const <String, String>{
        'jobs/nightly.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendCron('0 3 * * *')
Future<void> reindexNightly() async {}
''',
      },
    );

    expect(
        File(p.join(root.path, 'lib', 'dartvel_client', 'schedules.g.dart'))
            .readAsStringSync(),
        isNot(contains('reindexNightly')));
  });
}
