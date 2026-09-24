// A GraphQL schema becomes a Dartvel module, the same way an OpenAPI
// document does: pure Dart over DV.Http, no foreign runtime and no binding.
//
// The hard part is not the parser. It is that a schema is a graph and a
// request carries a selection, so the generated types have to say exactly
// what was asked for. A class with a field the query never selected is a
// type that lies, and it lies by being null rather than by failing, which is
// the failure nobody finds.
import 'dart:io';

import 'package:dartvel_cli/src/modules/graphql_module.dart';
import 'package:dartvel_cli/src/modules/openapi_module.dart'
    show DVDescribedApiRefused, DVGeneratedModule;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

DVGeneratedModule _generate(String schema, {String? url}) =>
    dvGenerateGraphQlModule(
      schema: schema,
      moduleId: 'vendorErp',
      url: url ?? 'https://api.vendor.com/graphql',
    );

String _library(DVGeneratedModule module) =>
    module.files['lib/${module.packageName}.dart']!;

const String _schema = '''
schema { query: Query, mutation: Mutation }

"An order somebody placed."
type Query {
  order(id: ID!): Order
  orders(limit: Int, status: Status): [Order!]!
}

type Mutation {
  placeOrder(input: OrderInput!): Order!
}

type Order {
  id: ID!
  total: Float
  paid: Boolean!
  status: Status!
  customer: Customer
}

type Customer {
  id: ID!
  name: String!
  orders: [Order!]!
}

input OrderInput {
  customerId: ID!
  note: String
}

enum Status { PLACED SHIPPED }
''';

