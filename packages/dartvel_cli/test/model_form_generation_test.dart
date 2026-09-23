// Model.Form, without a callback to wire.
//
// The generated form took one: Article.Form(article, (edited) => edited.save())
// -- and its own doc said that without it the form "has no one to hand a
// value to and shows no controls", so every caller wrote the same closure to
// get a form at all. Saving is what a form does; asking the application to
// say so each time is a line that can only be written one way.
//
// On the class it creates a record. On an instance it edits that record.
// Policies decide whether the reader may do either, as they do everywhere
// else.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> generated() async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_form_test_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'models', 'article.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Article {
  final String id;
  final String title;

  const _Article({required this.id, required this.title});
}
''');

  await ModelGenerator.generate(
    root: root.path,
    pkgName: 'form_app',
    buildId: 'test-build',
  );

  return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
      .readAsStringSync();
}

void main() {
  test('the form on the class takes nothing and creates', () async {
    final String content = await generated();

    expect(content, contains('static Widget Form() =>'),
        reason: 'no model to pass and no callback to write');
    expect(content, isNot(contains('static Widget Form(Article model,')),
        reason: 'the old shape asked for both');
  });

  test('the form on an instance edits that instance', () async {
    final String content = await generated();

    expect(content, contains('extension ArticleFormX on Article'));
    expect(content, contains('Widget Form() =>'));
  });

  test('both save, so nothing is handed a closure', () async {
    final String content = await generated();

    // Two forms, each saving the value it was given.
    expect(
      'save()'.allMatches(content).length,
      greaterThanOrEqualTo(2),
      reason: 'creating saves and editing saves',
    );
  });

  test('the admin still wires its own submit', () async {
    // The admin refreshes its list after a write, so it keeps a builder that
    // takes one. That is the framework's own call, not an application's.
    final String content = await generated();

    expect(content, contains('_dvFormWith'),
        reason: 'the two-argument form stays, and stays private');
  });
}
