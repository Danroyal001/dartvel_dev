import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every app's sign-in looked the same: one card on the left, the form on the
/// right, only the colours changed. An app now draws the whole screen around
/// the framework's form (which keeps the sign-in logic, second factor and
/// password-manager handling in one place), names its own pages, and the
/// sign-in form links to the app's password reset when it has one.
void main() {
  testWidgets('frameBuilder draws the screen around the form', (tester) async {
    DVAuthScreen? seen;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DVAuthFrame(
          screen: DVAuthScreen.signIn,
          appearance: DVAuthAppearance(
            name: 'Kitchen',
            frameBuilder: (context, screen, form) {
              seen = screen;
              return Column(children: <Widget>[const Text('Today\'s menu'), Expanded(child: form)]);
            },
          ),
          children: const <Widget>[Text('the form')],
        ),
      ),
    ));
    expect(seen, DVAuthScreen.signIn);
    expect(find.text('Today\'s menu'), findsOneWidget);
    expect(find.text('the form'), findsOneWidget);
    expect(find.byKey(const ValueKey('dv-auth-brand-panel')), findsNothing);
  });

  test('titles fall back to the framework wording', () {
    const DVAuthAppearance plain = DVAuthAppearance();
    const DVAuthAppearance named = DVAuthAppearance(signInTitle: 'Unlock your vault', signUpTitle: 'Open a vault');
    expect(plain.titleFor(DVAuthScreen.signIn), 'Sign in to your account');
    expect(plain.titleFor(DVAuthScreen.signUp), 'Create an account');
    expect(named.titleFor(DVAuthScreen.signIn), 'Unlock your vault');
    expect(named.titleFor(DVAuthScreen.signUp), 'Open a vault');
  });

  testWidgets('a narrow default frame still shows the brand, not a bare name', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DVAuthFrame(
          appearance: DVAuthAppearance(name: 'Elena', tagline: 'Your home and your servers.'),
          children: <Widget>[Text('the form')],
        ),
      ),
    ));
    expect(find.text('Elena'), findsOneWidget);
    expect(find.text('Your home and your servers.'), findsOneWidget);
  });
}
