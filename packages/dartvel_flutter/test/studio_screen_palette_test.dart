// The command palette and the formula bar in Studio itself: Ctrl+K reaches
// the sections, the page's elements and what can be inserted, and the
// formula bar edits what is selected.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/studio/studio_command_palette.dart';
import 'package:dartvel_flutter/src/studio/studio_formula_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

Future<void> palette(WidgetTester tester, String query) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(DVStudioCommandPalette.searchKey), query);
  await tester.pump();
  await tester.testTextInput.receiveAction(.go);
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

  testWidgets('Ctrl+K goes to a section', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await palette(tester, 'go to data');
    expect(find.text('the data section'), findsOneWidget);
  });

  testWidgets('in the editor it inserts, selects and the formula bar edits',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, '/menu');
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-create')));
    await tester.pumpAndSettle();
    expect(find.byType(DVStudioFormulaBar), findsOneWidget);

    await palette(tester, 'insert text');
    final TextField bar =
        tester.widget<TextField>(find.byKey(DVStudioFormulaBar.inputKey));
    // Inserting selects what was inserted, so the bar shows its text.
    expect(bar.controller!.text, '"Text"');

    await tester.enterText(find.byKey(DVStudioFormulaBar.inputKey), '"Today\'s menu"');
    await tester.testTextInput.receiveAction(.done);
    await tester.pumpAndSettle();
    expect(find.text("Today's menu"), findsWidgets);

    await palette(tester, 'duplicate');
    expect(find.text("Today's menu"), findsNWidgets(3));
  });
}
