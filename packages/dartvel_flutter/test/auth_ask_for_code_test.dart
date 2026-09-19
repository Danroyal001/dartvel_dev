// DV.Auth.askForCode(): the other half of DV.Auth.code().
//
// An application that mails a code then has to ask for it back, and every one
// of them was building the same boxes, the same paste handling and the same
// "that code is wrong" line. As a modal over whatever is on screen, or as a
// whole page for a flow that has one.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> typeCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(EditableText).first, code);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the modal answers with the code that was typed',
      (WidgetTester tester) async {
    late Future<String?> asked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => asked = DV.Auth.askForCode(context),
          child: const Text('ask'),
        ),
      ),
    ));

    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your code'), findsOneWidget);

    await typeCode(tester, '123456');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(await asked, '123456');
  });

  testWidgets('it says when the code is wrong, and lets them try again',
      (WidgetTester tester) async {
    late Future<String?> asked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => asked = DV.Auth.askForCode(
            context,
            verify: (String code) async =>
                code == '654321' ? null : 'That code is wrong.',
          ),
          child: const Text('ask'),
        ),
      ),
    ));
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();

    await typeCode(tester, '111111');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('That code is wrong.'), findsOneWidget);
    expect(find.text('Enter your code'), findsOneWidget,
        reason: 'a wrong code keeps the dialog open');

    await typeCode(tester, '654321');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(await asked, '654321');
  });

  testWidgets('dismissing it answers with nothing',
      (WidgetTester tester) async {
    late Future<String?> asked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => asked = DV.Auth.askForCode(context),
          child: const Text('ask'),
        ),
      ),
    ));
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await asked, isNull);
  });

  testWidgets('it takes only digits, and only as many as the code has',
      (WidgetTester tester) async {
    late Future<String?> asked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => asked = DV.Auth.askForCode(context, length: 4),
          child: const Text('ask'),
        ),
      ),
    ));
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();

    await typeCode(tester, '12ab3456');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(await asked, '1234');
  });

  testWidgets('the page asks for the same thing, without a dialog',
      (WidgetTester tester) async {
    String? answered;
    await tester.pumpWidget(MaterialApp(
      home: DV.Auth.AskForCodePage(
        message: 'We sent a code to ada@example.com.',
        onCode: (String code) async => answered = code,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('We sent a code to ada@example.com.'), findsOneWidget);
    await typeCode(tester, '246813');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(answered, '246813');
  });
}
