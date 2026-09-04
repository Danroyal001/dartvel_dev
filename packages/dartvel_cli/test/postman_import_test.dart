// A Postman collection, read into Dartvel source.
//
// An OpenAPI document is the tidy case. What people are actually handed, very
// often, is somebody's Postman collection -- the requests a team already
// makes, exported from the tool they make them in. Reading it is the same
// job as reading a spec and the same answer: ordinary files in the project,
// not a runtime dependency on the export.
//
// It is a thinner document than a spec: a collection describes requests and
// almost never describes types, so this produces calls and says plainly that
// the models are not in there to be had.
import 'package:dartvel_cli/src/import/postman_import.dart';
import 'package:test/test.dart';

const String _collection = '''
{
  "info": {
    "name": "Catalog API",
    "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  },
  "item": [
    {
      "name": "List books",
      "request": {
        "method": "GET",
        "url": {
          "raw": "{{baseUrl}}/books?limit=10",
          "host": ["{{baseUrl}}"],
          "path": ["books"],
          "query": [{"key": "limit", "value": "10"}]
        }
      }
    },
    {
      "name": "Books",
      "item": [
        {
          "name": "Get one book",
          "request": {
            "method": "GET",
            "url": {
              "raw": "{{baseUrl}}/books/:id",
              "host": ["{{baseUrl}}"],
              "path": ["books", ":id"]
            }
          }
        },
        {
          "name": "Create a book",
          "request": {
            "method": "POST",
            "url": {"raw": "{{baseUrl}}/books", "path": ["books"]},
            "body": {
              "mode": "raw",
              "raw": "{\\"title\\": \\"A book\\"}",
              "options": {"raw": {"language": "json"}}
            }
          }
        }
      ]
    }
  ]
}
''';

DVPostmanImport get _imported => dvImportPostman(_collection);

void main() {
  group('the calls', () {
    test('one function per request, including inside folders', () {
      final String source = _imported.sources['lib/api/catalog_api.dart']!;

      expect(source, contains('listBooks'));
      expect(source, contains('getOneBook'));
      expect(source, contains('createABook'));
    });

    test('a path variable becomes a parameter, not part of the string', () {
      final String source = _imported.sources['lib/api/catalog_api.dart']!;

      expect(source, contains('String id'));
      expect(source, contains(r"'/books/$id'"),
          reason: 'a :id left in the path is a request for a book called ":id"');
    });

    test('a query string becomes named arguments', () {
      final String source = _imported.sources['lib/api/catalog_api.dart']!;

      expect(source, contains('limit'));
    });

    test('the verb is the one the collection says', () {
      // The same shape the OpenAPI import writes. Two importers producing
      // two different kinds of client would be two things to learn.
      final String source = _imported.sources['lib/api/catalog_api.dart']!;

      expect(source, contains('DV.Http.post('));
      expect(source, contains('DV.Http.get('));
    });

    test('the environment variable in the host does not reach the path', () {
      // {{baseUrl}} is Postman's, and the generated client already knows
      // where the API is. Leaving it in produces a request to a literal
      // "{{baseUrl}}/books", which fails at run time and reads as a network
      // problem.
      final String source = _imported.sources['lib/api/catalog_api.dart']!;

      expect(source, isNot(contains('{{')));
    });
  });

  group('what it cannot read', () {
    test('a document that is not JSON says so', () {
      expect(() => dvImportPostman('not json'),
          throwsA(isA<FormatException>()));
    });

    test('a collection with no items is reported, not written empty', () {
      final DVPostmanImport imported = dvImportPostman(
        '{"info": {"name": "Empty"}, "item": []}',
      );

      expect(imported.sources, isEmpty);
      expect(imported.problems, isNotEmpty);
    });

    test('it says that a collection carries no models', () {
      // The honest limit, said once rather than discovered by looking for
      // lib/models and finding nothing.
      expect(_imported.problems.join(' ').toLowerCase(), contains('model'));
    });
  });
}
