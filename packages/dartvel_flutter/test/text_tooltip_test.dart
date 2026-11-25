// `.tooltip()` on a DVText that is not pressable: a text field, or a status
// word. 3.47.7 dropped it in both cases (the box half is built with the
// interaction cleared, and the text half never drew one), so a field named
// with a tooltip showed nothing on hover and apps wrapped it by hand.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 320, child: child))));

Future<void> _hover(WidgetTester tester, Finder finder) async {
  final TestGesture mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await tester.pump();
  await mouse.moveTo(tester.getCenter(finder));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('a text field keeps its tooltip and shows it on hover', (WidgetTester tester) async {
    await tester.pumpWidget(_app(DVText('').modifier(
          DVModifier().input(hint: 'Ada', onChanged: (_) {}).semanticLabel('Business name').tooltip('Your business name, shown at the top'),
        )));
    expect(find.byTooltip('Your business name, shown at the top'), findsOneWidget);
    await _hover(tester, find.byType(TextField));
    expect(find.text('Your business name, shown at the top'), findsOneWidget);
  });

  testWidgets('a text field with box styling keeps its tooltip too', (WidgetTester tester) async {
    await tester.pumpWidget(_app(DVText('').modifier(
          DVModifier().input(onChanged: (_) {}).padding(8).tooltip('Phone number'),
        )));
    expect(find.byTooltip('Phone number'), findsOneWidget);
  });

  testWidgets('a long press in a text field still selects, not the tooltip', (WidgetTester tester) async {
    await tester.pumpWidget(_app(DVText('').modifier(
          DVModifier().input(onChanged: (_) {}).tooltip('Phone number'),
        )));
    final Tooltip tooltip = tester.widget<Tooltip>(find.byTooltip('Phone number'));
    expect(tooltip.triggerMode, TooltipTriggerMode.manual);
  });

  testWidgets('a status word that is not pressable shows its tooltip', (WidgetTester tester) async {
    await tester.pumpWidget(_app(DVText('Paid').modifier(DVModifier().tooltip('Payment received on 3 May'))));
    expect(find.byTooltip('Payment received on 3 May'), findsOneWidget);
  });

  testWidgets('a pressable text still has exactly one tooltip', (WidgetTester tester) async {
    await tester.pumpWidget(_app(DVText('Save').modifier(DVModifier().tooltip('Save the draft').onTap(() {}))));
    expect(find.byTooltip('Save the draft'), findsOneWidget);
  });
}
