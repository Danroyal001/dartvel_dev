// A password manager saves and fills the prebuilt sign-in and sign-up pages.
//
// A browser or a password manager offers to save a password when a form it
// recognises -- a username field and a password field, together -- is
// submitted, and fills that form next time. The prebuilt pages had neither:
// the sign-in fields said nothing about what they were, each field was a
// form of its own, and nothing told the platform a sign-in had succeeded, so
// nothing was ever offered for saving. Now both fields are one autofill group
// with the hints the platform matches on, Enter in the password field signs
// in, and the platform is told to save only once the server has accepted the
// password -- a wrong one is never offered for saving.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every `TextInput.finishAutofillContext` the page sent, by its shouldSave.
List<bool> saves(WidgetTester tester) => <bool>[
      for (final MethodCall call in tester.testTextInput.log)
        if (call.method == 'TextInput.finishAutofillContext')
          call.arguments as bool,
    ];

AutofillGroupState? groupOf(WidgetTester tester, String key) {
  final Finder field = find.byKey(ValueKey<String>(key));
  final Finder group =
      find.ancestor(of: field, matching: find.byType(AutofillGroup));
  if (group.evaluate().isEmpty) return null;
  return tester.state<AutofillGroupState>(group.first);
}

List<String> hintsOf(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey<String>(key))).autofillHints
        ?.toList() ??
    const <String>[];

void main() {
  setUp(() {
    DV.Auth.configure(DVLocalAuthProvider());
    DV.Test.fakeDatabase();
  });

  group('sign in', () {
    testWidgets('the email and password are one form, named for what they are',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          MaterialApp(home: DV.Auth.SignInWithEmailAndPasswordPage()));

      final AutofillGroupState? email = groupOf(tester, 'dv-auth-email');
      expect(email, isNotNull);
      expect(identical(email, groupOf(tester, 'dv-auth-password')), isTrue);
      expect(hintsOf(tester, 'dv-auth-email'),
          containsAll(<String>[AutofillHints.username, AutofillHints.email]));
      expect(hintsOf(tester, 'dv-auth-password'), <String>[AutofillHints.password]);
    });

    testWidgets('Enter in the password signs in, and the password is saved',
        (WidgetTester tester) async {
      await DV.Auth.signUp(email: 'ada@example.com', password: 'correct horse');
      await DV.Auth.signOut();
      await tester.pumpWidget(
          MaterialApp(home: DV.Auth.SignInWithEmailAndPasswordPage()));

      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-auth-email')), 'ada@example.com');
      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-auth-password')), 'correct horse');
      await tester.testTextInput.receiveAction(.done);
      await tester.pumpAndSettle();

      expect(DV.Auth.currentUser?.email, 'ada@example.com');
      expect(saves(tester), contains(true));
    });

    testWidgets('a refused password is never offered for saving',
        (WidgetTester tester) async {
      await DV.Auth.signUp(email: 'ada@example.com', password: 'correct horse');
      await DV.Auth.signOut();
      await tester.pumpWidget(
          MaterialApp(home: DV.Auth.SignInWithEmailAndPasswordPage()));

      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-auth-email')), 'ada@example.com');
      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-auth-password')), 'wrong');
      await tester.tap(find.byKey(const ValueKey<String>('dv-auth-submit')));
      await tester.pumpAndSettle();
      expect(DV.Auth.currentUser, isNull);

      // Leaving the page is not a sign-in either.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(saves(tester), isNot(contains(true)));
    });
  });

  group('sign up', () {
    testWidgets('the fields are one form, and the new password is saved',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: DV.Auth.SignUpPage()));

      final AutofillGroupState? email = groupOf(tester, 'dv-signup-email');
      expect(email, isNotNull);
      expect(identical(email, groupOf(tester, 'dv-signup-password')), isTrue);
      expect(hintsOf(tester, 'dv-signup-email'),
          containsAll(<String>[AutofillHints.username, AutofillHints.email]));

      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-signup-email')), 'grace@example.com');
      await tester.enterText(find.byKey(const ValueKey<String>('dv-signup-password')),
          'a long enough passphrase');
      await tester.testTextInput.receiveAction(.done);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('dv-signup-done')), findsOneWidget);
      expect(saves(tester), contains(true));
    });
  });
}
