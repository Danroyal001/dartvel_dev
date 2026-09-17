// What the generated backend tells Studio about each model.
//
// Studio on a web-server binary reads and edits records through the admin
// mount, and the backend cannot import the generated model classes to find
// them: those carry Flutter widgets. So the model generator writes, beside the
// public page specs, where each model's rows are -- the table, the key the
// generated find() uses, which fields are sensitive, whether rows belong to a
// tenant -- and the backend hands that to the admin server it mounts.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<Directory> project() async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_studio_models_');
  Directory(p.join(root.path, '.dart_tool')).createSync();
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'backend', 'functions'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'models', 'account.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(tenantScoped: true, softDelete: true)
@pragma('vm:entry-point')
class _Account {
  final int rank;
  final String id;
  final String name;
  @DVModel.sensitiveField()
  final String secret;
  final DateTime? joined;
  const _Account({required this.rank, required this.id, required this.name, required this.secret, this.joined});
}
''');
  File(p.join(root.path, 'lib', 'models', 'note.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(version: false)
@pragma('vm:entry-point')
class _Note {
  final int order;
  final bool done;
  const _Note({required this.order, required this.done});
}
''');
  return root;
}

/// The one spec in [source] for [model], as written.
String spec(String source, String model) {
  final int start = source.indexOf("DVStudioModelSpec(\n    model: '$model'");
  expect(start, isNot(-1), reason: 'no Studio spec for $model in\n$source');
  final int end = source.indexOf('\n  ),', start);
  return source.substring(start, end);
}

void main() {
  late Directory root;
  setUp(() async => root = await project());
  tearDown(() => root.deleteSync(recursive: true));

  test('every model has a spec naming its table, key and fields', () async {
    await ModelGenerator.generate(
        root: root.path, pkgName: 'shop', buildId: 'b');
    final String pages = File(
            p.join(root.path, 'lib', 'dartvel_client', 'model_pages.g.dart'))
        .readAsStringSync();

    expect(pages, isNot(contains('package:flutter')));
    expect(pages, contains('List<DVStudioModelSpec> dartvelStudioModels'));

    final String account = spec(pages, 'Account');
    expect(account, contains("table: 'accounts'"));
    // The key generated find() uses: the String id, not the first field.
    expect(account, contains("key: 'id'"));
    expect(account, contains('tenantScoped: true'));
    expect(account, contains('softDelete: true'));
    expect(account,
        contains("DVStudioFieldSpec(name: 'secret', type: 'String', sensitive: true)"));
    expect(account, contains("DVStudioFieldSpec(name: 'joined', type: 'DateTime?')"));

    final String note = spec(pages, 'Note');
    // No String field: the first field is the key, as the model's own.
    expect(note, contains("key: 'order'"));
    expect(note, contains('versioned: false'));
  });

  test('the backend mounts the admin with the specs and the database',
      () async {
    await ModelGenerator.generate(
        root: root.path, pkgName: 'shop', buildId: 'b');
    await BackendGenerator.generate(
      root: root.path,
      backendDir: 'lib/backend',
      pkgName: 'shop',
      buildId: 'b',
      backendHost: '127.0.0.1',
      backendPort: 3000,
      apiBasePath: '/api',
    );
    final String routes = File(
            p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'))
        .readAsStringSync();

    expect(routes, contains('dartvelStudioModels'));
    expect(
      routes,
      contains('core.DVAdminServer(mount: admin, root: adminRoot, '
          'models: dartvelStudioModels, database: dartvelDatabase)'),
    );
  });
}
