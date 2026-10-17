import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The generated library keeps the enums a model file declares, so a model
/// field typed with one compiles on the server without importing the input.
/// A file under lib/models that declares no model is the application's own
/// code: copying its enums made a second type of the same name, and every
/// file importing both the barrel and that file stopped compiling.
void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_model_enums_');
    Directory(p.join(root.path, 'lib/models')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib/dartvel_client'))
        .createSync(recursive: true);
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: enum_probe
environment:
  sdk: ^3.13.0
''');
    File(p.join(root.path, 'lib/models/player.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
enum Mood { calm, happy }
@DVModel()
class _Player({required final String id, final Mood mood = .happy});
''');
    File(p.join(root.path, 'lib/models/events.dart')).writeAsStringSync('''
enum EventType { outage, festival }
class GameEvent({required final EventType type});
''');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('enums come only from files that declare a model', () async {
    await ModelGenerator.generate(root: root.path, pkgName: 'enum_probe');
    final String models = File(
      p.join(root.path, 'lib/dartvel_client/models.g.dart'),
    ).readAsStringSync();
    expect(models, contains('enum Mood'));
    expect(models, isNot(contains('enum EventType')));
  });
}
