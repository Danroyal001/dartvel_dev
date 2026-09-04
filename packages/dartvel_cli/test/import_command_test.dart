// What `dartvel import openapi` does to a directory.
//
// The mapping itself is covered by openapi_import_test.dart; these are the
// behaviours a developer notices at the prompt -- where files land, and what
// happens to the ones already there.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/import_command.dart';
import 'package:test/test.dart';

const String _document = '''
{
  "openapi": "3.0.0",
  "info": {"title": "Catalog", "version": "1.0.0"},
  "paths": {
    "/books/{id}": {
      "get": {
        "operationId": "getBook",
        "parameters": [
          {"name": "id", "in": "path", "required": true,
           "schema": {"type": "string"}}
        ],
        "responses": {"200": {"description": "a book"}}
      }
    }
  },
  "components": {
    "schemas": {
      "Book": {
        "type": "object",
        "required": ["id", "title"],
        "properties": {
          "id": {"type": "string"},
          "title": {"type": "string"}
        }
      }
    }
  }
}
''';

void main() {
  group('dartvel import openapi', () {
    late Directory project;
    late Directory previous;
    late CommandRunner<void> runner;
    late File spec;

    setUp(() {
      previous = Directory.current;
      project = Directory.systemTemp.createTempSync('dartvel_import_');
      Directory.current = project;
      spec = File('${project.path}/catalog.json')
        ..writeAsStringSync(_document);
      runner = CommandRunner<void>('dartvel', 'Test runner')
        ..addCommand(ImportCommand());
      exitCode = 0;
    });

    tearDown(() {
      Directory.current = previous;
      project.deleteSync(recursive: true);
      exitCode = 0;
    });

    test('writes the models and the calls under the project', () async {
      await runner.run(<String>['import', 'openapi', spec.path]);

      final File model = File('${project.path}/lib/models/book.dart');
      final File calls = File('${project.path}/lib/api/catalog.dart');
      expect(model.existsSync(), isTrue,
          reason: 'the schema should have become a model');
      expect(calls.existsSync(), isTrue,
          reason: 'the operation should have become a call');
      expect(model.readAsStringSync(), contains('class _Book'));
      expect(calls.readAsStringSync(), contains('getBook'));
      expect(exitCode, 0);
    });

    test('--dry-run writes nothing', () async {
      await runner.run(<String>['import', 'openapi', spec.path, '--dry-run']);

      expect(Directory('${project.path}/lib').existsSync(), isFalse,
          reason: 'a dry run that creates directories is not a dry run');
    });

    test('leaves a file that is already there alone', () async {
      final File model = File('${project.path}/lib/models/book.dart');
      model.parent.createSync(recursive: true);
      model.writeAsStringSync('// mine, edited by hand\n');

      await runner.run(<String>['import', 'openapi', spec.path]);

      expect(model.readAsStringSync(), '// mine, edited by hand\n',
          reason: 'an import that silently overwrites edits is run once');
      expect(File('${project.path}/lib/api/catalog.dart').existsSync(), isTrue,
          reason: 'the files that were not there should still be written');
    });

    test('--overwrite replaces it', () async {
      final File model = File('${project.path}/lib/models/book.dart');
      model.parent.createSync(recursive: true);
      model.writeAsStringSync('// mine, edited by hand\n');

      await runner
          .run(<String>['import', 'openapi', spec.path, '--overwrite']);

      expect(model.readAsStringSync(), contains('class _Book'));
    });

    test('a document that is not a spec fails, and writes nothing', () async {
      final File broken = File('${project.path}/broken.json')
        ..writeAsStringSync('not json at all');

      await runner.run(<String>['import', 'openapi', broken.path]);

      expect(exitCode, isNot(0), reason: 'the shell has to be able to tell');
      expect(Directory('${project.path}/lib').existsSync(), isFalse);
    });

    test('a file that is not there fails, and does not throw', () async {
      await runner.run(<String>['import', 'openapi', 'nowhere.json']);

      expect(exitCode, isNot(0));
    });
  });
}
