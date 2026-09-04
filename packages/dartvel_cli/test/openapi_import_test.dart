// An API description becoming Dartvel models and a typed client.
//
// Dartvel already writes an OpenAPI document out of an application. Reading
// one in is the other direction and the one people actually start from: an
// API exists, somebody hands you its spec, and the work is transcribing it
// into models and calls by hand.
//
// What matters is that the result is ordinary Dartvel source -- private
// @DVModel inputs and a function per operation -- so the import is a
// starting point rather than a dependency. And that a spec Dartvel cannot
// read says which part it could not, because "import failed" against a
// four-thousand-line document is not something anybody can act on.
import 'package:dartvel_cli/src/import/openapi_import.dart';
import 'package:test/test.dart';

const String _spec = '''
{
  "openapi": "3.0.0",
  "info": {"title": "Shop", "version": "1.0.0"},
  "paths": {
    "/products": {
      "get": {
        "operationId": "listProducts",
        "responses": {
          "200": {
            "description": "ok",
            "content": {
              "application/json": {
                "schema": {"type": "array", "items": {"\$ref": "#/components/schemas/Product"}}
              }
            }
          }
        }
      }
    },
    "/products/{id}": {
      "get": {
        "operationId": "getProduct",
        "parameters": [
          {"name": "id", "in": "path", "required": true, "schema": {"type": "string"}}
        ],
        "responses": {
          "200": {
            "description": "ok",
            "content": {
              "application/json": {"schema": {"\$ref": "#/components/schemas/Product"}}
            }
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "Product": {
        "type": "object",
        "required": ["id", "title", "price"],
        "properties": {
          "id": {"type": "string"},
          "title": {"type": "string"},
          "price": {"type": "number"},
          "inStock": {"type": "boolean"},
          "releasedAt": {"type": "string", "format": "date-time"},
          "tags": {"type": "array", "items": {"type": "string"}}
        }
      }
    }
  }
}
''';

void main() {
  group('the models', () {
    late DVOpenApiImport import;
    setUpAll(() => import = dvImportOpenApi(_spec));

    test('a schema becomes a private @DVModel input', () {
      // Private, because every Dartvel generation input is: application code
      // refers to the generated public name, and a public input is a hard
      // error the generator already gives.
      final String source = import.sources['lib/models/product.dart']!;

      expect(source, contains('@DVModel()'));
      expect(source, contains('class _Product'));
    });

    test('its fields keep their types', () {
      final String source = import.sources['lib/models/product.dart']!;

      expect(source, contains('final String id;'));
      expect(source, contains('final double price;'));
      // Nullable, because the spec's `required` names id, title and price
      // and nothing else -- which is the rule the next test is about.
      expect(source, contains('final DateTime? releasedAt;'));
      expect(source, contains('final List<String>? tags;'));
    });

    test('what the spec does not require is nullable', () {
      // A field the API may omit and the model insists on is a parse that
      // throws on the first response that leaves it out.
      final String source = import.sources['lib/models/product.dart']!;

      expect(source, contains('final bool? inStock;'));
    });

    test('a name that is not a Dart name is made one', () {
      final DVOpenApiImport odd = dvImportOpenApi('''
{
  "openapi": "3.0.0",
  "info": {"title": "x", "version": "1"},
  "paths": {},
  "components": {"schemas": {"order-line": {"type": "object",
    "properties": {"line-total": {"type": "number"}}}}}
}
''');

      expect(odd.sources['lib/models/order_line.dart'], contains('class _OrderLine'));
      expect(odd.sources['lib/models/order_line.dart'], contains('lineTotal'));
    });
  });

  group('the calls', () {
    late DVOpenApiImport import;
    setUpAll(() => import = dvImportOpenApi(_spec));

    test('an operation becomes a function named after it', () {
      final String source = import.sources['lib/api/shop.dart']!;

      expect(source, contains('listProducts('));
      expect(source, contains('getProduct('));
    });

    test('a path parameter is an argument, and reaches the path', () {
      // The failure this prevents is a generated call that asks for an id
      // and requests /products/{id} literally.
      final String source = import.sources['lib/api/shop.dart']!;

      expect(source, contains('String id'));
      expect(source, contains(r"'/products/$id'"));
    });

    test('the return type is the schema, not a Map', () {
      final String source = import.sources['lib/api/shop.dart']!;

      expect(source, contains('Future<List<Product>> listProducts'));
      expect(source, contains('Future<Product> getProduct'));
    });
  });

  group('what it cannot read', () {
    test('a document that is not JSON says so, not "import failed"', () {
      expect(() => dvImportOpenApi('not json'), throwsA(isA<FormatException>()));
    });

    test('a schema it cannot map is reported and skipped, not guessed', () {
      // A field of an unknown shape typed as dynamic would compile and lose
      // the error where nobody looks for it.
      final DVOpenApiImport import = dvImportOpenApi('''
{
  "openapi": "3.0.0",
  "info": {"title": "x", "version": "1"},
  "paths": {},
  "components": {"schemas": {"Thing": {"type": "object",
    "properties": {"weird": {"\$ref": "#/components/schemas/Missing"}}}}}
}
''');

      expect(import.problems.join(' '), contains('Missing'));
      expect(import.problems.join(' '), contains('weird'));
    });

    test('an operation with no id is named for its method and path', () {
      // Skipping it would drop an endpoint silently, and operationId is
      // optional in the specification.
      final DVOpenApiImport import = dvImportOpenApi('''
{
  "openapi": "3.0.0",
  "info": {"title": "x", "version": "1"},
  "paths": {"/health": {"get": {"responses": {"200": {"description": "ok"}}}}}
}
''');

      expect(import.sources['lib/api/x.dart'], contains('getHealth('));
    });
  });
}
