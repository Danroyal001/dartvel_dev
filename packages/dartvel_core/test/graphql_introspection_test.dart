// Introspection is built from the same registry that serves queries, so it
// cannot drift from what actually executes — the failure mode a
// hand-maintained schema document has.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    DVGraphQL.reset();
    DVGraphQL.registerType(DVGraphQLObjectType('User', const <DVGraphQLField>[
      DVGraphQLField('slug', 'String!'),
      DVGraphQLField('age', 'Int'),
    ]));
    DVGraphQL.registerQuery(
      DVGraphQLField('users', '[User!]!', resolve: (args, parent) => const []),
    );
    DVGraphQL.registerQuery(DVGraphQLField(
      'user',
      'User',
      args: const <String, String>{'slug': 'String!'},
      resolve: (args, parent) => null,
    ));
    DVGraphQL.registerMutation(
      DVGraphQLField('save', 'User!', resolve: (args, parent) => null),
    );
  });

  test('__schema reports the roots and every registered type', () async {
    final result = await DVGraphQL.execute(
      '{ __schema { queryType { name } mutationType { name } '
      'types { name kind } } }',
    );

    expect(result['errors'], isNull);
    final schema = (result['data']! as Map)['__schema']! as Map;
    expect((schema['queryType']! as Map)['name'], 'Query');
    expect((schema['mutationType']! as Map)['name'], 'Mutation');

    final names = (schema['types']! as List)
        .map((Object? t) => (t! as Map)['name'])
        .toList();
    expect(names, containsAll(<String>['Query', 'Mutation', 'User']));
    // The scalars the schema uses are declared too, or a client cannot
    // resolve a field's type.
    expect(names, containsAll(<String>['String', 'Int']));
  });

  test('a field type carries its nullability nesting', () async {
    final result = await DVGraphQL.execute(
      '{ __type(name: "Query") { fields { name '
      'type { kind ofType { kind ofType { kind ofType { kind name } } } } '
      '} } }',
    );

    final fields =
        ((result['data']! as Map)['__type']! as Map)['fields']! as List;
    final users = fields.firstWhere(
      (Object? f) => (f! as Map)['name'] == 'users',
    )! as Map;

    // [User!]! is NON_NULL(LIST(NON_NULL(User))); a client reads nullability
    // from exactly this nesting.
    final type = users['type']! as Map;
    expect(type['kind'], 'NON_NULL');
    final list = type['ofType']! as Map;
    expect(list['kind'], 'LIST');
    final inner = list['ofType']! as Map;
    expect(inner['kind'], 'NON_NULL');
    expect((inner['ofType']! as Map)['name'], 'User');
  });

  test('a nullable field is not wrapped in NON_NULL', () async {
    final result = await DVGraphQL.execute(
      '{ __type(name: "User") { fields { name type { kind name } } } }',
    );

    final fields =
        ((result['data']! as Map)['__type']! as Map)['fields']! as List;
    final age = fields.firstWhere(
      (Object? f) => (f! as Map)['name'] == 'age',
    )! as Map;
    expect((age['type']! as Map)['kind'], 'SCALAR');
    expect((age['type']! as Map)['name'], 'Int');
  });

  test('arguments are reported so a client knows how to call a field',
      () async {
    final result = await DVGraphQL.execute(
      '{ __type(name: "Query") { fields { name args { name } } } }',
    );

    final fields =
        ((result['data']! as Map)['__type']! as Map)['fields']! as List;
    final user = fields.firstWhere(
      (Object? f) => (f! as Map)['name'] == 'user',
    )! as Map;
    expect(((user['args']! as List).single as Map)['name'], 'slug');
  });

  test('__type of an unknown name is null rather than an error', () async {
    final result =
        await DVGraphQL.execute('{ __type(name: "Ghost") { name } }');

    expect(result['errors'], isNull);
    expect((result['data']! as Map)['__type'], isNull);
  });

  test('__typename resolves at the root and inside a selection', () async {
    DVGraphQL.registerQuery(
      DVGraphQLField(
        'users',
        '[User!]!',
        resolve: (args, parent) => <Map<String, Object?>>[
          <String, Object?>{'slug': 'ada'},
        ],
      ),
    );

    final result =
        await DVGraphQL.execute('{ __typename users { __typename slug } }');

    final data = result['data']! as Map;
    expect(data['__typename'], 'Query');
    expect(((data['users']! as List).first as Map)['__typename'], 'User');
  });

  test('introspection follows the registry, not a fixed document', () async {
    DVGraphQL.registerQuery(const DVGraphQLField('addedLater', 'String'));

    final result = await DVGraphQL.execute(
      '{ __type(name: "Query") { fields { name } } }',
    );

    final names =
        (((result['data']! as Map)['__type']! as Map)['fields']! as List)
            .map((Object? f) => (f! as Map)['name'])
            .toList();
    expect(names, contains('addedLater'));
  });

  test('an empty schema reports null roots rather than empty ones', () {
    DVGraphQL.reset();

    final schema = DVGraphQL.introspectionSchema();

    expect(schema['queryType'], isNull);
    expect(schema['mutationType'], isNull);
    // Subscriptions are not implemented, and the document says so rather
    // than advertising a root that cannot be used.
    expect(schema['subscriptionType'], isNull);
  });
}
