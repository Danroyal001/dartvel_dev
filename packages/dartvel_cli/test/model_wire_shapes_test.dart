// Field shapes a real app (the Dartvel store) hit on 3.47.20.
//
// - An enum field went into toJson as the enum object, so jsonEncode threw
//   and a function answer holding the model was a 500; fromJson cast the
//   decoded string `as Mood` and threw on the way back.
// - A List of an enum or of a model stopped generation: the test factory had
//   no default for it.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _model = '''
import 'package:dartvel_core/dartvel.dart';

enum ListingState { draft, live, suspended }

@DVModel()
class _Screenshot {
  final String id;
  final String url;

  const _Screenshot({required this.id, required this.url});
}

@DVModel()
class _Listing {
  final String id;
  final String title;
  final ListingState state;
  final ListingState? previousState;
  final List<ListingState> history;
  final List<Screenshot> screenshots;
  final Map<String, ListingState> byChannel;

  const _Listing({
    required this.id,
    required this.title,
    this.state = ListingState.draft,
    this.previousState,
    this.history = const <ListingState>[],
    this.screenshots = const <Screenshot>[],
    this.byChannel = const <String, ListingState>{},
  });
}
''';

Future<String> generate(String source) async {
  final root = await Directory.systemTemp.createTemp('dartvel_wire_shapes_');
  try {
    Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);
    File(p.join(root.path, 'lib', 'models', 'model.dart'))
        .writeAsStringSync(source);
    await ModelGenerator.generate(
      root: root.path,
      pkgName: 'wire_app',
      buildId: 'test-build',
    );
    return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
        .readAsStringSync();
  } finally {
    root.deleteSync(recursive: true);
  }
}

/// The body of [member] inside Listing's generated extension (Screenshot,
/// declared first, has members of the same names).
String bodyOf(String generated, String member) {
  final scope = generated.indexOf('extension ListingDartvelExtension');
  final start = member.startsWith('static Listing')
      ? generated.indexOf(member)
      : generated.indexOf(member, scope);
  expect(start, greaterThan(-1), reason: 'no $member was generated');
  final end = generated.indexOf('  }', start);
  return generated.substring(start, end == -1 ? generated.length : end);
}

void main() {
  late String generated;
  setUpAll(() async => generated = await generate(_model));

  test('an enum field leaves as its name, which jsonEncode can write', () {
    final toJson = bodyOf(generated, 'Map<String, Object?> toJson()');
    expect(toJson, contains("'state': state.name"));
    expect(toJson, contains("'previousState': previousState?.name"));
    expect(toJson, contains("'history': history.map((item) => item.name).toList()"));
    expect(toJson, contains("'byChannel': byChannel.map((key, value) => MapEntry(key, value.name))"));
    final toPublicJson = bodyOf(generated, 'Map<String, Object?> toPublicJson()');
    expect(toPublicJson, contains("'state': state.name"));
  });

  test('an enum field is read back from its name, not cast', () {
    final fromJson = bodyOf(generated, 'static Listing fromJson(');
    expect(fromJson, isNot(contains('as ListingState')));
    expect(fromJson, contains("ListingState.values.byName(json['state'] as String)"));
    expect(fromJson,
        contains("json['previousState'] == null ? null : (ListingState.values.byName(json['previousState'] as String))"));
    expect(fromJson, contains('ListingState.values.byName(item as String)'));
    expect(fromJson, contains('ListingState.values.byName(value as String)'));
  });

  test('a stored list of enums is read back from names too', () {
    // A row holds the list as JSON text of names; a cast of each name to the
    // enum throws on the first read from the database.
    expect(generated, isNot(contains('(item) => item as ListingState')));
  });

  test('a list of models leaves as JSON maps', () {
    final toJson = bodyOf(generated, 'Map<String, Object?> toJson()');
    expect(toJson, contains("'screenshots': screenshots.map((item) => item.toJson()).toList()"));
  });

  test('the test factory defaults a list or map of enums or models to empty', () {
    expect(generated, contains('history: history ?? const <ListingState>[]'));
    expect(generated, contains('screenshots: screenshots ?? const <Screenshot>[]'));
    expect(generated, contains('byChannel: byChannel ?? const <String, ListingState>{}'));
  });
  test('inside the model class a list is core.List, not the List widget', () {
    // The class declares a static List widget, so a bare List<String> in its
    // header or body is that member and the app does not compile.
    final header = generated.substring(
        generated.indexOf('class const Listing('), generated.indexOf(') {', generated.indexOf('class const Listing(')));
    expect(header, contains('core.List<ListingState> history'));
    expect(header, isNot(contains(' List<')));
    final fromRow = bodyOf(generated, 'static Listing _fromRow(');
    expect(fromRow, isNot(contains('as List)')));
  });

  test('a field with a default or a nullable type is optional in the constructor', () {
    final header = generated.substring(
        generated.indexOf('class const Listing('), generated.indexOf(') {', generated.indexOf('class const Listing(')));
    expect(header, contains('required final String id,'));
    expect(header, contains('required final String title,'));
    expect(header, contains('final ListingState state = ListingState.draft,'));
    expect(header, contains('final ListingState? previousState,'));
    expect(header, isNot(contains('required final ListingState? previousState')));
    expect(header, contains('final core.List<ListingState> history = const <ListingState>[],'));
  });
}
