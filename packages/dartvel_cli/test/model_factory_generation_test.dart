// Generated factories, which had no tests at all.
//
// The spec writes `UserFactory().admin().create()` and expects it to be the
// normal way to make test data. The generated factory produced a constant for
// every field, so two calls returned two models with the same id -- a test
// that creates two users and keys them by id silently gets one, and the
// failure surfaces as an assertion about the wrong record rather than as
// anything about the factory.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _model = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  final String id;
  final String email;
  final String name;
  final int loginCount;

  const _User({
    required this.id,
    required this.email,
    required this.name,
    required this.loginCount,
  });
}
''';

Future<String> generate() async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_factory_test_');
  try {
    Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);
    File(p.join(root.path, 'lib', 'models', 'model.dart'))
        .writeAsStringSync(_model);

    await ModelGenerator.generate(
      root: root.path,
      pkgName: 'factory_app',
      buildId: 'test-build',
    );

    return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
        .readAsStringSync();
  } finally {
    root.deleteSync(recursive: true);
  }
}

/// Just the factory class.
String factoryOf(String generated) {
  final int start = generated.indexOf('class UserFactory {');
  final int end = generated.indexOf('\nclass ', start + 1);
  return generated.substring(start, end < 0 ? generated.length : end);
}

void main() {
  late String factory;

  setUpAll(() async {
    factory = factoryOf(await generate());
  });

  test('it exists, with the shape the spec writes', () {
    expect(factory, contains('UserFactory copyWith('));
    expect(factory, contains('UserFactory admin()'));
    expect(factory, contains('User create()'));
  });

  test('each created model gets its own identifier', () {
    // The bug: id defaulted to the constant 'id_1', so every user was the
    // same user. A sequence makes each call distinct.
    expect(factory, contains('_sequence'),
        reason: 'create() must vary the identifying fields between calls');
    // The field name is baked in and only the sequence interpolates. Escaping
    // both put a literal \${name} into the generated code, where it resolved
    // to the factory's own nullable `name` field and every id came out as
    // "null_1" -- which a contains() check for "_sequence" would have passed.
    expect(factory, contains(r"id: id ?? 'id_$n'"));
    expect(factory, isNot(contains(r"'${name}_")));
  });

  test('the sequence can be reset, so a test is deterministic', () {
    // Without a reset the ids depend on how many tests ran before this one,
    // which makes a golden or a snapshot assertion unrepeatable.
    expect(factory, contains('static void resetSequence()'));
  });

  test('a unique field is varied, a descriptive one is not', () {
    // An email carries a unique constraint in most schemas, so two records
    // with the same one fail to insert. A display name does not, and varying
    // it makes test expectations read strangely.
    expect(factory, contains(r"email ?? 'user$n@example.com'"));
    expect(factory, contains("name ?? 'Test User'"));
  });

  test('an explicit value still wins over the sequence', () {
    // copyWith is how a test says "this one, specifically".
    expect(factory, contains('id: id ??'));
    expect(factory, contains('email: email ??'));
  });

  test('it can make several at once', () {
    // Every list-shaped test needs this, and writing the loop by hand is
    // where people reach for a shared instance and reintroduce the
    // duplicate-id bug.
    expect(factory, contains('List<User> createMany('));
  });

  test('a non-identifying field keeps its stable default', () {
    expect(factory, contains('loginCount ?? 1'));
  });
}
