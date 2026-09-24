// An OpenAPI document becomes a Dartvel module, and the module is pure Dart.
//
// This is the cheapest boundary in Module Sources and the one that proves the
// pipeline: there is no foreign runtime, no artifact and no binding, so what
// comes out is a Dart package the parent mounts like any other module, whose
// calls go over DV.Http against a host the module declares.
//
// The failures worth testing are the quiet ones. A document that describes a
// call the generator cannot express should refuse rather than emit a method
// that compiles and sends the wrong request; an operation without an
// operationId still needs a name, and two of them must not collide; and a
// path parameter interpolated without encoding is how a value with a slash in
// it reaches a different endpoint entirely.
import 'dart:io';

import 'package:dartvel_cli/src/modules/openapi_module.dart';
import 'package:dartvel_core/dartvel.dart' show DVHttp, DVHttpHostConfig;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:test/test.dart';

Map<String, Object?> _document({
  Map<String, Object?>? paths,
  Map<String, Object?>? schemas,
  List<Object?>? servers,
}) =>
    <String, Object?>{
      'openapi': '3.0.3',
      'info': <String, Object?>{'title': 'Vendor ERP', 'version': '1.0.0'},
      'servers': servers ?? <Object?>[
        <String, Object?>{'url': 'https://api.vendor.com'},
      ],
      'paths': paths ?? <String, Object?>{},
      if (schemas != null)
        'components': <String, Object?>{'schemas': schemas},
    };

DVGeneratedModule _generate(Map<String, Object?> document) =>
    dvGenerateDescribedApiModule(document: document, moduleId: 'vendorErp');

String _library(DVGeneratedModule module) =>
    module.files['lib/${module.packageName}.dart']!;

