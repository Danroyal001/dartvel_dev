// Every format the section lists is read and written by the data model
// itself. These compile the generated server library with plain Dart and run
// the members, so a format that is written and cannot be read back -- or one
// whose writer no member reaches -- fails here rather than in an application.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String corePath = p.normalize(p.absolute('..', 'dartvel_core'));

Future<Directory> project() async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_data_io_formats_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: data_io_app
environment:
  sdk: ">=3.13.0 <4.0.0"
dependencies:
  dartvel_core:
    path: $corePath
''');
  File(p.join(root.path, 'lib', 'models', 'note.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(generatePages: false)
class const _Note({
  required final String id,
  required final String title,
  @DVModel.sensitiveField() final String owner = '',
  final int views = 0,
});
''');
  await ModelGenerator.generate(
      root: root.path, pkgName: 'data_io_app', buildId: 'test-build');
  return root;
}

Future<String> run(Directory root, String body) async {
  File(p.join(root.path, 'bin', 'main.dart'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:data_io_app/dartvel_client/dartvel_server.dart';

Future<void> main() async {
  registerDartvelModels();
  const List<Note> notes = <Note>[
    Note(id: 'n1', title: 'Deploying, "quoted"', owner: 'alice', views: 3),
    Note(id: 'n2', title: 'Caching', owner: 'bob', views: 5),
  ];
  $body
}
''');
  final ProcessResult get = await Process.run(
      Platform.resolvedExecutable, <String>['pub', 'get'],
      workingDirectory: root.path);
  expect(get.exitCode, 0, reason: '${get.stdout}${get.stderr}');
  final ProcessResult result = await Process.run(
      Platform.resolvedExecutable, <String>['run', 'bin/main.dart'],
      workingDirectory: root.path);
  expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  return '${result.stdout}';
}

void main() {
  test('an export without its sensitive column reads back', () async {
    // An export leaves a sensitive field out by default, and the importer
    // cast the missing value to String: every row of every CSV and NDJSON
    // export of a data model with a sensitive field failed to import, each
    // with "type 'Null' is not a subtype of type 'String'". A field the file
    // does not carry takes its declared default, as a stored row does; a
    // required one with no default is a row error naming the field.
    final Directory root = await project();
    final String out = await run(root, r'''
  final DVImportResult<Note> csv =
      Note.importCsv(utf8.decode(Note.exportCsv(notes).bytes));
  print('csv ${csv.items.length} errors ${csv.errors.length}');
  print('csv owner [${csv.items.first.owner}] views ${csv.items.first.views}');
  final DVImportResult<Note> ndjson =
      Note.importNdjson(utf8.decode(Note.exportNdjson(notes).bytes));
  print('ndjson ${ndjson.items.length} errors ${ndjson.errors.length}');
  final DVImportResult<Note> noTitle = Note.importNdjson('{"id":"x"}');
  print('missing ${noTitle.errors.single.message.contains('Note.title')}');
''');
    expect(out, contains('csv 2 errors 0'));
    expect(out, contains('csv owner [] views 3'));
    expect(out, contains('ndjson 2 errors 0'));
    expect(out, contains('missing true'));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a JSON export reads back through importJson', () async {
    // exportJson wrote an array of objects and nothing read one: the section
    // lists JSON import beside CSV, NDJSON and Excel, and the model had the
    // other three.
    final Directory root = await project();
    final String out = await run(root, r'''
  final DVExportResult file = Note.exportJson(notes);
  final DVImportResult<Note> back = Note.importJson(utf8.decode(file.bytes));
  print('items ${back.items.length} errors ${back.errors.length}');
  print('first ${back.items.first.title} views ${back.items.first.views}');
  // The sensitive field was left out of the file, so it reads back empty.
  print('owner [${back.items.first.owner}]');

  // A bad element is a row error naming its position; the good ones import.
  final DVImportResult<Note> mixed =
      Note.importJson('[{"id":"a","title":"A"}, 7, {"title":"no id"}]');
  print('mixed ${mixed.items.length} rows ${mixed.errors.map((DVImportRowError e) => e.row).join(',')}');

  // A document that is not an array of records is not a row problem.
  try {
    Note.importJson('{"id":"a"}');
    print('accepted an object');
  } on FormatException catch (error) {
    print('refused ${error.message.contains('Note')}');
  }
''');
    expect(out, contains('items 2 errors 0'));
    expect(out, contains('first Deploying, "quoted" views 3'));
    expect(out, contains('owner []'));
    expect(out, contains('mixed 1 rows 2,3'));
    expect(out, contains('refused true'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
