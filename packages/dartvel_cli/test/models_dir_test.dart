// Project Structure: modelsDir under the dartvel: key.
//
// The key was read into DartvelConfig and then ignored -- the model generator,
// the model-name scan, dartvel db, dartvel admin and the static-paths check
// all globbed lib/models/**.dart themselves -- so a project that set
// modelsDir: lib/data got a client with no data models and no error saying
// why. The section also offers globs and several places at once, which
// nothing read.
import 'dart:io';

import 'package:dartvel_cli/src/config/source_paths.dart';
import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _book = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Book {
  final String title;
  const _Book({required this.title});
}
''';

const String _shelf = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Shelf {
  final String name;
  const _Shelf({required this.name});
}
''';

Directory _project(String dartvelYaml, Map<String, String> files) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_models_dir_');
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
    'name: models_dir_app\n'
    'environment:\n  sdk: ^3.13.0\n'
    '$dartvelYaml',
  );
  for (final MapEntry<String, String> file in files.entries) {
    File(p.join(root.path, file.key))
      ..createSync(recursive: true)
      ..writeAsStringSync(file.value);
  }
  return root;
}

List<String> _relative(Directory root, List<File> files) => <String>[
      for (final File f in files) p.posix.joinAll(p.split(p.relative(f.path, from: root.path))),
    ];

void main() {
  group('dvModelSourceFiles', () {
    test('defaults to lib/models', () {
      final Directory root = _project('', <String, String>{
        'lib/models/book.dart': _book,
        'lib/data/shelf.dart': _shelf,
      });
      addTearDown(() => root.deleteSync(recursive: true));
      expect(_relative(root, dvModelSourceFiles(root.path)), <String>['lib/models/book.dart']);
    });

    test('reads one directory from modelsDir', () {
      final Directory root = _project('dartvel:\n  modelsDir: lib/data\n', <String, String>{
        'lib/models/book.dart': _book,
        'lib/data/shelf.dart': _shelf,
      });
      addTearDown(() => root.deleteSync(recursive: true));
      expect(_relative(root, dvModelSourceFiles(root.path)), <String>['lib/data/shelf.dart']);
    });

    test('reads several places, directories and globs, once each and in order', () {
      final Directory root = _project(
        'dartvel:\n'
        '  modelsDir:\n'
        '    - lib/models\n'
        '    - lib/features/*/models\n'
        '    - lib/models\n',
        <String, String>{
          'lib/models/book.dart': _book,
          'lib/features/shop/models/shelf.dart': _shelf,
          'lib/features/shop/pages/home.dart': '// not a model file',
        },
      );
      addTearDown(() => root.deleteSync(recursive: true));
      expect(_relative(root, dvModelSourceFiles(root.path)), <String>[
        'lib/features/shop/models/shelf.dart',
        'lib/models/book.dart',
      ]);
    });

    test('a file glob names files, not directories', () {
      final Directory root = _project(
        'dartvel:\n  modelsDir: lib/**/*.model.dart\n',
        <String, String>{
          'lib/a/book.model.dart': _book,
          'lib/a/helpers.dart': '// not a model',
        },
      );
      addTearDown(() => root.deleteSync(recursive: true));
      expect(_relative(root, dvModelSourceFiles(root.path)), <String>['lib/a/book.model.dart']);
    });

    test('the place to write a new model is the first plain directory', () {
      final Directory root = _project(
        'dartvel:\n  modelsDir:\n    - lib/features/*/models\n    - lib/data\n',
        const <String, String>{},
      );
      addTearDown(() => root.deleteSync(recursive: true));
      expect(dvModelWriteDirectory(root.path), 'lib/data');
    });
  });

  test('the generator writes the models modelsDir names, from every place',
      () async {
    final Directory root = _project(
      'dartvel:\n  modelsDir:\n    - lib/data\n    - lib/features/*/models\n',
      <String, String>{
        'lib/data/book.dart': _book,
        'lib/features/shop/models/shelf.dart': _shelf,
      },
    );
    addTearDown(() => root.deleteSync(recursive: true));
    await ModelGenerator.generate(root: root.path, pkgName: 'models_dir_app');
    final String generated =
        File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart')).readAsStringSync();
    expect(generated, contains('class Book'));
    expect(generated, contains('class Shelf'));
  });
}
