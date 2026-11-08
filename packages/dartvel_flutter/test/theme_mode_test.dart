import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => DV.Theme.setMode(.system));

  test('DV.Theme tells its listeners when the mode changes, and only then', () {
    int heard = 0;
    void listener() => heard++;
    DV.Theme.addListener(listener);
    addTearDown(() => DV.Theme.removeListener(listener));
    DV.Theme.setMode(.dark);
    DV.Theme.setMode(.dark);
    expect(heard, 1);
    DV.Theme.setMode(.light);
    expect(heard, 2);
  });

  testWidgets('an application listening to DV.Theme switches mode when it is set', (WidgetTester tester) async {
    DV.Theme.setMode(.light);
    await tester.pumpWidget(ListenableBuilder(
      listenable: DV.Theme,
      builder: (BuildContext context, Widget? child) => MaterialApp(
        theme: dartvelDefaultTheme(.light),
        darkTheme: dartvelDefaultTheme(.dark),
        themeMode: DV.Theme.mode,
        home: DVBox(const SizedBox(width: 10, height: 10), DVModifier().backgroundColor(DVColor.surface)),
      ),
    ));
    Color painted() => (tester.widget<Container>(find.byType(Container).last).decoration! as BoxDecoration).color!;
    expect(painted().toARGB32(), 0xFFFFFFFF);
    DV.Theme.setMode(.dark);
    await tester.pumpAndSettle();
    expect(painted().toARGB32(), 0xFF0A0D13);
  });
}
