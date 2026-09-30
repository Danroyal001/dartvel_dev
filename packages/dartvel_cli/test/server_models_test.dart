// A backend is compiled without Flutter, and models.g.dart imports it for
// the widgets. So a backend function could not name Product.all(), and the
// example's catalogue wrote the model's table, key and columns out a second
// time to read rows by hand. models_server.g.dart is the same library
// without the widgets, and these tests compile and run it with plain Dart.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String corePath = p.normalize(p.absolute('..', 'dartvel_core'));

Future<Directory> project() async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_server_models_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: server_models_app
environment:
  sdk: ">=3.13.0 <4.0.0"
dependencies:
  dartvel_core:
    path: $corePath
''');
  File(p.join(root.path, 'lib', 'models', 'note.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(searchable: true, semantic: true, generatePublicPages: false)
class const _Note({
  required final String id,
  @DVModel.searchableField() required final String title,
  @DVModel.searchableField() required final String body,
  @DVModel.sensitiveField() final String owner = '',
  final int views = 0,
});
''');
  await ModelGenerator.generate(
      root: root.path, pkgName: 'server_models_app', buildId: 'test-build');
  return root;
}

void main() {
  test('the server library names no Flutter and keeps the data surface',
      () async {
    final Directory root = await project();
    final String server = File(p.join(
            root.path, 'lib', 'dartvel_client', 'models_server.g.dart'))
        .readAsStringSync();

    expect(server, isNot(contains('package:flutter/')));
    expect(server, isNot(contains('package:dartvel_flutter/')));
    expect(server, isNot(contains('Widget')));
    for (final String member in <String>[
      'static Future<Note> save(',
      'static Future<Note?> find(String id)',
      'static Future<DVSearchResultPage<Note>> search(',
      'static Future<DVSemanticPage<Note>> semanticSearch(',
      'static Future<int> semanticBackfill(',
      'Map<String, Object?> toJson()',
    ]) {
      expect(server, contains(member));
    }
  });

  test('a plain Dart program saves, finds and searches through it', () async {
    final Directory root = await project();
    File(p.join(root.path, 'bin', 'main.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:server_models_app/dartvel_client/dartvel_server.dart';

Future<void> main() async {
  registerDartvelModels();
  const DVDatabase().configure(SqliteDVDatabaseAdapter.memory());
  // What the generated backend's migration does on start.
  await const DVDatabase().execute('CREATE TABLE IF NOT EXISTS notes (id TEXT, title TEXT, body TEXT, owner TEXT, views TEXT, _dv_version INTEGER NOT NULL DEFAULT 1, _dv_deleted_at TEXT)');
  await const Note(id: 'n1', title: 'Deploying', body: 'Copy one file to a server.', owner: 'a', views: 1).save();
  await const Note(id: 'n2', title: 'Caching', body: 'Get, set, has and delete.', owner: 'b', views: 2).save();
  final Note? found = await Note.find('n2');
  print('found \${found?.title}');
  print('all \${(await Note.all()).length}');
  final List<Note> notes = await Note.all();
  Note.useSearchProvider(DVInMemorySearchProvider<Note, NoteFacets>(
      records: notes, document: (Note n) => '\${n.title} \${n.body}'));
  Note.useSemanticSearch(
      embedder: DVLatentSemanticEmbedder.fit(<String>[
    for (final Note n in notes) '\${n.title} \${n.body}',
  ], dimensions: 2));
  print('embedded \${await Note.semanticBackfill()}');
  final DVSemanticPage<Note> page =
      await Note.semanticSearch('copy to a server', mode: DVSearchMode.hybrid);
  print('hybrid \${page.items.first.id}');
}
''');
    final ProcessResult get = await Process.run(
        Platform.resolvedExecutable, <String>['pub', 'get'],
        workingDirectory: root.path);
    expect(get.exitCode, 0, reason: '${get.stdout}${get.stderr}');
    final ProcessResult run = await Process.run(
        Platform.resolvedExecutable, <String>['run', 'bin/main.dart'],
        workingDirectory: root.path);
    expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
    expect('${run.stdout}', contains('found Caching'));
    expect('${run.stdout}', contains('all 2'));
    expect('${run.stdout}', contains('embedded 2'));
    expect('${run.stdout}', contains('hybrid n1'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
