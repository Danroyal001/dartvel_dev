// The generated backend asks a policy about the model it was written for.
//
// A server-side policy is written against dartvel_core, with its own class
// for the resource -- the generated model reaches Flutter, and the server
// cannot load it. The replay route handed that policy a map, which it does
// not accept, so every replayed write was refused. The backend now builds
// the policy's own class from the record's values, by the constructor the
// application wrote, and passes that.
import 'dart:io';

import 'package:dartvel_cli/src/generators/policy_classes.dart';
import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _policy = '''
import 'package:dartvel_core/dartvel.dart';

class Note {
  const Note({
    required this.id,
    required this.ownerId,
    this.pinned = false,
    this.count,
  });

  final String id;
  final String ownerId;
  final bool pinned;
  final int? count;
}

@DVPolicy(Note)
class NotePolicy {
  bool create(DVSessionPrincipal? user, Note? note) =>
      user != null && note?.ownerId == user.userId;
}
''';

void main() {
  group('reading the class a policy takes', () {
    test('named parameters that initialise fields', () {
      final DVResourceShape? shape = dvResourceShapeIn(_policy, 'Note');

      expect(shape, isNotNull);
      expect(
        shape!.parameters.map((DVResourceParameter p) => '${p.name}:${p.type}'),
        <String>['id:String', 'ownerId:String', 'pinned:bool', 'count:int?'],
      );
      expect(shape.parameters.every((DVResourceParameter p) => p.named),
          isTrue);
    });

    test('positional parameters too', () {
      final DVResourceShape? shape = dvResourceShapeIn('''
class Note {
  Note(this.id, this.total);
  final String id;
  final double total;
}
''', 'Note');

      expect(shape!.parameters.map((DVResourceParameter p) => p.named),
          <bool>[false, false]);
    });

    test('a constructor that takes something that is not a field is not '
        'guessed at', () {
      // Whatever it does with the argument is the application's code, and
      // building one from a record's values would be inventing an argument.
      expect(
        dvResourceShapeIn('''
class Note {
  Note(String raw) : id = raw.trim();
  final String id;
}
''', 'Note'),
        isNull,
      );
    });

    test('a class that is not there has no shape', () {
      expect(dvResourceShapeIn(_policy, 'Ledger'), isNull);
    });
  });

  group('a generated backend', () {
    late Directory dir;

    setUpAll(() async {
      dir = Directory.systemTemp.createTempSync('dv_offline_policy_');
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: offline_policy_probe
publish_to: none
environment:
  sdk: ^3.9.0
dartvel:
  prodBackendHost: https://example.com
''');
      final File page =
          File(p.join(dir.path, 'lib', 'pages', 'index.page.dart'));
      page.parent.createSync(recursive: true);
      page.writeAsStringSync('''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
Widget _indexPage(BuildContext context) => const DVText('Home');
''');
      final File model = File(p.join(dir.path, 'lib', 'models', 'note.dart'));
      model.parent.createSync(recursive: true);
      model.writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(offline: DVConflict.lastWriteWins)
class _Note {
  final String id;
  final String ownerId;

  const _Note({required this.id, required this.ownerId});
}
''');
      final File policy =
          File(p.join(dir.path, 'lib', 'policies', 'note_policy.dart'));
      policy.parent.createSync(recursive: true);
      policy.writeAsStringSync(_policy);
      await routes.generate(root_: dir.path);
    });

    tearDownAll(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('builds the policy\'s class from a record\'s values', () {
      final String policies = File(p.join(
              dir.path, 'lib', 'dartvel_client', 'backend_policies.g.dart'))
          .readAsStringSync();

      expect(policies, contains('dartvelOfflineResources'));
      expect(policies, contains("'Note': (Map<String, Object?> values) =>"));
      expect(policies, contains(".Note("));
      expect(policies, contains("id: _dvString(values['id'])"));
      expect(policies,
          contains("count: values['count'] == null ? null : _dvInt(values['count'])"));
      expect(policies, contains("pinned: _dvBool(values['pinned'])"));
    });

    test('and hands the builders to the replay route', () {
      final String backend = File(
              p.join(dir.path, '.dart_tool', 'dartvel_backend_routes.g.dart'))
          .readAsStringSync();

      expect(backend, contains('resources: dartvelOfflineResources'));
    });
  });
}
