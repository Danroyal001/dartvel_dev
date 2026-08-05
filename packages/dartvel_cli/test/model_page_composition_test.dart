import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Generates [source] as `lib/models/model.dart` and returns the generated
/// `models.g.dart`.
Future<String> generate(String source) async {
  final root = await Directory.systemTemp.createTemp('dartvel_page_test_');
  try {
    Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);
    File(p.join(root.path, 'lib', 'models', 'model.dart'))
        .writeAsStringSync(source);

    await ModelGenerator.generate(
      root: root.path,
      pkgName: 'page_app',
      buildId: 'test-build',
    );

    return File(
      p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
    ).readAsStringSync();
  } finally {
    root.deleteSync(recursive: true);
  }
}

/// The generated `PageBody` body, so ordering assertions cannot be satisfied
/// by text elsewhere in the file.
String pageBodyOf(String generated) {
  final start = generated.indexOf('static Widget PageBody(');
  expect(start, greaterThan(-1), reason: 'no PageBody was generated');
  final end = generated.indexOf('  }', start);
  return generated.substring(start, end);
}

void main() {
  test('explicit annotations drive the page composition', () async {
    final generated = await generate('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Post {
  final String id;
  @DVModel.featuredImage()
  final DVImage cover;
  @DVModel.pageTitle()
  final String headline;
  @DVModel.mainContent()
  final String body;
  @DVModel.pageOrder(1)
  final String author;
  @DVModel.hideFromPage()
  final String internalReference;

  const _Post({
    required this.id,
    required this.cover,
    required this.headline,
    required this.body,
    required this.author,
    required this.internalReference,
  });
}
''');

    expect(generated, contains("static const String? pageTitleField = 'headline';"));
    expect(
      generated,
      contains("static const String? featuredImageField = 'cover';"),
    );
    expect(
      generated,
      contains("static const core.List<String> mainContentFields = <String>['body'];"),
    );
    expect(
      generated,
      contains(
        "static const Set<String> hiddenPageFields = <String>{'internalReference'};",
      ),
    );

    final body = pageBodyOf(generated);
    // Spec order: featured image, title, main content, then the rest.
    expect(
      body.indexOf('DVImageView(model.cover)'),
      lessThan(body.indexOf('model.headline')),
    );
    expect(
      body.indexOf('model.headline'),
      lessThan(body.indexOf('_mainContentOf(model)')),
    );
    expect(
      body.indexOf('_mainContentOf(model)'),
      lessThan(body.indexOf('model.author')),
    );
    // @DVModel.pageOrder(1) puts author ahead of the unannotated id.
    expect(body.indexOf('model.author'), lessThan(body.indexOf('model.id')));
    // @DVModel.hideFromPage() keeps the field off the page but on the model.
    expect(body, isNot(contains('internalReference')));
    expect(generated, contains('final String internalReference;'));
  });

  test('composition is inferred when nothing is annotated', () async {
    final generated = await generate('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Article {
  final String id;
  final DVImage? banner;
  final String title;
  final String summary;

  const _Article({
    required this.id,
    this.banner,
    required this.title,
    required this.summary,
  });
}
''');

    // First DVImage field is the featured image; a `title` field is the title.
    expect(
      generated,
      contains("static const String? featuredImageField = 'banner';"),
    );
    expect(generated, contains("static const String? pageTitleField = 'title';"));
    // Every remaining string is a main-content candidate: the spec picks the
    // largest text block, which is only knowable from the record's values.
    expect(
      generated,
      contains(
        "static const core.List<String> mainContentFields = <String>['id', 'summary'];",
      ),
    );
  });

  test('sensitive fields never reach a generated page', () async {
    final generated = await generate('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Account {
  final String id;
  final String name;
  @DVModel.sensitiveField()
  final String taxNumber;

  const _Account({
    required this.id,
    required this.name,
    required this.taxNumber,
  });
}
''');

    final body = pageBodyOf(generated);
    expect(body, isNot(contains('taxNumber')));
    expect(body, contains('model.name'));
    // Nor as a main-content candidate, which would put it on the page
    // whenever it happened to be the longest value.
    expect(
      generated,
      contains("static const core.List<String> mainContentFields = <String>['id'];"),
    );
  });

  test('a nullable main-content field is read without a null check',
      () async {
    // `?.` on a non-nullable field is an analyzer warning, so the generator
    // must emit null handling only where the field can actually be null.
    final generated = await generate('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Note {
  final String title;
  final String? body;

  const _Note({required this.title, this.body});
}
''');

    expect(generated, contains("model.body ?? ''"));
    expect(generated, isNot(contains('model.body?.toString()')));
  });

  test('the page renders the composition rather than the card', () async {
    final generated = await generate('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Product {
  final String id;
  final String name;

  const _Product({required this.id, required this.name});
}
''');

    expect(generated, contains('final render = builder ?? Product.PageBody;'));
    // Card stays as the compact representation lists and tables use.
    expect(generated, contains('static Widget Card(Product model)'));
  });
}
