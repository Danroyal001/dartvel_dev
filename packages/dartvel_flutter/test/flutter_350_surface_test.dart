// Flutter 3.50's new runtime APIs, through Dartvel's own surface.
//
// - `barrierBuilder` (RawDialogRoute, 3.50) on `DV.Auth.askForCode`: an app
//   draws its own barrier, and Dartvel keeps the real one -- the tap that
//   dismisses, the "Dismiss" a screen reader announces -- whatever it draws.
// - `itemExtentBuilder` on separated lists (ListView.separated, 3.50) on
//   `DVBox.scrollableList`, counted in rows: Dartvel knows the gaps are
//   `spacing` tall and answers for them itself.
// - `AutofillHints.emailOTPCode` (3.50): a code that came by e-mail is
//   offered as one on Android; iOS and the web only know `oneTimeCode`
//   (`autocomplete="one-time-code"`), so they keep it.
import 'package:dartvel_core/dartvel.dart' show DVNotificationChannel;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget asker(void Function(BuildContext context) ask) => MaterialApp(
      home: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => ask(context),
          child: const Text('ask'),
        ),
      ),
    );

Iterable<String>? hintsOfTheCodeField(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).autofillHints;

void main() {
  group('askForCode barrierBuilder', () {
    testWidgets('draws what the app builds behind the dialog', (WidgetTester tester) async {
      await tester.pumpWidget(asker((BuildContext context) => DV.Auth.askForCode(
            context,
            barrierBuilder: (BuildContext context, RouteBarrierDetails details, Widget barrier) =>
                Stack(fit: .expand, children: <Widget>[
              barrier,
              const ColoredBox(key: ValueKey<String>('mine'), color: Color(0x2200FF00)),
            ]),
          )));
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('mine')), findsOneWidget);
      expect(find.text('Enter your code'), findsOneWidget);
    });

    testWidgets('a barrier that leaves the default out still dismisses, and is still announced',
        (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      String? answer = 'unset';
      await tester.pumpWidget(asker((BuildContext context) async {
        answer = await DV.Auth.askForCode(
          context,
          barrierBuilder: (BuildContext context, RouteBarrierDetails details, Widget barrier) =>
              const ColoredBox(key: ValueKey<String>('mine'), color: Color(0x88000000)),
        );
      }));
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('mine')), findsOneWidget,
          reason: 'the builder runs once');
      expect(find.bySemanticsLabel('Dismiss'), findsOneWidget);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Enter your code'), findsNothing);
      expect(answer, isNull);
      semantics.dispose();
    });

    testWidgets('without one, the dialog is the one it always was', (WidgetTester tester) async {
      await tester.pumpWidget(asker((BuildContext context) => DV.Auth.askForCode(context)));
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      final ModalBarrier barrier = tester.widget<ModalBarrier>(find.byType(ModalBarrier).last);
      expect(barrier.color, Colors.black54);
    });
  });

  group('scrollableList itemExtentBuilder', () {
    Widget list(double Function(int index, SliverLayoutDimensions dimensions) extent,
            {double spacing = 8}) =>
        MaterialApp(
          home: Scaffold(
            body: DVBox.scrollableList(
              <Widget>[for (int i = 0; i < 50; i++) Text('row $i')],
              spacing: spacing,
              itemExtentBuilder: extent,
            ),
          ),
        );

    testWidgets('every row takes the extent it is given, and the gaps stay spacing tall',
        (WidgetTester tester) async {
      await tester.pumpWidget(list((int index, SliverLayoutDimensions dimensions) => 40));
      expect(tester.getTopLeft(find.text('row 1')).dy - tester.getTopLeft(find.text('row 0')).dy,
          48);
      expect(tester.getTopLeft(find.text('row 2')).dy - tester.getTopLeft(find.text('row 1')).dy,
          48);
    });

    testWidgets('it is asked about rows, never about gaps or rows past the end',
        (WidgetTester tester) async {
      final Set<int> asked = <int>{};
      await tester.pumpWidget(list((int index, SliverLayoutDimensions dimensions) {
        asked.add(index);
        return index.isEven ? 30 : 60;
      }));
      await tester.drag(find.byType(Scrollable), const Offset(0, -100000));
      await tester.pumpAndSettle();
      expect(asked.every((int index) => index >= 0 && index < 50), isTrue);
      expect(asked, contains(49));
      expect(find.text('row 49'), findsOneWidget);
    });

    testWidgets('with no spacing it goes straight to the rows', (WidgetTester tester) async {
      await tester.pumpWidget(
          list((int index, SliverLayoutDimensions dimensions) => 25, spacing: 0));
      expect(tester.getTopLeft(find.text('row 3')).dy - tester.getTopLeft(find.text('row 2')).dy,
          25);
    });
  });

  group('one-time code autofill', () {
    testWidgets('an e-mailed code is offered as one on Android', (WidgetTester tester) async {
      await tester.pumpWidget(asker((BuildContext context) => DV.Auth.askForCode(context)));
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      expect(hintsOfTheCodeField(tester), <String>[AutofillHints.emailOTPCode]);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('a texted code is an SMS code on Android', (WidgetTester tester) async {
      await tester.pumpWidget(asker((BuildContext context) =>
          DV.Auth.askForCode(context, sentBy: DVNotificationChannel.sms)));
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      expect(hintsOfTheCodeField(tester), <String>[AutofillHints.oneTimeCode]);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('iOS only knows oneTimeCode, for mail and text alike', (WidgetTester tester) async {
      await tester.pumpWidget(asker((BuildContext context) => DV.Auth.askForCode(context)));
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      expect(hintsOfTheCodeField(tester), <String>[AutofillHints.oneTimeCode]);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('the page asks the same way', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: DV.Auth.AskForCodePage(onCode: (String code) async => null),
      ));
      expect(hintsOfTheCodeField(tester), <String>[AutofillHints.emailOTPCode]);
      await tester.pumpWidget(MaterialApp(
        home: DV.Auth.AskForCodePage(
            sentBy: DVNotificationChannel.sms, onCode: (String code) async => null),
      ));
      expect(hintsOfTheCodeField(tester), <String>[AutofillHints.oneTimeCode]);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
