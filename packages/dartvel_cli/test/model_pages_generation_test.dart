// The generated backend resolves a model's public page on request.
//
// The generated model class carries a Flutter widget, so the backend cannot
// import it. What the backend needs is data: where the rows are and which
// fields carry the title, the content, the image and whether the row is
// published. That goes into a pure-Dart file beside the models, and the
// backend's server resolves a page's data from it through the shared
// pipeline -- so /users/ada is Ada's page the moment it is asked for.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<Directory> project() async {
  final Directory root = await Directory.systemTemp.createTemp('dartvel_model_pages_');
  Directory(p.join(root.path, '.dart_tool')).createSync();
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'backend', 'functions')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'models', 'user.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(generatePublicPages: true)
@pragma('vm:entry-point')
class _User {
  final String slug;
  @DVModel.pageTitle()
  final String name;
  @DVModel.mainContent()
  final String bio;
  @DVModel.featuredImage()
  final String avatar;
  final bool published;
  const _User({required this.slug, required this.name, required this.bio, required this.avatar, required this.published});
}
''');
  File(p.join(root.path, 'lib', 'models', 'note.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
@pragma('vm:entry-point')
class _Note {
  final String id;
  final String text;
  const _Note({required this.id, required this.text});
}
''');
  return root;
}

void main() {
  late Directory root;
  setUp(() async => root = await project());
  tearDown(() => root.deleteSync(recursive: true));

  test('model_pages.g.dart names each public page\'s rows and fields, and imports no Flutter', () async {
    await ModelGenerator.generate(root: root.path, pkgName: 'shop', buildId: 'b');
    final String pages = File(p.join(root.path, 'lib', 'dartvel_client', 'model_pages.g.dart')).readAsStringSync();

    expect(pages, isNot(contains('package:flutter')));
    expect(pages, contains('const List<DVModelPageSpec> dartvelModelPages'));
    expect(pages, contains("model: 'User'"));
    expect(pages, contains("route: '/users/:slug'"));
    expect(pages, contains("param: 'slug'"));
    expect(pages, contains("table: 'users'"));
    expect(pages, contains("keyField: 'slug'"));
    expect(pages, contains("titleField: 'name'"));
    expect(pages, contains("contentFields: <String>['bio']"));
    expect(pages, contains("imageField: 'avatar'"));
    expect(pages, contains("publishedField: 'published'"));
    expect(pages, isNot(contains("model: 'Note'")), reason: 'a model with no public pages has no page to resolve');
  });

  test('the backend starts its server with the resolver, over the built site', () async {
    await ModelGenerator.generate(root: root.path, pkgName: 'shop', buildId: 'b');
    await BackendGenerator.generate(
      root: root.path,
      backendDir: 'lib/backend',
      pkgName: 'shop',
      buildId: 'b',
      backendHost: '127.0.0.1',
      backendPort: 3000,
      apiBasePath: '/api',
    );
    final String routes = File(p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart')).readAsStringSync();

    // Package-relative: the routes file lives under .dart_tool, where a
    // relative path to lib/ points nowhere.
    expect(routes, contains("import 'package:shop/dartvel_client/model_pages.g.dart'"));
    expect(routes, contains('core.dvModelPageResolver('));
    expect(routes, contains('  dartvelModelPages,'));
    expect(routes, contains('String? spaRoot'));
    expect(routes, contains('spaRoot: spaRoot'));
    expect(routes, contains('pageData: dartvelPageData'));
  });
}
