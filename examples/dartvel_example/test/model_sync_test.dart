// Drives the generated persistence and sync surface the way an application
// would: real generated User class, real SQLite database, real change hub.
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() async {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    // The generated schema for the model's table.
    await database.execute(const User(
      slug: 's',
      name: 'n',
      email: 'e',
      published: true,
      recoveryToken: 't',
    ).createTableSql);
  });

  tearDown(() async {
    await DVModelSync.reset();
    database.close();
  });

  User user(String slug, {String name = 'Ada'}) => User(
        slug: slug,
        name: name,
        email: '$slug@example.com',
        published: true,
        recoveryToken: 'secret',
      );

  test('save, find and all round-trip through the real database', () async {
    await user('ada').save();
    await user('grace', name: 'Grace').save();

    final found = await User.find('ada');
    expect(found, isNotNull);
    expect(found!.name, 'Ada');
    // Booleans survive SQLite's integer storage.
    expect(found.published, isTrue);

    expect((await User.all()).length, 2);
    expect(await User.find('nobody'), isNull);
  });

  test('save is an upsert keyed on the public path field', () async {
    await user('ada').save();
    await user('ada', name: 'Ada Lovelace').save();

    expect((await User.all()).length, 1);
    expect((await User.find('ada'))!.name, 'Ada Lovelace');
  });

  test('saves publish created then updated; destroy publishes deleted',
      () async {
    final kinds = <DVModelChangeKind>[];
    final sub = User.changes.listen(
      (DVModelChange<User> change) => kinds.add(change.kind),
    );

    final ada = await user('ada').save();
    await ada.save();
    await ada.destroy();
    await Future<void>.delayed(Duration.zero);

    expect(kinds, <DVModelChangeKind>[
      DVModelChangeKind.created,
      DVModelChangeKind.updated,
      DVModelChangeKind.deleted,
    ]);
    expect(await User.find('ada'), isNull);
    await sub.cancel();
  });

  test('watch sees the current rows now and again after each change',
      () async {
    final snapshots = <List<String>>[];
    final watch = await User.watch(
      (List<User> users) =>
          snapshots.add(users.map((User u) => u.slug).toList()..sort()),
    );
    expect(snapshots, <List<String>>[<String>[]]);

    await user('ada').save();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await user('grace').save();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(snapshots.last, <String>['ada', 'grace']);
    await watch.cancel();

    // After cancel, further changes stop arriving.
    final count = snapshots.length;
    await user('alan').save();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(snapshots.length, count);
  });

  test('sync persists and announces the synced state', () async {
    final kinds = <DVModelChangeKind>[];
    final sub = User.changes.listen(
      (DVModelChange<User> change) => kinds.add(change.kind),
    );

    await user('ada').sync();
    await Future<void>.delayed(Duration.zero);

    expect(kinds, contains(DVModelChangeKind.synced));
    expect(await User.find('ada'), isNotNull);
    await sub.cancel();
  });
}
