// A data model's key has to be a value find() and destroy() can compare.
//
// With no String field the key fell back to the first field, whatever it
// was. A nested data model there produced a destroy that did not compile, so
// the app stopped building with the error inside a generated file.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> generate(String source) async {
  final root = await Directory.systemTemp.createTemp('dartvel_key_field_');
  try {
    Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
    File(p.join(root.path, 'lib', 'models', 'model.dart')).writeAsStringSync(source);
    await ModelGenerator.generate(root: root.path, pkgName: 'key_app', buildId: 'test-build');
    return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart')).readAsStringSync();
  } finally {
    root.deleteSync(recursive: true);
  }
}

void main() {
  test('a data model with no String field is refused with a reason, naming the model', () async {
    const String source = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(generatePages: false)
class _Place({required final double lat, required final double lng});

@DVModel(generatePages: false)
class _Visit({required final Place place, required final int minutes});
''';
    await expectLater(
      generate(source),
      throwsA(isA<StateError>().having((StateError error) => error.message, 'message',
          allOf(contains('Visit'), contains('String'), contains('id')))),
    );
  });

  test('the test factory makes a nested data model with that model\'s own factory', () async {
    // It had no default for a field typed with another data model and stopped
    // generation.
    final String generated = await generate('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(generatePages: false)
class _Place({required final String id, required final double lat});

@DVModel(generatePages: false)
class _Visit({required final String id, required final Place place});
''');
    expect(generated, contains('place: place ?? PlaceFactory().create()'));
  });
}