void main() {
  group('the package it writes', () {
    final DVGeneratedModule module = _generate(_document());

    test('is named for the module id, in the spelling Dart wants', () {
      expect(module.id, 'vendorErp');
      expect(module.packageName, 'vendor_erp');
      expect(module.files.keys, contains('pubspec.yaml'));
      expect(module.files.keys, contains('lib/vendor_erp.dart'));
    });

    test('declares itself a module, so the parent can mount it', () {
      expect(module.files['pubspec.yaml'], contains('name: vendor_erp'));
      expect(module.files['pubspec.yaml'], contains('  module:\n    id: vendorErp'));
    });

    test("declares the document's server as the host, under dartvel.http", () {
      // Not a base URL written into the generated calls. Declared, so the
      // retries, timeouts, circuit breaking and secret resolution are the
      // ones the specification already defines rather than a second set.
      expect(
        module.files['pubspec.yaml'],
        contains('    hosts:\n      vendorErp:\n'
            '        baseUrl: "https://api.vendor.com"'),
      );
      expect(_library(module), isNot(contains('https://api.vendor.com')));
    });

    test('declares a host the framework accepts', () {
      // Read by the same reader the application startup uses, so the
      // generated block cannot be a shape only this generator believes in:
      // a key DVHttp does not understand is an ArgumentError naming it.
      final Object? pubspec = loadYaml(module.files['pubspec.yaml']!);
      final Map<String, DVHttpHostConfig> hosts = DVHttp.readConfig(
        ((pubspec! as Map)['dartvel']! as Map)['http']! as Map,
      );

      expect(hosts.keys, <String>['vendorErp']);
      expect(hosts['vendorErp']!.baseUrl, 'https://api.vendor.com');
    });

    test('says it was generated and from what', () {
      expect(_library(module), contains('GENERATED CODE'));
      expect(_library(module), contains('OpenAPI'));
    });
  });

  group('an operation', () {
    test('becomes a method named for its operationId', () {
      final DVGeneratedModule module = _generate(_document(paths: <String, Object?>{
        '/orders/{id}': <String, Object?>{
          'get': <String, Object?>{
            'operationId': 'getOrder',
            'parameters': <Object?>[
              <String, Object?>{
                'name': 'id',
                'in': 'path',
                'required': true,
                'schema': <String, Object?>{'type': 'string'},
              },
            ],
            'responses': <String, Object?>{'200': <String, Object?>{}},
          },
        },
      }));

      expect(_library(module), contains('Future<void> getOrder({required String id})'));
    });

    test('encodes a path parameter rather than interpolating it', () {
      // A value with a slash in it is a different endpoint. This is the
      // failure that produces a plausible result: the call succeeds, against
      // something else.
      final DVGeneratedModule module = _generate(_document(paths: <String, Object?>{
        '/orders/{id}': <String, Object?>{
          'get': <String, Object?>{
            'operationId': 'getOrder',
            'parameters': <Object?>[
              <String, Object?>{
                'name': 'id',
                'in': 'path',
                'required': true,
                'schema': <String, Object?>{'type': 'string'},
              },
            ],
            'responses': <String, Object?>{'200': <String, Object?>{}},
          },
        },
      }));

      expect(_library(module), contains(r'Uri.encodeComponent(id)'));
      expect(_library(module), isNot(contains(r"'/orders/$id'")));
    });

    test('with no operationId is named for its method and path', () {
      final DVGeneratedModule module = _generate(_document(paths: <String, Object?>{
        '/orders/{id}/lines': <String, Object?>{
          'get': <String, Object?>{
            'parameters': <Object?>[
              <String, Object?>{
                'name': 'id',
                'in': 'path',
                'required': true,
                'schema': <String, Object?>{'type': 'string'},
              },
            ],
            'responses': <String, Object?>{'200': <String, Object?>{}},
          },
        },
      }));

      expect(_library(module), contains('getOrdersLines('));
    });

    test('takes an optional query parameter as an optional argument', () {
      final DVGeneratedModule module = _generate(_document(paths: <String, Object?>{
        '/orders': <String, Object?>{
          'get': <String, Object?>{
            'operationId': 'listOrders',
            'parameters': <Object?>[
              <String, Object?>{
                'name': 'limit',
                'in': 'query',
                'schema': <String, Object?>{'type': 'integer'},
              },
            ],
            'responses': <String, Object?>{'200': <String, Object?>{}},
          },
        },
      }));

      final String source = _library(module);
      expect(source, contains('Future<void> listOrders({int? limit})'));
      // Left off the request when it was not given, rather than sent empty.
      expect(source, contains("if (limit != null) 'limit': '\$limit'"));
    });

    test('sends its request body as JSON', () {
      final DVGeneratedModule module = _generate(_document(
        paths: <String, Object?>{
          '/orders': <String, Object?>{
            'post': <String, Object?>{
              'operationId': 'createOrder',
              'requestBody': <String, Object?>{
                'required': true,
                'content': <String, Object?>{
                  'application/json': <String, Object?>{
                    'schema': <String, Object?>{
                      r'$ref': '#/components/schemas/Order',
                    },
                  },
                },
              },
              'responses': <String, Object?>{
                '201': <String, Object?>{
                  'content': <String, Object?>{
                    'application/json': <String, Object?>{
                      'schema': <String, Object?>{
                        r'$ref': '#/components/schemas/Order',
                      },
                    },
                  },
                },
              },
            },
          },
        },
        schemas: <String, Object?>{
          'Order': <String, Object?>{
            'type': 'object',
            'required': <Object?>['id'],
            'properties': <String, Object?>{
              'id': <String, Object?>{'type': 'string'},
              'total': <String, Object?>{'type': 'number'},
            },
          },
        },
      ));

      final String source = _library(module);
      expect(source, contains('Future<Order> createOrder({required Order body})'));
      expect(source, contains('json: body.toJson()'));
    });
  });

  group('a schema', () {
    final DVGeneratedModule module = _generate(_document(
      paths: <String, Object?>{},
      schemas: <String, Object?>{
        'Order': <String, Object?>{
          'type': 'object',
          'required': <Object?>['id', 'lines'],
          'properties': <String, Object?>{
            'id': <String, Object?>{'type': 'string'},
            'total': <String, Object?>{'type': 'number'},
            'paid': <String, Object?>{'type': 'boolean'},
            'lines': <String, Object?>{
              'type': 'array',
              'items': <String, Object?>{r'$ref': '#/components/schemas/Line'},
            },
          },
        },
        'Line': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'sku': <String, Object?>{'type': 'string'},
          },
        },
      },
    ));

    test('becomes a class with its required fields non-null', () {
      final String source = _library(module);
      expect(source, contains('class Order {'));
      expect(source, contains('final String id;'));
      expect(source, contains('final double? total;'));
      expect(source, contains('final bool? paid;'));
      expect(source, contains('final List<Line> lines;'));
    });

    test('reads itself back from JSON, and writes itself to it', () {
      final String source = _library(module);
      expect(source, contains('factory Order.fromJson(Map<String, Object?> json)'));
      expect(source, contains('Map<String, Object?> toJson()'));
      // A nested reference is decoded through the type it names, not left
      // as a map the caller has to know about.
      expect(source, contains('Line.fromJson('));
    });

    test('leaves a null field out of its JSON rather than sending null', () {
      expect(_library(module), contains("if (total != null) 'total': total"));
    });
  });

  group('what it refuses', () {
    test('a document with no server, because a host needs a base URL', () {
      expect(
        () => dvGenerateDescribedApiModule(
          document: _document(servers: <Object?>[]),
          moduleId: 'vendorErp',
        ),
        throwsA(isA<DVDescribedApiRefused>().having(
          (DVDescribedApiRefused e) => e.message,
          'message',
          contains('servers'),
        )),
      );
    });

    test('two operations that would generate the same method', () {
      // Silently keeping one would drop a call the document describes.
      expect(
        () => _generate(_document(paths: <String, Object?>{
          '/orders': <String, Object?>{
            'get': <String, Object?>{
              'operationId': 'listOrders',
              'responses': <String, Object?>{'200': <String, Object?>{}},
            },
          },
          '/orders/': <String, Object?>{
            'get': <String, Object?>{
              'operationId': 'listOrders',
              'responses': <String, Object?>{'200': <String, Object?>{}},
            },
          },
        })),
        throwsA(isA<DVDescribedApiRefused>().having(
          (DVDescribedApiRefused e) => e.message,
          'message',
          contains('listOrders'),
        )),
      );
    });

    test('a reference to a schema the document does not define', () {
      expect(
        () => _generate(_document(
          paths: <String, Object?>{},
          schemas: <String, Object?>{
            'Order': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'line': <String, Object?>{
                  r'$ref': '#/components/schemas/Missing',
                },
              },
            },
          },
        )),
        throwsA(isA<DVDescribedApiRefused>().having(
          (DVDescribedApiRefused e) => e.message,
          'message',
          contains('Missing'),
        )),
      );
    });

    test('an OpenAPI version it has not been written against', () {
      final Map<String, Object?> document = _document()..['openapi'] = '2.0';
      expect(
        () => dvGenerateDescribedApiModule(
          document: document,
          moduleId: 'vendorErp',
        ),
        throwsA(isA<DVDescribedApiRefused>()),
      );
    });
  });

  test('the same document twice generates the same bytes', () {
    // DV-BIND-002: generation that differs between two runs on one input is
    // a build error, and the first place to hold the line is here.
    final Map<String, Object?> document = _document(
      paths: <String, Object?>{
        '/orders': <String, Object?>{
          'get': <String, Object?>{
            'operationId': 'listOrders',
            'responses': <String, Object?>{'200': <String, Object?>{}},
          },
          'post': <String, Object?>{
            'operationId': 'createOrder',
            'responses': <String, Object?>{'201': <String, Object?>{}},
          },
        },
      },
      schemas: <String, Object?>{
        'Order': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'id': <String, Object?>{'type': 'string'},
          },
        },
      },
    );

    expect(_generate(document).files, _generate(document).files);
  });

  group('the generated code is real', _generatedCodeIsReal);
}

