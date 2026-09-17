// The sign-in form's demo credentials belong to the demo only.
//
// Served by its own web-server, the app signs in against the accounts that
// server keeps, where maya@oakline.coffee does not exist: a form filled in
// with it offered a sign-in that could only fail.
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:dartvel_example/screens/sign_in_form.dart';
import 'package:dartvel_example/shop/account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester) => tester.pumpWidget(
  const MaterialApp(
    home: Scaffold(body: SignInForm(from: '/')),
  ),
);

String _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  tearDown(() {
    DVAuth.servedByOwnServer = const bool.fromEnvironment('DARTVEL_WEB_SERVER');
  });

  testWidgets('on its own server the form starts empty', (
    WidgetTester tester,
  ) async {
    DVAuth.servedByOwnServer = true;
    await _pump(tester);

    expect(_field(tester, 'sign-in-email'), isEmpty);
    expect(_field(tester, 'sign-in-password'), isEmpty);
    expect(find.textContaining('demo account'), findsNothing);
  });

  testWidgets('in the on-device demo the demo account is filled in', (
    WidgetTester tester,
  ) async {
    DVAuth.servedByOwnServer = false;
    await _pump(tester);

    expect(_field(tester, 'sign-in-email'), demoEmail);
    expect(_field(tester, 'sign-in-password'), demoPassword);
  });
}
