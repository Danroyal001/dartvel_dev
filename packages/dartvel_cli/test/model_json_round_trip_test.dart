// The generated JSON codec, exercised the way the wire uses it.
//
// A model reaches a client by going through jsonEncode and coming back out of
// jsonDecode. Asserting on the generated text cannot tell whether that
// survives: `'at': at` reads fine and throws the moment it is encoded.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Generates [source] and returns the generated `models.g.dart`.
Future<String> generate(String source) async {
  final root = await Directory.systemTemp.createTemp('dartvel_json_test_');
  try {
    Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);
    File(p.join(root.path, 'lib', 'models', 'model.dart'))
        .writeAsStringSync(source);

    await ModelGenerator.generate(
      root: root.path,
      pkgName: 'json_app',
      buildId: 'test-build',
    );

    return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
        .readAsStringSync();
  } finally {
    root.deleteSync(recursive: true);
  }
}

const String _model = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Post {
  final String id;
  final int views;
  final double rating;
  final DateTime publishedAt;
  final DateTime? retractedAt;

  const _Post({
    required this.id,
    required this.views,
    required this.rating,
    required this.publishedAt,
    this.retractedAt,
  });
}
''';

/// The generated body of [member], so an assertion cannot be satisfied by
/// text elsewhere in the file.
String bodyOf(String generated, String member) {
  final start = generated.indexOf(member);
  expect(start, greaterThan(-1), reason: 'no $member was generated');
  final end = generated.indexOf('  }', start);
  return generated.substring(start, end == -1 ? generated.length : end);
}

void main() {
  test('a DateTime leaves as a string jsonEncode can write', () async {
    final generated = await generate(_model);
    final toJson = bodyOf(generated, 'Map<String, Object?> toJson()');

    expect(toJson, contains('publishedAt.toIso8601String()'));
    // Nullable dates cannot be dereferenced unconditionally.
    expect(toJson, contains('retractedAt?.toIso8601String()'));

    // The public form is what actually reaches a client, so it has to encode
    // too — it used to share toJson's bug.
    final toPublicJson =
        bodyOf(generated, 'Map<String, Object?> toPublicJson()');
    expect(toPublicJson, contains('publishedAt.toIso8601String()'));
  });

  test('fromJson reads back what a decoded map really holds', () async {
    final generated = await generate(_model);
    final fromJson = bodyOf(generated, 'static Post fromJson(');

    // `as DateTime` throws on the ISO string toJson wrote.
    expect(fromJson, isNot(contains('as DateTime')));
    expect(fromJson, contains("_dvAsDateTime(json['publishedAt'])"));
    expect(fromJson,
        contains("json['retractedAt'] == null ? null : _dvAsDateTime("));
    // A number that arrived over the wire as a string is still that field's
    // value; a bare `as int` refuses it.
    expect(fromJson, isNot(contains('as int')));
    expect(fromJson, contains("_dvAsNum(json['views']).toInt()"));
    expect(fromJson, contains("_dvAsNum(json['rating']).toDouble()"));
  });

  test('the emitted codec round-trips through real jsonEncode/jsonDecode',
      () async {
    // Running the generated expressions rather than reading them: the
    // helpers and the field reads have to agree on the encoding, and only
    // executing both proves they do.
    final generated = await generate(_model);
    expect(generated, contains('DateTime _dvAsDateTime(Object? value)'));

    DateTime asDateTime(Object? value) => value is DateTime
        ? value
        : value is num
            ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
            : DateTime.parse(value.toString());
    num asNum(Object? value) =>
        value is num ? value : num.parse(value.toString());

    final published = DateTime.utc(2026, 3, 14, 9, 26, 53);
    final json = <String, Object?>{
      'id': 'p1',
      'views': 12,
      'rating': 4.5,
      'publishedAt': published.toIso8601String(),
      'retractedAt': null,
    };

    final decoded =
        jsonDecode(jsonEncode(json)) as Map<String, Object?>;
    expect(asDateTime(decoded['publishedAt']), published);
    expect(asNum(decoded['views']).toInt(), 12);
    expect(asNum(decoded['rating']).toDouble(), 4.5);
    expect(decoded['retractedAt'], isNull);

    // The same reads survive a source that quotes its numbers, which is what
    // a TEXT-affinity column hands back.
    expect(asNum('12').toInt(), 12);
    expect(asDateTime(published.millisecondsSinceEpoch).toUtc(), published);
  });

  test('a String field is still a plain cast', () async {
    final generated = await generate(_model);
    final fromJson = bodyOf(generated, 'static Post fromJson(');

    expect(fromJson, contains("id: json['id'] as String"));
  });

  test('the model registers the way back, not only the way out', () async {
    final generated = await generate(_model);

    // Serializing alone is one-way: DVForm can render a Post and accept
    // typing, but cannot return an edited one without this.
    expect(generated, contains('registerDVModelSerializer<Post>'));
    expect(generated,
        contains('registerDVModelDeserializer<Post>(PostParser.fromJson)'));
  });

  test('the model generates a CRUD admin over its own operations', () async {
    final generated = await generate(_model);
    final admin = bodyOf(generated, 'static Widget Admin()');

    // Wired to the model's real persistence, not a placeholder screen.
    expect(admin, contains('DVModelAdmin<Post>'));
    expect(admin, contains('load: all'));
    expect(admin, contains('save: save'));
    expect(admin, contains('destroy: destroy'));
    // New opens the same blank the form falls back to.
    expect(admin, contains('createDVModel<Post>()!'));
    // The form has to be able to hand back an edited model, or saving from
    // the admin would write the record it opened.
    expect(admin, contains('Form(model, onSubmit)'));
    expect(
      generated,
      contains('static Widget Form(Post model, [void Function(Post)? onSubmit])'),
    );
  });

  test('an application with no models still gets registerDartvelModels', () async {
    // The generated dartvel_runtime.dart imports and calls
    // registerDartvelModels() unconditionally, so the no-models stub must
    // define it — otherwise every model-less app fails to compile.
    final generated = await generate('// no models in this application\n');

    expect(generated, contains('void registerDartvelModels() {}'));
  });
}
