// The generated GraphQL surface for models, driven the way a client would:
// queries and mutations through DVGraphQL.execute against the generated User
// resolvers, backed by real SQLite. Registration itself is under test too —
// configureDartvelRuntime() must force it, since the lazy blocks run for
// nobody on their own.
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() async {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    await database.execute(const User(
      slug: 's',
      name: 'n',
      email: 'e',
      published: true,
      recoveryToken: 't',
    ).createTableSql);
    DVGraphQL.reset();
    registerDartvelModels();
  });

  tearDown(() async {
    await DVModelSync.reset();
    database.close();
  });

  test('the generated schema exposes the model, minus sensitive fields', () {
    final sdl = DVGraphQL.toSdl();

    expect(sdl, contains('type User {'));
    expect(sdl, contains('users: [User!]!'));
    expect(sdl, contains('user(slug: String!): User'));
    expect(sdl, contains('saveUser('));
    expect(sdl, contains('deleteUser(slug: String!): Boolean!'));
    // Sensitive fields must not exist anywhere in the public API.
    expect(sdl, isNot(contains('recoveryToken')));
  });

  test('a mutation writes through to the database and queries read back',
      () async {
    final saved = await DVGraphQL.execute('''
      mutation {
        saveUser(slug: "ada", name: "Ada", email: "ada@example.com",
                 published: true) { slug name }
      }
    ''');
    expect(saved['errors'], isNull);
    expect(
      (saved['data']! as Map)['saveUser'],
      <String, Object?>{'slug': 'ada', 'name': 'Ada'},
    );

    // Really in the database, not an in-memory echo.
    expect((await User.find('ada'))!.email, 'ada@example.com');

    final queried = await DVGraphQL.execute(
      r'query($who: String!) { user(slug: $who) { name email } }',
      variables: <String, Object?>{'who': 'ada'},
    );
    expect(
      (queried['data']! as Map)['user'],
      <String, Object?>{'name': 'Ada', 'email': 'ada@example.com'},
    );
  });

  test('sensitive fields cannot be selected, even by name', () async {
    await const User(
      slug: 'ada',
      name: 'Ada',
      email: 'a@example.com',
      published: true,
      recoveryToken: 'super-secret',
    ).save();

    final result = await DVGraphQL.execute(
      '{ user(slug: "ada") { name recoveryToken } }',
    );

    expect(
      (result['errors']! as List).first,
      containsPair('message', contains('recoveryToken')),
    );
    final user = (result['data']! as Map)['user']! as Map;
    expect(user['recoveryToken'], isNull);
    expect(user['name'], 'Ada');
  });

  test('deleteUser removes the row and reports honestly', () async {
    await const User(
      slug: 'ada',
      name: 'Ada',
      email: 'a@example.com',
      published: true,
      recoveryToken: 't',
    ).save();

    final deleted = await DVGraphQL.execute(
      'mutation { deleteUser(slug: "ada") }',
    );
    expect((deleted['data']! as Map)['deleteUser'], isTrue);
    expect(await User.find('ada'), isNull);

    final again = await DVGraphQL.execute(
      'mutation { deleteUser(slug: "ada") }',
    );
    expect((again['data']! as Map)['deleteUser'], isFalse);
  });
}
