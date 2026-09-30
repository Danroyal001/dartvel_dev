// What a form is for: returning the model the fields describe.
//
// DVForm rendered a model's fields and accepted typing into them, but the
// edits stayed inside the widget — submit reassigned the model it started
// with, and there was nothing on screen to submit with in the first place.
// These drive the form the way a person does: type, press Save, check what
// came out.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A model of the shape the generator emits: a serializer, a deserializer
/// that coerces the way the generated `fromJson` does, and a factory.
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

/// Registered without a deserializer, which is the state every model was in
/// before one was generated.
class Legacy {
  final String name;

  const Legacy({required this.name});

  Map<String, Object?> toJson() => <String, Object?>{'name': name};
}

void registerAccount() {
  registerDVModelFactory<Account>(
      () => const Account(id: '', email: '', seats: 0));
  registerDVModelSerializer<Account>((Account model) => model.toJson());
  registerDVModelDeserializer<Account>(Account.fromJson);
}

/// Field order follows the serialized map: id, email, seats.
const int idField = 0;
const int emailField = 1;
const int seatsField = 2;

void main() {
  group('a field kept out of forms', _sensitiveFieldTests);
  group('a write-only field', _writeOnlyFieldTests);

  void clearRegistries() {
    dvModelFactories.clear();
    dvModelSerializers.clear();
    dvModelDeserializers.clear();
    dvModelReadCarriers.clear();
    dvModelFormFields.clear();
    dvModelWriteOnlyFields.clear();
  }

  setUp(clearRegistries);
  tearDown(clearRegistries);

  Future<void> pumpAccountForm(
    WidgetTester tester, {
    required void Function(Account)? onSubmit,
    Account model = const Account(id: 'a1', email: 'old@example.com', seats: 3),
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Material(child: DVForm<Account>(model, onSubmit)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('submit returns the edited model, not the one it started with',
      (WidgetTester tester) async {
    registerAccount();
    Account? submitted;
    await pumpAccountForm(tester, onSubmit: (Account v) => submitted = v);

    await tester.enterText(
        find.byType(EditableText).at(emailField), 'new@example.com');
    await press(tester, 'Save');

    expect(submitted, isNotNull);
    expect(submitted!.email, 'new@example.com');
    // Untouched fields keep their value rather than resetting to a default.
    expect(submitted!.id, 'a1');
    expect(submitted!.seats, 3);
  });

  testWidgets(
      'the edited model carries the version its record was read at, so its '
      'save is checked against that read rather than refused as unread',
      (WidgetTester tester) async {
    registerAccount();
    // Where a generated model keeps the record it was read at: beside the
    // model, keyed by identity, as the generated Expando is.
    final Expando<int> readAt = Expando<int>();
    registerDVModelReadCarrier<Account>((Account read, Account edited) {
      readAt[edited] = readAt[read];
    });
    const Account loaded = Account(id: 'a1', email: 'old@example.com', seats: 3);
    readAt[loaded] = 7;
    Account? submitted;
    await pumpAccountForm(tester,
        model: loaded, onSubmit: (Account v) => submitted = v);

    await tester.enterText(
        find.byType(EditableText).at(emailField), 'new@example.com');
    await press(tester, 'Save');

    expect(identical(submitted, loaded), isFalse);
    expect(readAt[submitted!], 7);
  });

  testWidgets('a typed number comes back as a number, not a string',
      (WidgetTester tester) async {
    registerAccount();
    Account? submitted;
    await pumpAccountForm(tester, onSubmit: (Account v) => submitted = v);

    await tester.enterText(find.byType(EditableText).at(seatsField), '12');
    await press(tester, 'Save');

    expect(submitted!.seats, 12);
  });

  testWidgets('a second edit builds on the first rather than reverting it',
      (WidgetTester tester) async {
    registerAccount();
    final submissions = <Account>[];
    await pumpAccountForm(tester, onSubmit: submissions.add);

    await tester.enterText(
        find.byType(EditableText).at(emailField), 'first@example.com');
    await press(tester, 'Save');
    await tester.enterText(find.byType(EditableText).at(seatsField), '9');
    await press(tester, 'Save');

    expect(submissions, hasLength(2));
    expect(submissions.last.email, 'first@example.com');
    expect(submissions.last.seats, 9);
  });

  testWidgets('reset drops the edits instead of leaving them staged',
      (WidgetTester tester) async {
    registerAccount();
    Account? submitted;
    await pumpAccountForm(tester, onSubmit: (Account v) => submitted = v);

    await tester.enterText(
        find.byType(EditableText).at(emailField), 'typo@example.com');
    await press(tester, 'Reset');
    await press(tester, 'Save');

    expect(submitted!.email, 'old@example.com');
  });

  testWidgets('a form nobody is listening to shows no controls',
      (WidgetTester tester) async {
    registerAccount();
    await pumpAccountForm(tester, onSubmit: null);

    // Offering Save with nowhere for the value to go would be a lie.
    expect(find.text('Save'), findsNothing);
    expect(find.byType(EditableText), findsNWidgets(3));
  });

  testWidgets('a model with no deserializer says so rather than silently '
      'dropping the edit', (WidgetTester tester) async {
    registerDVModelFactory<Legacy>(() => const Legacy(name: ''));
    registerDVModelSerializer<Legacy>((Legacy model) => model.toJson());

    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: DVForm<Legacy>(const Legacy(name: 'old'), (Legacy _) {}),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText).first, 'new');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();

    final error = tester.takeException();
    expect(error, isA<StateError>());
    expect((error as StateError).message,
        allOf(contains('deserializer'), contains('Legacy')));
  });

  testWidgets('a value the model cannot hold names the field',
      (WidgetTester tester) async {
    registerAccount();
    await pumpAccountForm(tester, onSubmit: (Account _) {});

    await tester.enterText(
        find.byType(EditableText).at(seatsField), 'not-a-number');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();

    final error = tester.takeException();
    expect(error, isA<StateError>());
    expect((error as StateError).message,
        allOf(contains('seats'), contains('not-a-number')));
  });

  testWidgets('the fields show the record, not a grey hint of it',
      (WidgetTester tester) async {
    registerAccount();
    await pumpAccountForm(tester, onSubmit: (Account _) {});

    // The value was passed as `hintText`, which draws it as placeholder text
    // in an empty field: a stored record looked like a blank one, and
    // clicking in to edit showed nothing to edit.
    expect(
      tester.widget<EditableText>(find.byType(EditableText).at(emailField))
          .controller.text,
      'old@example.com',
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText).at(seatsField))
          .controller.text,
      '3',
    );
  });

  testWidgets('typing does not fight the field for the cursor',
      (WidgetTester tester) async {
    registerAccount();
    await pumpAccountForm(tester, onSubmit: (Account _) {});

    // Each keystroke rebuilds the form; a controller recreated per build
    // would send the caret back to the start every time.
    final field = find.byType(EditableText).at(emailField);
    await tester.enterText(field, 'abc');
    await tester.pumpAndSettle();

    final state = tester.widget<EditableText>(field);
    expect(state.controller.text, 'abc');
    expect(state.controller.selection.baseOffset, 3);
  });
}

