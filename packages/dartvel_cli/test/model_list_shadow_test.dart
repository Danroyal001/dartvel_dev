// Inside a generated model, List is a widget.
//
// `User.List(users, builder: ...)` is the documented surface, so the class
// holds a static member called List -- and inside that class body a bare
// `List<String>` is that member, not the type. Three separate lines of the
// generator hit this on three separate days: importResumableCsv's return
// type, and the synonyms map of a model whose pubspec configures any, which
// nothing here read until a docs sample declared one.
//
// The file imports `dart:core as core`, so `core.List` is always correct and
// always available. This reads the class body and insists on it, rather than
// waiting for the next member to be added.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Everything a model can turn on at once, so a member added behind any one
/// flag is covered here.
const String _model = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(
  searchable: true,
  semantic: true,
  capture: true,
  softDelete: true,
  offline: DVConflict.lastWriteWins,
  history: DVHistory(keep: Duration(days: 365)),
  generatePublicPages: true,
)
class _Article {
  final String slug;

  @DVModel.pageTitle()
  final String title;

  @DVModel.mainContent()
  final String body;

  @DVModel.searchableField()
  final String tags;

  final bool published;
  final int views;
  final DateTime writtenAt;

  @DVModel.sensitiveField()
  final String editorNotes;

  const _Article({
    required this.slug,
    required this.title,
    required this.body,
    required this.tags,
    required this.published,
    required this.views,
    required this.writtenAt,
    required this.editorNotes,
  });
}
''';

/// The pubspec a real project has: `dartvel.search` with synonyms, which is
/// what put `<String, List<String>>` in the class body.
const String _pubspec = '''
name: shadow_app
environment:
  sdk: ^3.13.0
dartvel:
  search:
    synonyms:
      refund:
        - return
        - chargeback
''';

Future<String> generated() async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_list_shadow_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(_pubspec);
  File(p.join(root.path, 'lib', 'models', 'article.dart'))
      .writeAsStringSync(_model);

  await ModelGenerator.generate(
    root: root.path,
    pkgName: 'shadow_app',
    buildId: 'test-build',
  );

  return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
      .readAsStringSync();
}

/// The source of `class <name> {` up to its closing brace.
String classBody(String source, String name) {
  final int start = source.indexOf('class $name {');
  expect(start, isNonNegative, reason: 'no class $name in the generated file');
  int depth = 0;
  for (int i = source.indexOf('{', start); i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  fail('class $name is not closed');
}

void main() {
  test('the class really does shadow List, so the rest of this means '
      'something', () async {
    expect(
      classBody(await generated(), 'Article'),
      contains('static Widget List('),
    );
  });

  test('and no type inside it is written as a bare List', () async {
    final String body = classBody(await generated(), 'Article');

    // `List<` anywhere that is not `core.List<`. A list literal such as
    // `<String>[...]` never names List and is not matched.
    final List<String> bare = <String>[
      for (final RegExpMatch match
          in RegExp(r'(\w*\.)?\bList\s*<').allMatches(body))
        if (match.group(1) != 'core.')
          body
              .substring(
                  match.start - 60 < 0 ? 0 : match.start - 60, match.end + 40)
              .trim(),
    ];

    expect(bare, isEmpty,
        reason: 'inside the class body these are the static List member, '
            'not the type. Write core.List.');
  });

  test('the synonyms the pubspec declares are still there', () async {
    // So that a fix which simply stopped emitting them would fail here.
    final String body = classBody(await generated(), 'Article');

    expect(body, contains("'refund': <String>['return', 'chargeback']"));
  });
}
