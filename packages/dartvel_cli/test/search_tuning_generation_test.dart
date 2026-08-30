// Ranking is configured in pubspec.yaml, per the spec, so the generated search
// facade has to carry that configuration rather than leaving each application
// to repeat it at every call site.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _model = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(searchable: true)
class _User {
  @DVModel.searchableField()
  final String name;

  final String role;

  const _User({required this.name, required this.role});
}
''';

Future<String> generateWith(String pubspec) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_search_cfg_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'models', 'user.dart')).writeAsStringSync(_model);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(pubspec);

  await ModelGenerator.generate(
    root: root.path,
    pkgName: 'search_app',
    buildId: 'test-build',
  );

  return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
      .readAsStringSync();
}

void main() {
  test('with no configuration the facade carries the defaults', () async {
    final String generated = await generateWith('name: search_app\n');

    expect(generated, contains('static const DVSearchTuning tuning'));
    expect(generated, contains('typoTolerance: true'));
  });

  test('synonyms configured in pubspec reach the facade', () async {
    final String generated = await generateWith('''
name: search_app
dartvel:
  search:
    synonyms:
      admin: [administrator, superuser]
''');

    expect(generated, contains("'admin'"));
    expect(generated, contains("'administrator'"));
    expect(generated, contains("'superuser'"));
  });

  test('typo tolerance can be turned off in pubspec', () async {
    final String generated = await generateWith('''
name: search_app
dartvel:
  search:
    typoTolerance: false
''');

    expect(generated, contains('typoTolerance: false'));
  });

  test('highlight markers are configurable', () async {
    final String generated = await generateWith('''
name: search_app
dartvel:
  search:
    highlightPre: "<b>"
    highlightPost: "</b>"
''');

    expect(generated, contains(r"highlightPre: '<b>'"));
    expect(generated, contains(r"highlightPost: '</b>'"));
  });

  test('a quote in a configured value cannot break out of the literal',
      () async {
    // pubspec is project input. An unescaped value would produce a generated
    // file that does not compile, far from the line that caused it.
    final String generated = await generateWith('''
name: search_app
dartvel:
  search:
    highlightPre: "it's"
''');

    expect(generated, contains(r"highlightPre: 'it\'s'"));
  });
}