void main() {
  group('the package it writes', () {
    final DVGeneratedModule module = _generate(_schema);

    test('is a module, named for the id, declaring its host', () {
      expect(module.packageName, 'vendor_erp');
      expect(module.files['pubspec.yaml'], contains('id: vendorErp'));
      expect(
        module.files['pubspec.yaml'],
        contains('        baseUrl: "https://api.vendor.com"'),
      );
      // The path is the endpoint, and it is not in the base URL: a host is
      // a host, and every call on it goes to the same one path.
      expect(_library(module), contains("const String endpoint = '/graphql';"));
    });
  });

  group('a query field', () {
    final String source = _library(_generate(_schema));

    test('becomes a method with its arguments typed', () {
      expect(source, contains('Future<OrderResult?> order({required String id})'));
      expect(
        source,
        contains('Future<List<OrdersResult>> orders({int? limit, Status? status})'),
      );
    });

    test('sends a document with variables, never values spliced into it', () {
      // A value written into the query text is an injection, and a schema
      // whose arguments are strings makes it an easy one.
      expect(source, contains(r'query Order($id: ID!)'));
      expect(source, contains(r'order(id: $id)'));
      expect(source, contains("'variables':"));
      expect(source, isNot(contains(r'${id}')));
    });

    test('selects every field it generated a Dart field for', () {
      // The selection and the class are written from one walk, so a field
      // in one and not the other cannot happen.
      expect(source, contains('id total paid status'));
      expect(source, contains('class OrderResult {'));
      expect(source, contains('final String id;'));
      expect(source, contains('final double? total;'));
      expect(source, contains('final bool paid;'));
      expect(source, contains('final Status status;'));
    });

    test('stops where the graph turns back on itself, and says so', () {
      // Customer.orders returns to Order. The selection omits it, and so
      // does the class: a field that is always null because nothing asked
      // for it is worse than no field at all.
      expect(source, contains('class OrderResultCustomer {'));
      expect(source, contains('final String name;'));
      expect(source, isNot(contains('class OrderResultCustomerOrder')));
      expect(
        source,
        contains('/// `orders` is not selected here: it returns to `Order`,'),
      );
    });
  });

  group('a mutation', () {
    final String source = _library(_generate(_schema));

    test('takes its input type as a Dart class', () {
      expect(source, contains('class OrderInput {'));
      expect(source, contains('final String customerId;'));
      expect(source, contains('final String? note;'));
      expect(
        source,
        contains('Future<PlaceOrderResult> placeOrder('
            '{required OrderInput input})'),
      );
    });

    test('is sent as a mutation, not a query', () {
      expect(source, contains(r'mutation PlaceOrder($input: OrderInput!)'));
    });
  });

  group('an enum', () {
    final String source = _library(_generate(_schema));

    test('becomes a Dart enum that keeps the wire spelling', () {
      expect(source, contains('enum Status {'));
      expect(source, contains("placed('PLACED')"));
      expect(source, contains("shipped('SHIPPED')"));
    });

    test('a value the schema did not list is an error, not a silent null', () {
      // A server that adds a value is the commonest breaking change there
      // is, and reading it as null would put a wrong value into a record.
      expect(source, contains('Status.fromWire'));
      expect(source, contains('VendorErpException'));
    });
  });

  group('what it refuses', () {
    test('a schema with no Query type', () {
      expect(
        () => _generate('type Order { id: ID! }'),
        throwsA(isA<DVDescribedApiRefused>().having(
          (DVDescribedApiRefused e) => e.message,
          'message',
          contains('Query'),
        )),
      );
    });

    test('a subscription, which is not a request over HTTP', () {
      expect(
        () => _generate('''
schema { query: Query, subscription: Subscription }
type Query { ping: String }
type Subscription { orderPlaced: String }
'''),
        throwsA(isA<DVDescribedApiRefused>().having(
          (DVDescribedApiRefused e) => e.message,
          'message',
          contains('subscription'),
        )),
      );
    });

    test('an interface or a union, which need a typed fragment', () {
      expect(
        () => _generate('''
type Query { thing: Thing }
union Thing = Order | Customer
type Order { id: ID! }
type Customer { id: ID! }
'''),
        throwsA(isA<DVDescribedApiRefused>().having(
          (DVDescribedApiRefused e) => e.message,
          'message',
          contains('union'),
        )),
      );
    });

    test('a field whose type the schema never defines', () {
      expect(
        () => _generate('type Query { order: Order }'),
        throwsA(isA<DVDescribedApiRefused>().having(
          (DVDescribedApiRefused e) => e.message,
          'message',
          contains('Order'),
        )),
      );
    });

    test('a URL that is not one', () {
      expect(
        () => _generate(_schema, url: 'api.vendor.com/graphql'),
        throwsA(isA<DVDescribedApiRefused>()),
      );
    });
  });

  test('the same schema twice generates the same bytes', () {
    expect(_generate(_schema).files, _generate(_schema).files);
  });

  group('the generated code is real', () {
    Future<ProcessResult> ran(String verb, String source) async {
      final Directory scratch = Directory(p.join(
        Directory.current.path,
        '.dart_tool',
        'dv_graphql_probe',
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

    String generated() =>
        _library(_generate(_schema)).replaceFirst('library vendor_erp;', '');

    test('analyzes with nothing to say', () async {
      final ProcessResult result = await ran('analyze', generated());
      expect(
        '${result.stdout}${result.stderr}',
        contains('No issues found'),
        reason: '${result.stdout}${result.stderr}',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('sends the document and reads the answer back', () async {
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
      'data': <String, Object?>{
        'order': <String, Object?>{
          'id': 'o1',
          'total': 12.5,
          'paid': true,
          'status': 'SHIPPED',
          'customer': <String, Object?>{'id': 'c1', 'name': 'Ada'},
        },
      },
    }),
  });

  final OrderResult? order = await const VendorErpApi().order(id: 'o1');
  final Map<String, Object?> sent =
      jsonDecode(utf8.decode(fake.calls.single.body)) as Map<String, Object?>;
  print('url \${fake.calls.single.url}');
  print('query \${sent['query']}');
  print('variables \${jsonEncode(sent['variables'])}');
  print('read \${order!.id} \${order.status} \${order.customer!.name}');

  const DVHttp().fake(<String, DVHttpStub>{
    'vendorErp': DVHttpStub.json(<String, Object?>{
      'errors': <Object?>[<String, Object?>{'message': 'no such order'}],
    }),
  });
  try {
    await const VendorErpApi().order(id: 'nope');
    print('NOT THROWN');
  } on VendorErpException catch (error) {
    print('refused \$error');
  }
}
''');
      final String output = '${result.stdout}${result.stderr}';
      expect(result.exitCode, 0, reason: output);
      expect(output, contains('url https://api.vendor.com/graphql'));
      expect(
        output,
        contains(r'query query Order($id: ID!) { order(id: $id) '
            '{ id total paid status customer { id name } } }'),
      );
      expect(output, contains('variables {"id":"o1"}'));
      expect(output, contains('read o1 Status.shipped Ada'));
      expect(output, contains('refused'));
      expect(output, contains('no such order'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