// The tests above read the generated source. These run it, which is the only
// thing that proves an argument list, a JSON cast or a query string is right
// rather than plausible: every shape assertion above passed on a first run,
// and a generator whose output does not compile passes every one of them.
void _generatedCodeIsReal() {
  /// The document both tests below generate from.
  Map<String, Object?> document() => <String, Object?>{
        'openapi': '3.0.3',
        'info': <String, Object?>{'title': 'Vendor ERP', 'version': '1'},
        'servers': <Object?>[
          <String, Object?>{'url': 'https://api.vendor.com'},
        ],
        'paths': <String, Object?>{
          '/orders/{id}': <String, Object?>{
            'get': <String, Object?>{
              'operationId': 'getOrder',
              'parameters': <Object?>[
                <String, Object?>{
                  'name': 'id',
                  'in': 'path',
                  'required': true,
                  'schema': <String, Object?>{'type': 'string'},
                },
                <String, Object?>{
                  'name': 'include',
                  'in': 'query',
                  'schema': <String, Object?>{'type': 'string'},
                },
              ],
              'responses': <String, Object?>{
                '200': <String, Object?>{
                  'content': <String, Object?>{
                    'application/json': <String, Object?>{
                      'schema': <String, Object?>{
                        r'$ref': '#/components/schemas/Order',
                      },
                    },
                  },
                },
              },
            },
          },
          '/orders': <String, Object?>{
            'get': <String, Object?>{
              'operationId': 'listOrders',
              'responses': <String, Object?>{
                '200': <String, Object?>{
                  'content': <String, Object?>{
                    'application/json': <String, Object?>{
                      'schema': <String, Object?>{
                        'type': 'array',
                        'items': <String, Object?>{
                          r'$ref': '#/components/schemas/Order',
                        },
                      },
                    },
                  },
                },
              },
            },
            'post': <String, Object?>{
              'operationId': 'createOrder',
              'requestBody': <String, Object?>{
                'required': true,
                'content': <String, Object?>{
                  'application/json': <String, Object?>{
                    'schema': <String, Object?>{
                      r'$ref': '#/components/schemas/Order',
                    },
                  },
                },
              },
              'responses': <String, Object?>{
                '201': <String, Object?>{
                  'content': <String, Object?>{
                    'application/json': <String, Object?>{
                      'schema': <String, Object?>{
                        r'$ref': '#/components/schemas/Order',
                      },
                    },
                  },
                },
              },
            },
          },
        },
        'components': <String, Object?>{
          'schemas': <String, Object?>{
            'Order': <String, Object?>{
              'type': 'object',
              'required': <Object?>['id', 'lines'],
              'properties': <String, Object?>{
                'id': <String, Object?>{'type': 'string'},
                'total': <String, Object?>{'type': 'number'},
                'lines': <String, Object?>{
                  'type': 'array',
                  'items': <String, Object?>{
                    r'$ref': '#/components/schemas/Line',
                  },
                },
              },
            },
            'Line': <String, Object?>{
              'type': 'object',
              'required': <Object?>['sku'],
              'properties': <String, Object?>{
                'sku': <String, Object?>{'type': 'string'},
                'quantity': <String, Object?>{'type': 'integer'},
              },
            },
          },
        },
      };

  /// Writes [source] beside this package's own resolution and runs it.
  ///
  /// Inside .dart_tool so `package:dartvel_core/...` resolves without a pub
  /// get, and a directory per call because the analyzer caches on path.
  Future<ProcessResult> ran(String verb, String source) async {
    final Directory scratch = Directory(p.join(
      Directory.current.path,
      '.dart_tool',
      'dv_openapi_probe',
      'probe_${DateTime.now().microsecondsSinceEpoch}',
    ))
      ..createSync(recursive: true);
    addTearDown(() {
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    });
    final File probe = File(p.join(scratch.path, 'probe.dart'))
      ..writeAsStringSync(source);
    return Process.run(
      Platform.resolvedExecutable,
      <String>[verb, if (verb == 'analyze') '--fatal-infos', probe.path],
    );
  }

  String generated() {
    final DVGeneratedModule module = dvGenerateDescribedApiModule(
      document: document(),
      moduleId: 'vendorErp',
    );
    // The library alone: the package: URI it would be imported by does not
    // exist until it is on disk with a pubspec, and what is being checked is
    // the source, not pub.
    return module.files['lib/vendor_erp.dart']!
        .replaceFirst('library vendor_erp;', '');
  }

  test('the generated library analyzes with nothing to say', () async {
    final ProcessResult result = await ran('analyze', generated());
    expect(
      '${result.stdout}${result.stderr}',
      contains('No issues found'),
      reason: '${result.stdout}${result.stderr}',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a generated call sends the request the document describes', () async {
    // Against DV.Http's own fake, so what is checked is the request that
    // reached the wire: the method, the path with the parameter encoded into
    // it, the query, and the body as JSON.
    final ProcessResult result = await ran('run', '''
import 'dart:convert';

${generated()}

Future<void> main() async {
  const DVHttp().declare(
    'vendorErp',
    const DVHttpHostConfig(baseUrl: 'https://api.vendor.com'),
  );
  final DVHttpFake fake = const DVHttp().fake(<String, DVHttpStub>{
    'vendorErp': DVHttpStub.json(<String, Object?>{
      'id': 'o/1',
      'total': 12.5,
      'lines': <Object?>[<String, Object?>{'sku': 'A-1', 'quantity': 2}],
    }),
  });

  final Order order =
      await const VendorErpApi().getOrder(id: 'o/1', include: 'lines');
  print('url \${fake.calls.single.url}');
  print('id \${order.id} total \${order.total} sku \${order.lines.single.sku}');

  const DVHttp().fake(<String, DVHttpStub>{
    'vendorErp': DVHttpStub.json(<Object?>[
      <String, Object?>{'id': 'o1', 'lines': <Object?>[]},
    ]),
  });
  final List<Order> orders = await const VendorErpApi().listOrders();
  print('listed \${orders.length}');

  final DVHttpFake posted = const DVHttp().fake(<String, DVHttpStub>{
    'vendorErp': DVHttpStub.json(<String, Object?>{
      'id': 'o2',
      'lines': <Object?>[],
    }, status: 201),
  });
  await const VendorErpApi().createOrder(
    body: const Order(id: 'o2', lines: <Line>[Line(sku: 'B-2')]),
  );
  print('sent \${utf8.decode(posted.calls.single.body)}');
}
''');
    final String output = '${result.stdout}${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    // The slash in the key is encoded, so the call reaches /orders/o%2F1 and
    // not the collection endpoint one level up.
    expect(output, contains('url https://api.vendor.com/orders/o%2F1?include=lines'));
    expect(output, contains('id o/1 total 12.5 sku A-1'));
    expect(output, contains('listed 1'));
    expect(output, contains('sent {"id":"o2","lines":[{"sku":"B-2"}]}'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
