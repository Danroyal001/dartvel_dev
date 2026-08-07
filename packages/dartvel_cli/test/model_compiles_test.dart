// The generated client has to be valid Dart, which the other model tests
// cannot tell.
//
// Every assertion elsewhere reads the emitted text. Text that reads correctly
// still fails to compile: `String?? subtitle` looks like a nullable
// parameter, `DateTime get x => y?.x ?? null` looks like a defaulted getter,
// and `const Post(publishedAt: DateTime.fromMillisecondsSinceEpoch(0))` looks
// like a const model. All three shipped, and a model with either a nullable
// field or a DateTime produced a client that did not compile at all.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A model covering the field shapes that broke: nullable, non-nullable,
/// defaultable, and a type with no sensible default.
const String _model = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Post {
  final String id;
  final String? subtitle;
  final String? contactEmail;
  final int views;
  final double rating;
  final bool published;
  final DateTime publishedAt;
  final DateTime? retractedAt;

  const _Post({
    required this.id,
    this.subtitle,
    this.contactEmail,
    required this.views,
    required this.rating,
    required this.published,
    required this.publishedAt,
    this.retractedAt,
  });
}
''';

Future<String> generate(String source) async {
  final root = await Directory.systemTemp.createTemp('dartvel_compiles_test_');
  try {
    Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);
    File(p.join(root.path, 'lib', 'models', 'model.dart'))
        .writeAsStringSync(source);

    await ModelGenerator.generate(
      root: root.path,
      pkgName: 'compiles_app',
      buildId: 'test-build',
    );

    return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
        .readAsStringSync();
  } finally {
    root.deleteSync(recursive: true);
  }
}

void main() {
  late String generated;

  setUpAll(() async {
    generated = await generate(_model);
  });

  test('copyWith does not double up the question mark', () {
    // `String?? subtitle` is a parse error, and it took the rest of the file
    // down with it.
    expect(generated, isNot(contains('?? subtitle')));
    expect(generated, isNot(contains('??  ')));
    expect(generated, contains('String? subtitle'));
    expect(generated, contains('DateTime? retractedAt'));
    // The non-nullable fields still become optional in copyWith.
    expect(generated, contains('String? id'));
    expect(generated, contains('DateTime? publishedAt'));
  });

  test('a form getter with no default admits it can return null', () {
    // `DateTime get publishedAt => post?.publishedAt ?? null` does not
    // type-check: there is no default DateTime to fall back to.
    expect(generated, isNot(contains('?? null;')));
    expect(generated, contains('DateTime? get publishedAt => post?.publishedAt;'));
    // Types that do have a default keep it, and keep their own type.
    expect(generated, contains("String get id => post?.id ?? '';"));
    expect(generated, contains('int get views => post?.views ?? 0;'));
    expect(generated, contains('bool get published => post?.published ?? false;'));
  });

  test('validation on a nullable string does not dereference it', () {
    // `subtitle.trim()` where subtitle is String? is a compile error.
    expect(generated, isNot(contains('subtitle.trim()')));
    expect(generated, contains("(subtitle ?? '').trim().isNotEmpty"));
    expect(generated, contains("(contactEmail ?? '').contains('@')"));
    // A non-nullable string needs no guard.
    expect(generated, contains('id.trim().isNotEmpty'));
  });

  test('the registered factory is not const', () {
    // The defaults include DateTime.fromMillisecondsSinceEpoch, which no
    // const invocation can hold. Calling a const constructor without const
    // is always legal; the reverse is not.
    expect(generated, contains('registerDVModelFactory<Post>(() => Post('));
    expect(
        generated, isNot(contains('registerDVModelFactory<Post>(() => const')));
    // The class still declares its const constructor.
    expect(generated, contains('const Post({'));
  });
}
