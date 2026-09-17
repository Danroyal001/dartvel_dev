// The generated client imports the types a backend function names.
//
// functions.g.dart writes a function's return and parameter types into the
// client's signatures and imported none of them, so a function returning
// Future<Tick> or Stream<Tick>, with Tick in a file of the application's,
// generated a client that did not compile: "Type 'Tick' not found".
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_type_imports.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('dartvel_client_types');
    void write(String relative, String content) => File(
            p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    write('lib/shared/tick.dart', 'class Tick {}\nenum Phase { a }\n');
    write('lib/shared/io_only.dart', 'class Unused {}\n');
    write('lib/shared/sealed.dart', 'sealed class Shape {}\n');
  });

  tearDown(() => project.deleteSync(recursive: true));

  List<String> imports(String source, List<String> types) =>
      dvClientTypeImports(
        source: source,
        sourcePath: p.join(project.path, 'lib/backend/functions/ticks.get.dart'),
        projectRoot: project.path,
        packageName: 'probe',
        types: types,
      );

  test('a type declared in a relative import is imported by package URI', () {
    expect(
      imports("import '../../shared/tick.dart';\n", <String>['Stream<Tick>']),
      <String>['package:probe/shared/tick.dart'],
    );
  });

  test('a package import of the application itself is kept as it is', () {
    expect(
      imports("import 'package:probe/shared/tick.dart';\n",
          <String>['Future<List<Tick>>', 'Phase']),
      <String>['package:probe/shared/tick.dart'],
    );
  });

  test('only files that declare a named type are imported', () {
    expect(
      imports(
        "import 'dart:io';\n"
        "import 'package:dartvel_core/dartvel.dart';\n"
        "import '../../shared/io_only.dart';\n"
        "import '../../shared/sealed.dart';\n"
        "import '../../shared/tick.dart';\n",
        <String>['Future<Shape>', 'String', 'Map<String, Object?>'],
      ),
      <String>['package:probe/shared/sealed.dart'],
    );
  });

  test('core types and types nothing imports add nothing', () {
    expect(
      imports("import '../../shared/tick.dart';\n",
          <String>['Future<Map<String, dynamic>>', 'Stream<int>', 'Missing']),
      isEmpty,
    );
  });
}
