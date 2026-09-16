// The generated GraphQL surface for models, driven the way a client would:
// queries and mutations through DVGraphQL.execute against the generated User
// resolvers, backed by real SQLite. Registration itself is under test too —
// configureDartvelRuntime() must force it, since the lazy blocks run for
// nobody on their own.
//
// Every generated field asks the model's policy before it reads or writes, so
// each test registers a User policy whose answer it controls. The last test
// has it refuse.
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SqliteDVDatabaseAdapter database;
  // What the registered User policy answers, for every action.
  late bool allowed;

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
    allowed = true;
    for (final String action in <String>[
      'viewAny',
      'view',
      'create',
      'update',
      'delete',
    ]) {
      DV.Auth.authorization.register<Object?, User?>(
        action,
        (Object? user, User? record) => allowed,
      );
    }
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

  test(
      'an update names the version it read: without one it is refused, and '
      'the stored row is unchanged', () async {
    Map<Object?, Object?> saved(Map<String, Object?> result) =>
        (result['data']! as Map<Object?, Object?>)['saveUser']
            as Map<Object?, Object?>;

    final created = await DVGraphQL.execute('''
      mutation {
        saveUser(slug: "ada", name: "Ada", email: "ada@example.com",
                 published: true) { slug dvVersion }
      }
    ''');
    expect(created['errors'], isNull);
    expect(saved(created)['dvVersion'], 1);

    final read = await DVGraphQL.execute(
      '{ user(slug: "ada") { name dvVersion } }',
    );
    expect((read['data']! as Map)['user'],
        <String, Object?>{'name': 'Ada', 'dvVersion': 1});

    // A client that read nothing cannot know what it would replace.
    final blind = await DVGraphQL.execute('''
      mutation {
        saveUser(slug: "ada", name: "Mallory", email: "m@example.com",
                 published: true) { slug }
      }
    ''');
    expect((blind['data']! as Map)['saveUser'], isNull);
    expect(
      (blind['errors']! as List<Object?>).first,
      containsPair('message', contains('DV-HISTORY-001')),
    );
    expect((await User.find('ada'))!.name, 'Ada');

    // At the version it read, the update lands and moves the version.
    final edited = await DVGraphQL.execute('''
      mutation {
        saveUser(slug: "ada", name: "Ada Lovelace", email: "ada@example.com",
                 published: true, dvVersion: 1) { name dvVersion }
      }
    ''');
    expect(edited['errors'], isNull);
    expect(saved(edited),
        <String, Object?>{'name': 'Ada Lovelace', 'dvVersion': 2});

    // A second client that also read version one is now stale.
    final stale = await DVGraphQL.execute('''
      mutation {
        saveUser(slug: "ada", name: "Countess", email: "ada@example.com",
                 published: true, dvVersion: 1) { name }
      }
    ''');
    expect(
      (stale['errors']! as List<Object?>).first,
      containsPair('message', contains('DV-HISTORY-001')),
    );
    expect((await User.find('ada'))!.name, 'Ada Lovelace');
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

  test('a policy that refuses stops the read, the write and the delete',
      () async {
    await const User(
      slug: 'ada',
      name: 'Ada',
      email: 'a@example.com',
      published: true,
      recoveryToken: 't',
    ).save();
    allowed = false;

    Object? codeOf(Map<String, Object?> result) {
      final Map<Object?, Object?> error =
          (result['errors']! as List<Object?>).first! as Map<Object?, Object?>;
      return (error['extensions'] as Map<Object?, Object?>?)?['code'];
    }

    final listed = await DVGraphQL.execute('{ users { slug } }');
    expect(codeOf(listed), 'FORBIDDEN');

    final read = await DVGraphQL.execute('{ user(slug: "ada") { name } }');
    expect((read['data']! as Map)['user'], isNull);
    expect(codeOf(read), 'FORBIDDEN');

    // An update of a stored record, and a create of a new one: neither is
    // written.
    final updated = await DVGraphQL.execute('''
      mutation {
        saveUser(slug: "ada", name: "Mallory", email: "m@example.com",
                 published: true) { slug }
      }
    ''');
    expect(codeOf(updated), 'FORBIDDEN');
    expect((await User.find('ada'))!.name, 'Ada');

    final created = await DVGraphQL.execute('''
      mutation {
        saveUser(slug: "bob", name: "Bob", email: "b@example.com",
                 published: true) { slug }
      }
    ''');
    expect(codeOf(created), 'FORBIDDEN');
    expect(await User.find('bob'), isNull);

    final deleted =
        await DVGraphQL.execute('mutation { deleteUser(slug: "ada") }');
    expect((deleted['data']! as Map)['deleteUser'], isNull);
    expect(codeOf(deleted), 'FORBIDDEN');
    expect(await User.find('ada'), isNotNull);
  });
}
