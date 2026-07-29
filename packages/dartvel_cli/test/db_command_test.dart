import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/db_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('DbCommand', () {
    late Directory previous;
    late Directory root;

    setUp(() {
      previous = Directory.current;
      root = Directory.systemTemp.createTempSync('dartvel_db_command_');
      Directory.current = root;
      exitCode = 0;
    });

    tearDown(() {
      Directory.current = previous;
      root.deleteSync(recursive: true);
      exitCode = 0;
    });

    test('migrate writes a deterministic local schema snapshot', () async {
      _writeModel(root, 'user.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
@pragma('vm:entry-point')
class _User {
  final String id;
  const _User(this.id);
}
''');

      await _runDb(<String>['db', 'migrate']);

      final snapshot = localSchemaSnapshotFile(root.path);
      expect(snapshot.existsSync(), isTrue);
      final decoded = jsonDecode(snapshot.readAsStringSync());
      expect(decoded, isA<Map<String, Object?>>());
      final json = decoded as Map<String, Object?>;
      expect(json['version'], 1);
      expect(json['tables'], [
        <String, Object?>{
          'name': 'users',
          'model': 'User',
          'source': 'lib/models/user.dart',
        }
      ]);
    });

    test('schema discovery rejects public annotated model inputs', () {
      _writeModel(root, 'user.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class User {}
''');

      expect(
        () => discoverLocalSchema(root.path),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('model generation inputs must be private'),
          ),
        ),
      );
    });

    test('push requires a local migrated schema snapshot', () async {
      await _runDb(<String>['db', 'push']);

      expect(exitCode, 1);
      expect(remoteSchemaSnapshotFile(root.path).existsSync(), isFalse);
    });

    test('push and pull copy concrete schema snapshots', () async {
      _writeModel(root, 'account.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
@pragma('vm:entry-point')
class _Account {}
''');

      await _runDb(<String>['db', 'migrate']);
      await _runDb(<String>['db', 'push']);
      expect(exitCode, 0);
      expect(remoteSchemaSnapshotFile(root.path).existsSync(), isTrue);

      localSchemaSnapshotFile(root.path).deleteSync();
      await _runDb(<String>['db', 'pull']);
      expect(exitCode, 0);
      expect(pulledSchemaSnapshotFile(root.path).existsSync(), isTrue);
      expect(
        pulledSchemaSnapshotFile(root.path).readAsStringSync(),
        remoteSchemaSnapshotFile(root.path).readAsStringSync(),
      );
    });

    test('seed reports missing seed files instead of succeeding', () async {
      await _runDb(<String>['db', 'seed']);

      expect(exitCode, 1);
    });

    test('seed discovery finds supported seed file locations', () {
      File(p.join(root.path, 'tool', 'seed.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}');
      File(p.join(root.path, 'lib', 'seeds', 'users.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}');

      expect(
        discoverSeedFiles(root.path)
            .map((file) => p.relative(file.path, from: root.path))
            .toList(),
        <String>['lib/seeds/users.dart', 'tool/seed.dart'],
      );
    });
  });
}

Future<void> _runDb(List<String> args) {
  return (CommandRunner<void>('dartvel', 'test')..addCommand(DbCommand()))
      .run(args);
}

void _writeModel(Directory root, String name, String source) {
  final file = File(p.join(root.path, 'lib', 'models', name));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(source);
}
