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
  });

  tearDown(() {
    database.close();
    dvModelFactories.clear();
    dvModelSerializers.clear();
    dvModelDeserializers.clear();
  });

  Widget host() => MaterialApp(
        home: Material(
          child: DVModelAdmin<Account>(
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

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(host());
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
}
