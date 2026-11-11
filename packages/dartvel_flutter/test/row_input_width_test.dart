// A text field beside a label in a row had no width limit, and Flutter's
// TextField throws without one: Dev Launcher's command line (a prompt sign,
// then the field) failed layout. In a row an input takes the room left.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an input in a row takes the remaining width', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DVBox.row([
          DVText('>'),
          DVText('').modifier(DVModifier().input(label: 'Command')),
        ], spacing: 10),
      ),
    ));
    expect(tester.takeException(), isNull);
    final double width = tester.getSize(find.byType(TextField)).width;
    expect(width, greaterThan(300));
  });

  testWidgets('also in a row aligned to the start', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DVBox.row([
          DVText('>'),
          DVText('').modifier(DVModifier().input(label: 'Command')),
        ], spacing: 10, crossAlign: DVCrossAlign.start),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(TextField)).width, greaterThan(300));
  });
}
