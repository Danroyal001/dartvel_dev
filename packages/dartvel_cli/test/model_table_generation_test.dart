// The generated Table has to be a table.
//
// User.Table() emitted DVBox.builder(...).grid(columns: 2) -- a grid of cards
// wearing the name. No header, no rows, no column, nothing to arrow between,
// and nothing a screen reader could announce as tabular, while the spec
// promises sorting, keyboard navigation, column management and accessibility
// from exactly this method.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _model = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Person {
  final String id;
  final String fullName;
  final int age;
  @DVModel.sensitiveField()
  final String passwordHash;

  const _Person({
    required this.id,
    required this.fullName,
    required this.age,
    required this.passwordHash,
  });
}
''';

Future<String> generate(String source) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_table_test_');
  try {
    Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);
    File(p.join(root.path, 'lib', 'models', 'model.dart'))
        .writeAsStringSync(source);

    await ModelGenerator.generate(
      root: root.path,
      pkgName: 'table_app',
      buildId: 'test-build',
    );

    return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
        .readAsStringSync();
  } finally {
    root.deleteSync(recursive: true);
  }
}

/// Just the Table method.
///
/// The assertions below are about what Table emits. Read against the whole
/// file they are meaningless: `passwordHash` is legitimately a field on the
/// model class, and List and Grid legitimately build a card grid.
String tableMethodOf(String generated) {
  final int start = generated.indexOf('static Widget Table');
  final int end = generated.indexOf('/// Generated page component', start);
  return generated.substring(start, end);
}

void main() {
  late String generated;
  late String table;

  setUpAll(() async {
    generated = await generate(_model);
    table = tableMethodOf(generated);
  });

  test('it emits a DVTable, not a grid of cards', () {
    expect(table, contains('DVTable<Person>('));
    expect(table, contains('columns: <DVTableColumn<Person>>['));
  });

  test('one column per field', () {
    expect(table, contains("label: 'Id'"));
    expect(table, contains("label: 'Full name'"));
    expect(table, contains("label: 'Age'"));
  });

  test('a camelCase field reads as a heading', () {
    // A header is shown to a reader and announced to a screen reader, so
    // "fullName" is the identifier, not the label.
    expect(table, contains("label: 'Full name'"));
    expect(table, isNot(contains("label: 'fullName'")));
  });

  test('a sensitive field is not a column', () {
    // The same rule that keeps it out of logs and AI context. A column is the
    // widest possible exposure -- it is on screen, in the semantics tree, and
    // in the crawler-visible HTML.
    expect(table, isNot(contains('passwordHash')),
        reason: 'a sensitive field must not reach the table');
    // It is still a field on the model; it is the column that must not exist.
    expect(generated, contains('passwordHash'));
  });

  test('a number sorts as a number, not as its text', () {
    // Comparing through toString sorts 10 before 9. It looks like it works
    // and orders nothing meaningfully, which is worse than not offering the
    // control at all.
    expect(table, contains('compare: (a, b) => a.age.compareTo(b.age)'));
    expect(table, isNot(contains('a.age.toString().compareTo')));
  });

  test('a string sorts in its own type too', () {
    expect(table,
        contains('compare: (a, b) => a.fullName.compareTo(b.fullName)'));
  });

  test('rows not here yet are the skeleton of the columns, not "No rows"', () {
    // A generated table knows its columns before it has rows. Null is a
    // load in flight; an empty iterable is a load that found nothing. They
    // render differently, and a loading table that announced "No rows" was
    // plausible and false.
    expect(table, contains('Iterable<Person>? models'));
    expect(table, contains('loading: models == null'));
    expect(table, contains('models?.toList(growable: false) ?? <Person>[]'));
  });

  test('the table takes a typed empty-state slot, nothing yet by default', () {
    // Nothing yet is what an empty generated collection is unless the
    // caller says otherwise, so one that declares no action is the one
    // DV-STATE-001 reports.
    expect(table, contains('DVEmpty? empty'));
    expect(table, contains('empty: empty ?? const DVEmpty.nothingYet()'));
  });

  test('so does the list, which says so rather than rendering nothing', () {
    final int start = generated.indexOf('static Widget List(');
    final String list =
        generated.substring(start, generated.indexOf('static Widget Table', start));
    expect(list, contains('DVEmpty? empty'));
    expect(list, contains('if (models.isEmpty)'));
    expect(
      list,
      contains(
        "DVEmptyView(empty ?? const DVEmpty.nothingYet(), collection: 'Person')",
      ),
    );
  });

  test('a builder still gives the card grid, for callers that want it', () {
    // The old behaviour stays reachable rather than being removed from under
    // anyone using it.
    expect(table, contains('if (builder != null)'));
    expect(table, contains('.grid(columns: columns)'));
  });

  test('a list not here yet is the skeleton of its fields, not empty', () {
    // Error, Empty, and Loading States: the card list and grid have a
    // skeleton derived from the model's field layout, as the table does.
    final int start = generated.indexOf('static Widget List(');
    final String list =
        generated.substring(start, generated.indexOf('static Widget Table', start));
    expect(list, contains('Iterable<Person>? models'));
    final int skeleton = list.indexOf('if (models == null)');
    expect(skeleton, isNot(-1));
    expect(skeleton, lessThan(list.indexOf('if (models.isEmpty)')),
        reason: 'loading is decided before empty, or a load reads as empty');
    expect(list,
        contains("DVSkeletonCards(fields: <String>['id', 'fullName', 'age'])"));
  });

  test('the card grid has the same skeleton, in its columns', () {
    expect(table,
        contains("DVSkeletonCards(fields: <String>['id', 'fullName', 'age'], columns: columns)"));
  });

  test('a sensitive field has no placeholder line either', () {
    // The skeleton is the shape of what the reader will see, and a sensitive
    // field is never shown in a generated collection.
    final int start = generated.indexOf('static Widget List(');
    final String list =
        generated.substring(start, generated.indexOf('static Widget Table', start));
    expect(list, isNot(contains("'passwordHash'")));
    expect(table, isNot(contains("'passwordHash'")));
  });
}
