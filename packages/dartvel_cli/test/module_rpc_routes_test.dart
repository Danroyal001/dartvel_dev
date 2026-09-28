// The backend half of a module call carried over RPC: a route per carried
// operation, behind the policy the application names for the module.
//
// The route runs the operation with the server's authority, so a module that
// carries anything to the backend and names no policy is refused at build
// time (DV-MODULE-021) rather than served to anybody.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _modulePubspec = '''
name: dv_notes_module
dartvel:
  module:
    id: notes
    kind: dartPackage
    source: "path:notes"
    surface: NotesModule
    operations:
      readNote:
        native: real
        web: {compat: backend}
        backend: real
      separator:
        native: real
        web: unavailable
        backend: real
''';

Future<Directory> parent({String? policy}) async {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_module_rpc_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    notes:
      source:
        path: modules/dv_notes_module
      mount: /notes
${policy == null ? '' : '      backendPolicy: $policy\n'}''');
  Directory(p.join(root.path, '.dart_tool')).createSync();
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'backend', 'functions'))
      .createSync(recursive: true);
  File(p.join(root.path, 'modules', 'dv_notes_module', 'pubspec.yaml'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_modulePubspec);
  return root;
}

Future<void> generate(Directory root) => BackendGenerator.generate(
      root: root.path,
      backendDir: 'lib/backend',
      pkgName: 'shopfront',
      backendHost: '127.0.0.1',
      backendPort: 3000,
      apiBasePath: '/api',
    );

String routes(Directory root) => File(p.join(
        root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'))
    .readAsStringSync();

void main() {
  test('a module that carries a call to the backend names who may make it',
      () async {
    final Directory root = await parent();
    await expectLater(
      generate(root),
      throwsA(predicate((Object e) =>
          '$e'.contains('DV-MODULE-021') &&
          '$e'.contains('notes.readNote') &&
          '$e'.contains('backendPolicy'))),
    );
  });

  test('each carried operation is a route of its own, behind the policy',
      () async {
    final Directory root = await parent(policy: 'viewNotes');
    await generate(root);
    final String source = routes(root);
    expect(source,
        contains("import 'package:dv_notes_module/src/carrier_backend.dart'"));
    expect(source, contains("'/_dv/modules/notes/readNote'"));
    expect(source, contains("_dvAllowed('viewNotes', req)"));
    expect(source, contains("dvModuleDispatch('readNote'"));
    // Only what the module carries is reachable from the network.
    expect(source, isNot(contains('/_dv/modules/notes/separator')));
  });

  test('public is a policy said out loud', () async {
    final Directory root = await parent(policy: 'public');
    await generate(root);
    final String source = routes(root);
    expect(source, contains("'/_dv/modules/notes/readNote'"));
    expect(source, isNot(contains("_dvAllowed('public'")));
  });

  test('an application with no carried module has no module routes',
      () async {
    final Directory root = Directory.systemTemp.createTempSync('dv_rpc_none_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: shop\n');
    Directory(p.join(root.path, '.dart_tool')).createSync();
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'backend', 'functions'))
        .createSync(recursive: true);
    await generate(root);
    expect(routes(root), isNot(contains('/_dv/modules/')));
  });
}
