// Studio on a phone.
//
// Studio is where somebody who does not write code runs their site, and they
// have a phone in their hand more often than a laptop. The editor laid its
// panels, canvas and inspector side by side, 264 + 300 points of fixed panels
// before the canvas had any, so on a 390-point phone it overflowed by 154 and
// the inspector was out of reach. On a phone the sections move to a bar along
// the bottom, and the editor shows one pane at a time -- Elements, Page or
// Style -- chosen from a bar of its own.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host() => MaterialApp(
      home: Material(
        child: DVStudioScreen(
          sections: <DVStudioSection>[
            DVStudioSection(
              id: 'data',
              label: 'Data',
              icon: DVStudioIcons.page,
              build: (BuildContext context) => const Text('the data section'),
            ),
          ],
        ),
      ),
    );

Future<void> atSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host());
  await tester.pumpAndSettle();
}

Future<void> openPage(WidgetTester tester) async {
  await tester.enterText(find.byType(EditableText).first, '/menu');
  await tester.tap(find.byKey(const ValueKey<String>('dv-studio-create')));
  await tester.pumpAndSettle();
}

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
  });

  tearDown(() {
    database.close();
    DVPageStore.resetCache();
  });

  for (final Size size in const <Size>[
    Size(320, 640),
    Size(390, 844),
    Size(844, 390),
  ]) {
    testWidgets('home and the editor fit ${size.width.toInt()} by '
        '${size.height.toInt()}', (WidgetTester tester) async {
      await atSize(tester, size);
      expect(tester.takeException(), isNull);

      await openPage(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('on a phone the sections are a bar along the bottom',
      (WidgetTester tester) async {
    await atSize(tester, const Size(390, 844));

    final Finder bar =
        find.byKey(const ValueKey<String>('dv-studio-bottom-bar'));
    expect(bar, findsOneWidget);
    expect(tester.getBottomLeft(bar).dy, 844);
    expect(find.byKey(const ValueKey<String>('dv-studio-rail')), findsNothing);

    await tester.tap(find.descendant(of: bar, matching: find.text('Data')));
    await tester.pumpAndSettle();
    expect(find.text('the data section'), findsOneWidget);
  });

  testWidgets('on a laptop the sections stay a rail down the left',
      (WidgetTester tester) async {
    await atSize(tester, const Size(1440, 900));

    expect(find.byKey(const ValueKey<String>('dv-studio-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('dv-studio-bottom-bar')),
        findsNothing);
  });

  testWidgets('the phone editor shows one pane at a time',
      (WidgetTester tester) async {
    await atSize(tester, const Size(390, 844));
    await openPage(tester);

    Finder pane(String name) =>
        find.byKey(ValueKey<String>('dv-studio-pane-$name'));
    // The page first: it is what somebody opened the editor to see.
    expect(find.byType(DVStudioCanvas), findsOneWidget);
    expect(find.byType(DVStudioInspector), findsNothing);

    await tester.tap(pane('elements'));
    await tester.pumpAndSettle();
    expect(find.byType(DVStudioCanvas), findsNothing);
    // Adding an element goes back to the page, where it can be seen.
    await tester.tap(find.text('Text').first);
    await tester.pumpAndSettle();
    expect(find.byType(DVStudioCanvas), findsOneWidget);

    await tester.tap(pane('style'));
    await tester.pumpAndSettle();
    expect(find.byType(DVStudioInspector), findsOneWidget);
    expect(find.byType(DVStudioCanvas), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
