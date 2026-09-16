// The generated model admin, driven the way a person drives it.
//
// The callbacks are wired to a real store rather than stubs, because the
// point of the screen is that listing, saving and deleting actually reach
// persistence — a version that only calls its own callbacks would pass while
// nothing was written.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Account {
  final String id;
  final String email;
  final int seats;

  const Account({required this.id, required this.email, required this.seats});

  Map<String, Object?> toJson() =>
      <String, Object?>{'id': id, 'email': email, 'seats': seats};

  static Account fromJson(Map<String, Object?> json) => Account(
        id: json['id']! as String,
        email: json['email']! as String,
        seats: json['seats'] is num
            ? (json['seats']! as num).toInt()
            : num.parse('${json['seats']}').toInt(),
      );
}

/// The persistence the generated `all`/`save`/`destroy` provide, over the
/// same DV.Database the generated code uses.
class AccountStore {
  static const String table = 'accounts';

  Future<void> _initialize() => const DVDatabase().execute(
      'CREATE TABLE IF NOT EXISTS $table (id TEXT, email TEXT, seats TEXT)');

  Future<List<Account>> all() async {
    await _initialize();
    final rows = await const DVDatabase().query('SELECT * FROM $table');
    return rows.map(Account.fromJson).toList(growable: false);
  }

  Future<Account> save(Account model) async {
    await _initialize();
    const database = DVDatabase();
    await database
        .execute('DELETE FROM $table WHERE id = ?', <Object?>[model.id]);
    await database.execute(
      'INSERT INTO $table (id, email, seats) VALUES (?, ?, ?)',
      <Object?>[model.id, model.email, model.seats],
    );
    return model;
  }

  Future<void> destroy(Account model) => const DVDatabase()
      .execute('DELETE FROM $table WHERE id = ?', <Object?>[model.id]);
}

