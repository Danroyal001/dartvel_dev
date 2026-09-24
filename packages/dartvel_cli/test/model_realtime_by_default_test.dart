// A model is realtime because it is a model, not because something called
// sync on it.
//
// The generated model carried an instance `sync()` that saved and then
// published a second change of its own kind. Saving already publishes, so
// the method was a second way to do one thing, and its existence said that
// syncing is something an application triggers. It is not: a model opted
// into it is read and written like any other, saving publishes the change,
// and watching receives it.
//
// This reads the generated class rather than the generator, because what
// matters is the surface an application can reach.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _model = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(offline: DVConflict.lastWriteWins, softDelete: true)
class _Article {
  final String slug;
  final String title;
  final bool published;

  const _Article({
    required this.slug,
    required this.title,
    required this.published,
  });
}
''';

const String _pubspec = '''
name: realtime_app
environment:
  sdk: ^3.12.0
''';

Future<String> generated() async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_realtime_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(_pubspec);
  File(p.join(root.path, 'lib', 'models', 'article.dart'))
      .writeAsStringSync(_model);

  await ModelGenerator.generate(
    root: root.path,
    pkgName: 'realtime_app',
    buildId: 'test-build',
  );

  return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
      .readAsStringSync();
}

void main() {
  test('nothing on a model is called sync', () async {
    final String source = await generated();
    // The generated file is one library, so any `sync(` in it is reachable.
    expect(source, isNot(contains('sync()')),
        reason: 'a model that has to be told to sync is not realtime');
    expect(source, isNot(contains('DVModelChangeKind.synced')),
        reason: 'the kind existed to be what sync() published');
  });

  test('saving is what publishes, and it is still there', () async {
    // The point is not that the surface got smaller. It is that the one
    // call that was doing the work still does it.
    final String source = await generated();
    expect(source, contains('Future<Article> save('));
    expect(source, contains('Future<void> destroy()'));
  });
}
