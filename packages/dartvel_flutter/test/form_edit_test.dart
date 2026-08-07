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
  void clearRegistries() {
    dvModelFactories.clear();
    dvModelSerializers.clear();
    dvModelDeserializers.clear();
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
