import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late List<Map<String, Object?>> users;

  setUp(() {
    users = <Map<String, Object?>>[
      <String, Object?>{'slug': 'ada', 'name': 'Ada', 'age': 36},
      <String, Object?>{'slug': 'grace', 'name': 'Grace', 'age': 45},
    ];
    DVGraphQL.reset();
    DVGraphQL.registerType(DVGraphQLObjectType('User', const <DVGraphQLField>[
      DVGraphQLField('slug', 'String!'),
      DVGraphQLField('name', 'String!'),
      DVGraphQLField('age', 'Int!'),
    ]));
    DVGraphQL.registerQuery(DVGraphQLField(
      'users',
      '[User!]!',
      resolve: (args, parent) => users,
    ));
    DVGraphQL.registerQuery(DVGraphQLField(
      'user',
      'User',
      args: const <String, String>{'slug': 'String!'},
      resolve: (args, parent) {
        for (final user in users) {
          if (user['slug'] == args['slug']) return user;
        }
        return null;
      },
    ));
    DVGraphQL.registerMutation(DVGraphQLField(
      'rename',
      'User!',
      args: const <String, String>{'slug': 'String!', 'name': 'String!'},
      resolve: (args, parent) {
        final user =
            users.firstWhere((u) => u['slug'] == args['slug']);
        user['name'] = args['name'];
        return user;
      },
    ));
  });

  test('selection sets return exactly the requested fields', () async {
    final result = await DVGraphQL.execute('{ users { slug age } }');

    expect(result['errors'], isNull);
    expect(result['data'], <String, Object?>{
      'users': <Object?>[
        <String, Object?>{'slug': 'ada', 'age': 36},
        <String, Object?>{'slug': 'grace', 'age': 45},
      ],
    });
  });

  test('arguments, variables and aliases work together', () async {
    final result = await DVGraphQL.execute(
      r'query GetOne($who: String!) { first: user(slug: $who) { name } }',
      variables: <String, Object?>{'who': 'grace'},
    );

    expect(result['errors'], isNull);
    expect(result['data'], <String, Object?>{
      'first': <String, Object?>{'name': 'Grace'},
    });
  });

  test('mutations run and return their selection', () async {
    final result = await DVGraphQL.execute(
      'mutation { rename(slug: "ada", name: "Ada Lovelace") { name } }',
    );

    expect(result['errors'], isNull);
    expect(
      result['data'],
      <String, Object?>{
        'rename': <String, Object?>{'name': 'Ada Lovelace'},
      },
    );
    expect(users.first['name'], 'Ada Lovelace');
  });

  test('named and inline fragments expand', () async {
    final result = await DVGraphQL.execute('''
      query {
        users {
          ...core
          ... on User { age }
        }
      }
      fragment core on User { slug name }
    ''');

    expect(result['errors'], isNull);
    final first =
        ((result['data']! as Map)['users']! as List).first as Map;
    expect(first.keys, containsAll(<String>['slug', 'name', 'age']));
  });

  test('a failing resolver nulls its field, not the response', () async {
    DVGraphQL.registerQuery(DVGraphQLField(
      'broken',
      'String',
      resolve: (args, parent) => throw StateError('boom'),
    ));

    final result =
        await DVGraphQL.execute('{ broken users { slug } }');

    final data = result['data']! as Map;
    expect(data['broken'], isNull);
    expect(data['users'], hasLength(2));
    expect(
      (result['errors']! as List).first,
      containsPair('message', contains('boom')),
    );
  });

  test('request-level failures return only errors', () async {
    final parseError = await DVGraphQL.execute('{ users { }');
    expect(parseError.containsKey('data'), isFalse);
    expect(parseError['errors'], isNotEmpty);

    final missingVariable = await DVGraphQL.execute(
      r'query($x: String!) { user(slug: $x) { name } }',
    );
    // A missing variable is a field error under this executor: the field
    // nulls and the message names the variable.
    expect(
      (missingVariable['errors']! as List).first,
      containsPair('message', contains(r'$x')),
    );
  });

  test('unknown fields are reported by name', () async {
    final result = await DVGraphQL.execute('{ users { slug ghost } }');

    expect(
      (result['errors']! as List).first,
      containsPair('message', contains('ghost')),
    );
    final first =
        ((result['data']! as Map)['users']! as List).first as Map;
    expect(first['ghost'], isNull);
    expect(first['slug'], 'ada');
  });

  test('the SDL document describes the registered schema', () {
    final sdl = DVGraphQL.toSdl();

    expect(sdl, contains('type Query {'));
    expect(sdl, contains('users: [User!]!'));
    expect(sdl, contains('user(slug: String!): User'));
    expect(sdl, contains('type Mutation {'));
    expect(sdl, contains('rename(slug: String!, name: String!): User!'));
    expect(sdl, contains('type User {'));
    expect(sdl, contains('age: Int!'));
  });

  test('multiple operations need an operationName', () async {
    const document = '''
      query A { users { slug } }
      query B { user(slug: "ada") { name } }
    ''';

    final ambiguous = await DVGraphQL.execute(document);
    expect(
      (ambiguous['errors']! as List).first,
      containsPair('message', contains('operationName')),
    );

    final chosen =
        await DVGraphQL.execute(document, operationName: 'B');
    expect(
      chosen['data'],
      <String, Object?>{
        'user': <String, Object?>{'name': 'Ada'},
      },
    );
  });
}
