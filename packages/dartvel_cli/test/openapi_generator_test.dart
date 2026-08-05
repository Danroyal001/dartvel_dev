import 'dart:convert';

import 'package:dartvel_cli/src/generators/openapi_generator.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> build(List<OpenApiOperation> ops) =>
      buildOpenApiDocument(
        title: 'app',
        version: '1.2.3',
        apiBasePath: '/api',
        operations: ops,
      );

  test('a POST function becomes a form-data operation', () {
    final doc = build(const <OpenApiOperation>[
      OpenApiOperation(
        method: 'post',
        path: '/orders',
        name: 'createOrder',
        parameterNames: <String>['sku', 'quantity'],
        parameterTypes: <String>['String', 'int'],
        returnType: 'Future<Order>',
      ),
    ]);

    final op = ((doc['paths']! as Map)['/orders'] as Map)['post'] as Map;
    expect(op['operationId'], 'createOrder');

    // Dartvel transmits backend data as form-data, per the spec's transport
    // rules — a JSON request body would document the wrong protocol.
    final body = op['requestBody'] as Map;
    final schema =
        ((body['content'] as Map)['multipart/form-data'] as Map)['schema']
            as Map;
    expect(
      schema['properties'],
      <String, Object?>{
        'sku': <String, Object?>{'type': 'string'},
        'quantity': <String, Object?>{'type': 'integer'},
      },
    );
    expect(schema['required'], <String>['sku', 'quantity']);

    final response =
        (((op['responses'] as Map)['200'] as Map)['content'] as Map);
    expect(
      (response['application/json'] as Map)['schema'],
      <String, Object?>{'type': 'object', 'x-dart-type': 'Order'},
    );
  });

  test('bracket path params become path parameters in brace form', () {
    final doc = build(const <OpenApiOperation>[
      OpenApiOperation(
        method: 'get',
        path: '/users/[id]',
        name: 'getUser',
        parameterNames: <String>['id'],
        parameterTypes: <String>['String'],
        returnType: 'Future<User>',
      ),
    ]);

    final paths = doc['paths']! as Map;
    expect(paths.keys, contains('/users/{id}'));
    final op = (paths['/users/{id}'] as Map)['get'] as Map;
    final params = op['parameters'] as List;
    expect(params, hasLength(1));
    expect((params.single as Map)['in'], 'path');
    expect((params.single as Map)['required'], isTrue);
  });

  test('GET arguments that are not path params go to the query string', () {
    final doc = build(const <OpenApiOperation>[
      OpenApiOperation(
        method: 'get',
        path: '/search',
        name: 'search',
        parameterNames: <String>['q', 'limit'],
        parameterTypes: <String>['String', 'int?'],
        returnType: 'Future<List<String>>',
      ),
    ]);

    final op = ((doc['paths']! as Map)['/search'] as Map)['get'] as Map;
    final params = (op['parameters'] as List).cast<Map>();
    expect(params.map((Map p) => p['in']), everyElement('query'));
    // A nullable parameter is optional; a non-nullable one is required.
    expect(
      params.singleWhere((Map p) => p['name'] == 'q')['required'],
      isTrue,
    );
    expect(
      params.singleWhere((Map p) => p['name'] == 'limit')['required'],
      isFalse,
    );
  });

  test('a Stream return documents server-sent events', () {
    final doc = build(const <OpenApiOperation>[
      OpenApiOperation(
        method: 'get',
        path: '/messages',
        name: 'messages',
        parameterNames: <String>[],
        parameterTypes: <String>[],
        returnType: 'Stream<Message>',
      ),
    ]);

    final response =
        (((((doc['paths']! as Map)['/messages'] as Map)['get'] as Map)['responses']
            as Map)['200'] as Map);
    expect(response['description'], contains('Server-sent event'));
    expect((response['content'] as Map).keys, contains('text/event-stream'));
  });

  test('scalar, list and date types map to their OpenAPI schemas', () {
    final doc = build(const <OpenApiOperation>[
      OpenApiOperation(
        method: 'post',
        path: '/report',
        name: 'report',
        parameterNames: <String>['when', 'tags', 'ratio'],
        parameterTypes: <String>['DateTime', 'List<String>', 'double'],
        returnType: 'Future<void>',
      ),
    ]);

    final schema = (((((doc['paths']! as Map)['/report'] as Map)['post']
                as Map)['requestBody'] as Map)['content']
            as Map)['multipart/form-data'] as Map;
    final properties = (schema['schema'] as Map)['properties'] as Map;
    expect(
      properties['when'],
      <String, Object?>{'type': 'string', 'format': 'date-time'},
    );
    expect(
      properties['tags'],
      <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
      },
    );
    expect(properties['ratio'], <String, Object?>{'type': 'number'});
  });

  test('the document is well-formed JSON with the fixed envelope', () {
    final doc = build(const <OpenApiOperation>[]);
    final decoded =
        jsonDecode(encodeOpenApiDocument(doc)) as Map<String, Object?>;

    expect(decoded['openapi'], '3.1.0');
    expect((decoded['info']! as Map)['version'], '1.2.3');
    expect((decoded['servers']! as List).single, {'url': '/api'});
  });
}
