// What the generated backend tells Studio about each model.
//
// Studio on a web-server binary reads and edits records through the admin
// mount, and the backend cannot import the generated model classes to find
// them: those carry Flutter widgets. So the model generator writes, beside the
// public page specs, where each model's rows are -- the table, the key the
// generated find() uses, which fields are sensitive, whether rows belong to a
// tenant -- and the backend hands that to the admin server it mounts.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:dartvel_core/dartvel.dart' show DVStudioFieldSpec, DVStudioModelSpec;
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

  test('the models are also written as a manifest a development server reads',
      () async {
    await ModelGenerator.generate(
        root: root.path, pkgName: 'shop', buildId: 'b');
    final File manifest =
        File(p.join(root.path, '.dart_tool', 'dartvel_studio_models.json'));

    expect(manifest.existsSync(), isTrue);
    final List<Object?> models =
        (jsonDecode(manifest.readAsStringSync()) as Map)['models'] as List<Object?>;
    final DVStudioModelSpec account = DVStudioModelSpec.fromManifest(
      (models.cast<Map>().firstWhere((Map m) => m['model'] == 'Account'))
          .cast<String, Object?>(),
    );
    expect(account.table, 'accounts');
    expect(account.key, 'id');
    expect(account.tenantScoped, isTrue);
    expect(
      account.fields.firstWhere((DVStudioFieldSpec f) => f.name == 'secret').sensitive,
      isTrue,
    );
  });

  test('an enum field carries its values, and a field naming another model '
      'carries the relation', () async {
    File(p.join(root.path, 'lib', 'models', 'order.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

enum OrderStatus { placed, roasting, shipped }

enum Size {
  small('S'),
  large('L');

  const Size(this.label);
  final String label;
}

@DVModel()
@pragma('vm:entry-point')
class _Order {
  final String id;
  final OrderStatus? status;
  final Size? size;
  final String accountId;
  final List<String> tags;
  final Map<String, Object?>? extras;
  const _Order({required this.id, this.status, this.size, required this.accountId, required this.tags, this.extras});
}
''');
    await ModelGenerator.generate(
        root: root.path, pkgName: 'shop', buildId: 'b');
    final String order = spec(
      File(p.join(root.path, 'lib', 'dartvel_client', 'model_pages.g.dart'))
          .readAsStringSync(),
      'Order',
    );

    expect(
      order,
      contains("DVStudioFieldSpec(name: 'status', type: 'OrderStatus?', "
          "options: <String>['placed', 'roasting', 'shipped'])"),
    );
    expect(
      order,
      contains("DVStudioFieldSpec(name: 'size', type: 'Size?', "
          "options: <String>['small', 'large'])"),
    );
    expect(
      order,
      contains("DVStudioFieldSpec(name: 'accountId', type: 'String', "
          "relation: 'Account')"),
    );
    expect(order,
        contains("DVStudioFieldSpec(name: 'tags', type: 'List<String>')"));
  });

  test('a module\'s models are specified under the module, resolving their '
      'table through its mount', () async {
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: notes
dartvel:
  module:
    id: notes
''');
    await ModelGenerator.generate(
        root: root.path, pkgName: 'notes', buildId: 'b');
    final String pages = File(
            p.join(root.path, 'lib', 'dartvel_client', 'model_pages.g.dart'))
        .readAsStringSync();

    final String note = spec(pages, 'Note');
    expect(note, contains("module: 'notes'"));
    expect(note, contains('data: _dvModule'));
  });

  test('a mounted module\'s models are given to the admin beside the '
      'application\'s', () async {
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shop
dartvel:
  modules:
    notes:
      source: { path: modules/notes }
      mount: /notes
      deployment: embedded
      data: schema-isolated
''');
    final Directory module = Directory(p.join(root.path, 'modules', 'notes'))
      ..createSync(recursive: true);
    File(p.join(module.path, 'pubspec.yaml')).writeAsStringSync('''
name: shop_notes
dartvel:
  module:
    id: notes
''');
    File(p.join(module.path, 'lib', 'models', 'memo.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
@pragma('vm:entry-point')
class _Memo {
  final String id;
  final String text;
  const _Memo({required this.id, required this.text});
}
''');
    Directory(p.join(module.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);
    await ModelGenerator.generate(
        root: module.path, pkgName: 'shop_notes', buildId: 'b');
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

    final RegExpMatch? imported = RegExp(
      r"import 'package:shop_notes/dartvel_client/model_pages\.g\.dart' "
      r'as (\w+) show dartvelStudioModels;',
    ).firstMatch(routes);
    expect(imported, isNotNull,
        reason: 'the module\'s model specs are not imported');
    expect(
      routes,
      contains('...dartvelStudioModels, ...${imported!.group(1)}.dartvelStudioModels'),
    );
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
    // The pages Studio publishes are served to the web app, ahead of the
    // application's routes and of the admin.
    expect(routes, contains('core.DVPublishedPages(database: '));
    expect(routes, contains('await publishedPages.respond(request) ?? '));
    expect(
      routes,
      contains('core.DVAdminServer(mount: admin, root: adminRoot, '
          'models: dartvelStudioModels, database: dartvelDatabase)'),
    );
  });
}
