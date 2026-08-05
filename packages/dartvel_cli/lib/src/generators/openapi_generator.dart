import 'dart:convert';

/// One backend function, as the backend generator discovered it.
class OpenApiOperation {
  final String method;

  /// The URL path in bracket form, e.g. `/users/[id]`.
  final String path;

  /// The public function name, used as the operationId.
  final String name;

  /// Parameter names, in declaration order.
  final List<String> parameterNames;

  /// Parameter Dart types, matching [parameterNames].
  final List<String> parameterTypes;

  /// The Dart return type, `Future<...>`/`Stream<...>` included.
  final String returnType;

  const OpenApiOperation({
    required this.method,
    required this.path,
    required this.name,
    required this.parameterNames,
    required this.parameterTypes,
    required this.returnType,
  });
}

/// Builds an OpenAPI 3.1 document for the discovered backend functions.
///
/// The spec promises generated OpenAPI with no manual configs, so everything
/// here derives from what the functions already declare: names, parameter
/// types, return types, and the transport rules Dartvel fixes (form-data
/// bodies, SSE for streams).
Map<String, Object?> buildOpenApiDocument({
  required String title,
  required String version,
  required String apiBasePath,
  required List<OpenApiOperation> operations,
}) {
  final paths = <String, Map<String, Object?>>{};

  for (final op in operations) {
    final pathParams = _bracketParams(op.path);
    final openApiPath = _toOpenApiPath(op.path);
    final method = op.method.toLowerCase();

    final bodyParams = <(String, String)>[];
    final queryOrPathParams = <Map<String, Object?>>[];

    for (var i = 0; i < op.parameterNames.length; i++) {
      final name = op.parameterNames[i];
      final type =
          i < op.parameterTypes.length ? op.parameterTypes[i] : 'String';
      if (pathParams.contains(name)) {
        queryOrPathParams.add(<String, Object?>{
          'name': name,
          'in': 'path',
          'required': true,
          'schema': _schemaFor(type),
        });
      } else if (method == 'get' || method == 'head' || method == 'delete') {
        // Bodyless methods carry arguments in the query string.
        queryOrPathParams.add(<String, Object?>{
          'name': name,
          'in': 'query',
          'required': !type.endsWith('?'),
          'schema': _schemaFor(type),
        });
      } else {
        bodyParams.add((name, type));
      }
    }

    // Path params that are not typed function parameters still exist in the
    // URL and must be declared, or the document is invalid.
    for (final param in pathParams) {
      if (!op.parameterNames.contains(param)) {
        queryOrPathParams.add(<String, Object?>{
          'name': param,
          'in': 'path',
          'required': true,
          'schema': const <String, Object?>{'type': 'string'},
        });
      }
    }

    final isStream = op.returnType.startsWith('Stream<');
    final operation = <String, Object?>{
      'operationId': op.name.isEmpty ? _fallbackId(method, op.path) : op.name,
      if (queryOrPathParams.isNotEmpty) 'parameters': queryOrPathParams,
      if (bodyParams.isNotEmpty)
        'requestBody': <String, Object?>{
          'required': true,
          // Dartvel transmits backend data as form-data, per the spec's
          // transport rules — not JSON.
          'content': <String, Object?>{
            'multipart/form-data': <String, Object?>{
              'schema': <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  for (final (name, type) in bodyParams)
                    name: _schemaFor(type),
                },
                'required': <String>[
                  for (final (name, type) in bodyParams)
                    if (!type.endsWith('?')) name,
                ],
              },
            },
          },
        },
      'responses': <String, Object?>{
        '200': <String, Object?>{
          'description': isStream
              ? 'Server-sent event stream of ${_unwrap(op.returnType)}'
              : 'Successful response',
          'content': <String, Object?>{
            if (isStream)
              'text/event-stream': <String, Object?>{
                'schema': _schemaFor(_unwrap(op.returnType)),
              }
            else
              'application/json': <String, Object?>{
                'schema': _schemaFor(_unwrap(op.returnType)),
              },
          },
        },
      },
    };

    (paths[openApiPath] ??= <String, Object?>{})[method] = operation;
  }

  return <String, Object?>{
    'openapi': '3.1.0',
    'info': <String, Object?>{'title': title, 'version': version},
    'servers': <Object?>[
      <String, Object?>{'url': apiBasePath},
    ],
    'paths': paths,
  };
}

/// The document as pretty JSON, for writing to disk and serving.
String encodeOpenApiDocument(Map<String, Object?> document) =>
    '${const JsonEncoder.withIndent('  ').convert(document)}\n';

/// Parameter segments in a route path. Both spellings occur: `[id]` in file
/// names and `<id>` (optionally `<name|regex>`) in the resolved routes.
final _paramSegment = RegExp(r'[\[<]([A-Za-z0-9_]+)(?:\|[^\]>]*)?[\]>]');

Set<String> _bracketParams(String path) =>
    _paramSegment.allMatches(path).map((Match m) => m.group(1)!).toSet();

/// `/users/[id]` or `/users/<id>` → `/users/{id}`, the OpenAPI form.
String _toOpenApiPath(String path) =>
    path.replaceAllMapped(_paramSegment, (Match m) => '{${m.group(1)}}');

String _fallbackId(String method, String path) {
  final cleaned = path.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  return '$method$cleaned';
}

/// Unwraps `Future<T>`/`Stream<T>` to `T`.
String _unwrap(String type) {
  final match = RegExp(r'^(?:Future|Stream)<(.+)>$').firstMatch(type.trim());
  return match?.group(1) ?? type.trim();
}

/// Maps a Dart type to an OpenAPI schema.
///
/// Model types cannot be expanded here — the backend generator sees only the
/// function signature — so they become objects carrying the Dart type name,
/// which is still enough for a client generator to key on.
Map<String, Object?> _schemaFor(String dartType) {
  var type = dartType.trim();
  final nullable = type.endsWith('?');
  if (nullable) type = type.substring(0, type.length - 1).trim();
  type = _unwrap(type);

  Map<String, Object?> base;
  final listMatch = RegExp(r'^List<(.+)>$').firstMatch(type);
  final mapMatch = RegExp(r'^Map<.+>$').firstMatch(type);
  if (listMatch != null) {
    base = <String, Object?>{
      'type': 'array',
      'items': _schemaFor(listMatch.group(1)!),
    };
  } else if (mapMatch != null) {
    base = const <String, Object?>{'type': 'object'};
  } else {
    base = switch (type) {
      'String' => const <String, Object?>{'type': 'string'},
      'int' => const <String, Object?>{'type': 'integer'},
      'double' ||
      'num' =>
        const <String, Object?>{'type': 'number'},
      'bool' => const <String, Object?>{'type': 'boolean'},
      'DateTime' =>
        const <String, Object?>{'type': 'string', 'format': 'date-time'},
      'void' || 'Null' || '' || 'dynamic' || 'Object' || 'Object?' =>
        const <String, Object?>{},
      _ => <String, Object?>{
          'type': 'object',
          'x-dart-type': type,
        },
    };
  }

  if (nullable && base.isNotEmpty) {
    return <String, Object?>{...base, 'nullable': true};
  }
  return base;
}