void main() {
  late SqliteDVDatabaseAdapter database;
  late AccountStore store;

  setUp(() {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    store = AccountStore();
    registerDVModelFactory<Account>(
        () => const Account(id: '', email: '', seats: 0));
    registerDVModelSerializer<Account>((Account model) => model.toJson());
    registerDVModelDeserializer<Account>(Account.fromJson);
    // The admin asks a policy before it offers an action, and a model
    // nobody wrote one for is refused like any other unanswered policy. The
    // screen itself is what these tests drive, so everybody may.
    DV.Test.resetPolicies();
    for (final String action in <String>['create', 'update', 'delete']) {
      DV.Auth.authorization
          .register<Object?, Account>(action, (Object? user, Account a) => true);
    }
  });

  tearDown(() {
    DV.Test.resetPolicies();
    DV.Test.resetAuth();
    database.close();
    dvModelFactories.clear();
    dvModelSerializers.clear();
    dvModelDeserializers.clear();
  });

  Widget host({Object? as}) => MaterialApp(
        home: Material(
          child: DVModelAdmin<Account>(
            as: as,
            title: 'Account',
            load: store.all,
            save: store.save,
            destroy: store.destroy,
            blank: () => const Account(id: 'new', email: '', seats: 0),
            label: (Account model) => model.id,
            form: (Account model, void Function(Account) onSubmit) =>
                DVForm<Account>(model, onSubmit),
          ),
        ),
      );

  Future<void> open(WidgetTester tester, {Object? as}) async {
    await tester.pumpWidget(host(as: as));
    await tester.pumpAndSettle();
  }

  testWidgets('stored records are listed', (WidgetTester tester) async {
    await store.save(const Account(id: 'a1', email: 'a@x.com', seats: 1));
    await store.save(const Account(id: 'a2', email: 'b@x.com', seats: 2));

    await open(tester);

    expect(find.text('a1'), findsOneWidget);
    expect(find.text('a2'), findsOneWidget);
    expect(find.text('Select or create a Account to edit.'), findsOneWidget);
  });

  testWidgets('an empty table says so rather than looking broken',
      (WidgetTester tester) async {
    await open(tester);

    expect(find.text('No Account records yet.'), findsOneWidget);
  });

  testWidgets('opening a record shows its own values',
      (WidgetTester tester) async {
    await store.save(const Account(id: 'a1', email: 'a@x.com', seats: 7));

    await open(tester);
    await tester
        .tap(find.byKey(const ValueKey<String>('dv-admin-record-a1')));
    await tester.pumpAndSettle();

    expect(find.byType(EditableText), findsNWidgets(3));
    expect(
      tester.widget<EditableText>(find.byType(EditableText).at(1)).controller
          .text,
      'a@x.com',
    );
  });

  testWidgets('editing a record writes the change through to the store',
      (WidgetTester tester) async {
    await store.save(const Account(id: 'a1', email: 'old@x.com', seats: 1));

    await open(tester);
    await tester
        .tap(find.byKey(const ValueKey<String>('dv-admin-record-a1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).at(1), 'new@x.com');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final stored = await store.all();
    expect(stored, hasLength(1));
    expect(stored.single.email, 'new@x.com');
    expect(find.text('Saved.'), findsOneWidget);
  });

  testWidgets('New creates a record that did not exist before',
      (WidgetTester tester) async {
    await open(tester);

    await tester.tap(find.byKey(const ValueKey<String>('dv-admin-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).at(1), 'fresh@x.com');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final stored = await store.all();
    expect(stored, hasLength(1));
    expect(stored.single.id, 'new');
    expect(stored.single.email, 'fresh@x.com');
    // The list reflects it without a reload.
    expect(find.byKey(const ValueKey<String>('dv-admin-record-new')),
        findsOneWidget);
  });

  testWidgets('Delete removes the record and closes the editor',
      (WidgetTester tester) async {
    await store.save(const Account(id: 'a1', email: 'a@x.com', seats: 1));

    await open(tester);
    await tester
        .tap(find.byKey(const ValueKey<String>('dv-admin-record-a1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('dv-admin-delete')));
    await tester.pumpAndSettle();

    expect(await store.all(), isEmpty);
    expect(find.text('Select or create a Account to edit.'), findsOneWidget);
    expect(find.text('Deleted.'), findsOneWidget);
  });

  testWidgets('switching records shows the second one, not the first',
      (WidgetTester tester) async {
    await store.save(const Account(id: 'a1', email: 'one@x.com', seats: 1));
    await store.save(const Account(id: 'a2', email: 'two@x.com', seats: 2));

    await open(tester);
    await tester
        .tap(find.byKey(const ValueKey<String>('dv-admin-record-a1')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey<String>('dv-admin-record-a2')));
    await tester.pumpAndSettle();

    // A form reused across records would still be holding one@x.com.
    expect(
      tester.widget<EditableText>(find.byType(EditableText).at(1)).controller
          .text,
      'two@x.com',
    );
  });

  testWidgets('an unreadable table is reported, not shown as empty',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: DVModelAdmin<Account>(
          title: 'Account',
          load: () => Future<List<Account>>.error(
              StateError('no such table: accounts')),
          save: store.save,
          destroy: store.destroy,
          blank: () => const Account(id: 'new', email: '', seats: 0),
          label: (Account model) => model.id,
          form: (Account model, void Function(Account) onSubmit) =>
              DVForm<Account>(model, onSubmit),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not read Account'), findsOneWidget);
    expect(find.text('No Account records yet.'), findsNothing);
  });

  group('the policy decides which actions are offered', () {
    Future<void> openRecord(WidgetTester tester, {Object? as}) async {
      await open(tester, as: as);
      await tester
          .tap(find.byKey(const ValueKey<String>('dv-admin-record-a1')));
      await tester.pumpAndSettle();
    }

    testWidgets('Delete is not offered to somebody the policy forbids',
        (WidgetTester tester) async {
      await store.save(const Account(id: 'a1', email: 'a@x.com', seats: 1));
      DV.Auth.authorization.register<Object?, Account>(
          'delete', (Object? user, Account a) => false);

      await openRecord(tester);

      expect(find.byKey(const ValueKey<String>('dv-admin-delete')),
          findsNothing);
    });

    testWidgets('a delete refused after the screen drew is refused at the write',
        (WidgetTester tester) async {
      await store.save(const Account(id: 'a1', email: 'a@x.com', seats: 1));
      bool allowed = true;
      DV.Auth.authorization.register<Object?, Account>(
          'delete', (Object? user, Account a) => allowed);

      await openRecord(tester);
      expect(find.byKey(const ValueKey<String>('dv-admin-delete')),
          findsOneWidget);
      // A role removed while the screen was open: the button is still
      // drawn, and pressing it must not delete.
      allowed = false;
      await tester.tap(find.byKey(const ValueKey<String>('dv-admin-delete')));
      await tester.pumpAndSettle();

      expect((await store.all()).map((Account a) => a.id), <String>['a1']);
      expect(find.textContaining('Account.delete is not allowed'),
          findsOneWidget);
    });

    testWidgets('New is not offered when the policy refuses create',
        (WidgetTester tester) async {
      DV.Auth.authorization.register<Object?, Account>(
          'create', (Object? user, Account a) => false);

      await open(tester);

      expect(find.byKey(const ValueKey<String>('dv-admin-new')), findsNothing);
    });

    testWidgets('a record the policy refuses to update is shown without Save',
        (WidgetTester tester) async {
      await store.save(const Account(id: 'a1', email: 'a@x.com', seats: 1));
      DV.Auth.authorization.register<Object?, Account>(
          'update', (Object? user, Account a) => false);

      await openRecord(tester);

      expect(find.byType(EditableText), findsNWidgets(3));
      expect(find.text('Save'), findsNothing);
      expect(find.textContaining('Account.update is not allowed'),
          findsOneWidget);
    });

    testWidgets('a save refused after the form drew writes nothing',
        (WidgetTester tester) async {
      await store.save(const Account(id: 'a1', email: 'old@x.com', seats: 1));
      bool allowed = true;
      DV.Auth.authorization.register<Object?, Account>(
          'update', (Object? user, Account a) => allowed);

      await openRecord(tester);
      await tester.enterText(find.byType(EditableText).at(1), 'new@x.com');
      allowed = false;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect((await store.all()).single.email, 'old@x.com');
      expect(find.text('Saved.'), findsNothing);
    });

    testWidgets('an update is asked about the stored record, not the edit',
        (WidgetTester tester) async {
      // Ownership is judged on what exists: typing somebody else's value
      // into the form must not make a record one may edit.
      await store.save(const Account(id: 'a1', email: 'mine@x.com', seats: 1));
      DV.Auth.authorization.register<Object?, Account>(
          'update', (Object? user, Account a) => a.email == 'mine@x.com');

      await openRecord(tester);
      await tester.enterText(find.byType(EditableText).at(1), 'other@x.com');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect((await store.all()).single.email, 'other@x.com');
    });

    testWidgets(
        'a policy written against the application\'s user refuses the session '
        'user rather than throwing', (WidgetTester tester) async {
      await store.save(const Account(id: 'a1', email: 'a@x.com', seats: 1));
      DV.Auth.authorization
          .register<Member, Account>('delete', (Member m, Account a) => true);

      await DV.Test.asUser(DV.Test.fakeAuthUser(id: 'u1'), () async {
        await openRecord(tester);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey<String>('dv-admin-delete')),
            findsNothing);
      });
    });

    testWidgets('the application\'s user handed to the admin is who is asked',
        (WidgetTester tester) async {
      await store.save(const Account(id: 'a1', email: 'a@x.com', seats: 1));
      DV.Auth.authorization.register<Member, Account>(
          'delete', (Member m, Account a) => m.id == 'm1');

      await DV.Test.asUser(DV.Test.fakeAuthUser(id: 'u1'), () async {
        await openRecord(tester, as: const Member('m1'));
        await tester
            .tap(find.byKey(const ValueKey<String>('dv-admin-delete')));
        await tester.pumpAndSettle();
      });

      expect(await store.all(), isEmpty);
    });

    testWidgets('an application user of the wrong type is refused, not '
        'swapped for the session user', (WidgetTester tester) async {
      await store.save(const Account(id: 'a1', email: 'a@x.com', seats: 1));
      DV.Auth.authorization.register<DVAuthUser, Account>(
          'delete', (DVAuthUser u, Account a) => true);

      await DV.Test.asUser(DV.Test.fakeAuthUser(id: 'u1'), () async {
        await openRecord(tester, as: const Member('m1'));
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey<String>('dv-admin-delete')),
            findsNothing);
      });
    });

    testWidgets('the signed-in user reaches a policy written against it',
        (WidgetTester tester) async {
      await store.save(const Account(id: 'a1', email: 'a@x.com', seats: 1));
      DV.Auth.authorization.register<DVAuthUser, Account>(
          'delete', (DVAuthUser u, Account a) => u.id == 'u1');

      await DV.Test.asUser(DV.Test.fakeAuthUser(id: 'u1'), () async {
        await openRecord(tester);
        expect(find.byKey(const ValueKey<String>('dv-admin-delete')),
            findsOneWidget);
      });
    });
  });
}

/// The application's own user model, which is not the session's DVAuthUser.
class Member {
  final String id;
  const Member(this.id);
}