/// A generated model with a `@DVModel.sensitiveField()`: the serializer is the
/// internal one and carries every field, so the form has to be told which of
/// them it may show.
class Member {
  final String id;
  final String name;
  final String passwordHash;

  const Member(
      {required this.id, required this.name, required this.passwordHash});

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'passwordHash': passwordHash,
      };

  static Member fromJson(Map<String, Object?> json) => Member(
        id: json['id']! as String,
        name: json['name']! as String,
        passwordHash: json['passwordHash']! as String,
      );
}

void registerMember() {
  registerDVModelFactory<Member>(
      () => const Member(id: '', name: '', passwordHash: ''));
  registerDVModelSerializer<Member>((Member model) => model.toJson());
  registerDVModelDeserializer<Member>(Member.fromJson);
  // What the generator registers: the fields a form may show, which leaves
  // the sensitive one out.
  registerDVModelFormFields<Member>(const <String>{'id', 'name'});
}

void _sensitiveFieldTests() {
  const Member stored =
      Member(id: 'm1', name: 'Ada', passwordHash: r'$pbkdf2$secret');

  setUp(() {
    dvModelFactories.clear();
    dvModelSerializers.clear();
    dvModelDeserializers.clear();
    dvModelReadCarriers.clear();
    dvModelFormFields.clear();
  });

  Future<void> pumpMember(WidgetTester tester,
      {Member? model, void Function(Member)? onSubmit}) async {
    registerMember();
    await tester.pumpWidget(MaterialApp(
      home: Material(child: DVForm<Member>(model, onSubmit)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a field the model keeps out of forms gets no input',
      (WidgetTester tester) async {
    await pumpMember(tester, onSubmit: (Member _) {});

    expect(find.byType(EditableText), findsNWidgets(2));
    expect(find.text('PASSWORDHASH'), findsNothing);
  });

  testWidgets('its value is not prefilled anywhere on screen',
      (WidgetTester tester) async {
    await pumpMember(tester, model: stored, onSubmit: (Member _) {});

    expect(find.textContaining('secret'), findsNothing);
    for (final Element e in find.byType(EditableText).evaluate()) {
      expect((e.widget as EditableText).controller.text,
          isNot(contains('secret')));
    }
  });

  testWidgets('an edit leaves the stored value as it was, and nothing typed '
      'reaches it', (WidgetTester tester) async {
    Member? submitted;
    await pumpMember(tester,
        model: stored, onSubmit: (Member v) => submitted = v);

    await tester.enterText(find.byType(EditableText).at(1), 'Ada L.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(submitted!.name, 'Ada L.');
    // Not blanked by an edit that never showed it, and not replaced.
    expect(submitted!.passwordHash, stored.passwordHash);
  });

  testWidgets('a builder form is handed the same controls as before',
      (WidgetTester tester) async {
    // The custom builder path already hid the field through the generated
    // form controls; the registration changes nothing there.
    registerMember();
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: DVForm<Member>.builder(
            (DVFormControls c) => DVText('${c.model is Member}'), stored),
      ),
    ));
    expect(find.text('true'), findsOneWidget);
  });
}

/// What the generator registers for a `@DVModel.sensitiveField()` now: the
/// readable fields as before, and the sensitive one as write-only -- an input
/// that can set a value and never shows one, like a password field.
void registerWriteOnlyMember() {
  registerMember();
  registerDVModelWriteOnlyFields<Member>(const <String>{'passwordHash'});
}

void _writeOnlyFieldTests() {
  const Member stored =
      Member(id: 'm1', name: 'Ada', passwordHash: r'$pbkdf2$secret');

  setUp(() {
    dvModelFactories.clear();
    dvModelSerializers.clear();
    dvModelDeserializers.clear();
    dvModelReadCarriers.clear();
    dvModelFormFields.clear();
    dvModelWriteOnlyFields.clear();
  });

  Future<void> pump(WidgetTester tester,
      {Member? model, void Function(Member)? onSubmit}) async {
    registerWriteOnlyMember();
    await tester.pumpWidget(MaterialApp(
      home: Material(child: DVForm<Member>(model, onSubmit)),
    ));
    await tester.pumpAndSettle();
  }

  EditableText input(WidgetTester tester, int index) =>
      tester.widget<EditableText>(find.byType(EditableText).at(index));

  testWidgets('it gets an input, obscured like a password field',
      (WidgetTester tester) async {
    await pump(tester, model: stored, onSubmit: (Member _) {});

    expect(find.byType(EditableText), findsNWidgets(3));
    expect(find.text('PASSWORDHASH'), findsOneWidget);
    expect(input(tester, 2).obscureText, isTrue);
    // The readable fields are not obscured.
    expect(input(tester, 1).obscureText, isFalse);
  });

  testWidgets('the input is empty even when the model holds a value',
      (WidgetTester tester) async {
    await pump(tester, model: stored, onSubmit: (Member _) {});

    expect(input(tester, 2).controller.text, isEmpty);
    expect(find.textContaining('secret'), findsNothing);
    for (final Element e in find.byType(EditableText).evaluate()) {
      expect((e.widget as EditableText).controller.text,
          isNot(contains('secret')));
    }
  });

  testWidgets('an edit says that leaving it empty keeps the current value',
      (WidgetTester tester) async {
    await pump(tester, model: stored, onSubmit: (Member _) {});
    expect(find.text('Leave empty to keep the current value'), findsOneWidget);
  });

  testWidgets('a new record is not told about a current value it lacks',
      (WidgetTester tester) async {
    await pump(tester, onSubmit: (Member _) {});
    expect(find.text('Leave empty to keep the current value'), findsNothing);
    expect(input(tester, 2).obscureText, isTrue);
  });

  testWidgets('left empty, an edit keeps the stored value',
      (WidgetTester tester) async {
    Member? submitted;
    await pump(tester, model: stored, onSubmit: (Member v) => submitted = v);

    await tester.enterText(find.byType(EditableText).at(1), 'Ada L.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(submitted!.name, 'Ada L.');
    expect(submitted!.passwordHash, stored.passwordHash);
  });

  testWidgets('typed into and then cleared, it still keeps the stored value',
      (WidgetTester tester) async {
    Member? submitted;
    await pump(tester, model: stored, onSubmit: (Member v) => submitted = v);

    await tester.enterText(find.byType(EditableText).at(2), 'oops');
    await tester.enterText(find.byType(EditableText).at(2), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(submitted!.passwordHash, stored.passwordHash);
  });

  testWidgets('a value typed into it is what the form saves',
      (WidgetTester tester) async {
    Member? submitted;
    await pump(tester, model: stored, onSubmit: (Member v) => submitted = v);

    await tester.enterText(find.byType(EditableText).at(2), 'new-secret');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(submitted!.passwordHash, 'new-secret');
    // Saved, the input is empty again: the value is not read back.
    expect(input(tester, 2).controller.text, isEmpty);
  });
}
