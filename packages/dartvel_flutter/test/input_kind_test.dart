// `.input(kind: ...)` says what a field holds, and the keyboard follows.
//
// Every field opened the letter keyboard and offered no autofill, so a phone
// number or a price was typed on the wrong keyboard and a sign-in field was
// never filled by the phone's password manager. A kind sets the keyboard, the
// autofill hints and, on web, the input's type, inputmode and autocomplete.
// A field that names no kind is what it always was.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<TextField> _field(WidgetTester tester, DVInputKind? kind) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: DVText('').modifier(
        kind == null
            ? DVModifier().input(label: 'Field')
            : DVModifier().input(label: 'Field', kind: kind),
      ),
    ),
  ));
  return tester.widget<TextField>(find.byType(TextField));
}

void main() {
  testWidgets('no kind leaves the keyboard and autofill as they were', (WidgetTester tester) async {
    final TextField field = await _field(tester, null);
    // TextField resolves an unset keyboard to the plain one.
    expect(field.keyboardType, TextInputType.text);
    expect(field.autofillHints, isNull);
    expect(field.obscureText, isFalse);
  });

  testWidgets('text is the plain keyboard, with no hints', (WidgetTester tester) async {
    final TextField field = await _field(tester, DVInputKind.text);
    expect(field.keyboardType, TextInputType.text);
    expect(field.autofillHints, isNull);
  });

  testWidgets('email', (WidgetTester tester) async {
    final TextField field = await _field(tester, DVInputKind.email);
    expect(field.keyboardType, TextInputType.emailAddress);
    expect(field.autofillHints, <String>[AutofillHints.email]);
  });

  testWidgets('phone opens the dial pad', (WidgetTester tester) async {
    final TextField field = await _field(tester, DVInputKind.phone);
    expect(field.keyboardType, TextInputType.phone);
    expect(field.autofillHints, <String>[AutofillHints.telephoneNumber]);
  });

  testWidgets('number is digits only, decimal also takes a point', (WidgetTester tester) async {
    expect((await _field(tester, DVInputKind.number)).keyboardType, TextInputType.number);
    expect(
      (await _field(tester, DVInputKind.decimal)).keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
  });

  testWidgets('url', (WidgetTester tester) async {
    final TextField field = await _field(tester, DVInputKind.url);
    expect(field.keyboardType, TextInputType.url);
    expect(field.autofillHints, <String>[AutofillHints.url]);
  });

  testWidgets('a password kind hides the text and asks for the saved password', (WidgetTester tester) async {
    final TextField field = await _field(tester, DVInputKind.password);
    expect(field.obscureText, isTrue);
    expect(field.autofillHints, <String>[AutofillHints.password]);
  });

  testWidgets('a new password kind hides the text and asks for a new one', (WidgetTester tester) async {
    final TextField field = await _field(tester, DVInputKind.newPassword);
    expect(field.obscureText, isTrue);
    expect(field.autofillHints, <String>[AutofillHints.newPassword]);
  });

  testWidgets('name capitalises words, street address has its own keyboard', (WidgetTester tester) async {
    final TextField name = await _field(tester, DVInputKind.name);
    expect(name.keyboardType, TextInputType.name);
    expect(name.textCapitalization, TextCapitalization.words);
    expect(name.autofillHints, <String>[AutofillHints.name]);
    final TextField street = await _field(tester, DVInputKind.streetAddress);
    expect(street.keyboardType, TextInputType.streetAddress);
    expect(street.autofillHints, <String>[AutofillHints.fullStreetAddress]);
  });

  testWidgets('a one-time code is digits and is filled from the message', (WidgetTester tester) async {
    final TextField field = await _field(tester, DVInputKind.oneTimeCode);
    expect(field.keyboardType, TextInputType.number);
    expect(field.autofillHints, <String>[AutofillHints.oneTimeCode]);
  });

  testWidgets('a kind survives a merge with another modifier', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DVText('').modifier(
          DVModifier().input(label: 'Phone', kind: DVInputKind.phone).merge(DVModifier().fontSize(14)),
        ),
      ),
    ));
    expect(tester.widget<TextField>(find.byType(TextField)).keyboardType, TextInputType.phone);
  });
}
