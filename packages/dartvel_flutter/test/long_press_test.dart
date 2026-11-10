// .onLongPress(): the second thing a control does, as a launcher's app icon
// opens on tap and offers pin/info/uninstall on a long press. The long press
// is the action's, not the tooltip's (which still shows on hover and focus),
// and a screen reader is offered it as a second action.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a long press runs the action, and a tap still taps', (WidgetTester tester) async {
    int taps = 0;
    int longPresses = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DVText('Termux').modifier(DVModifier().onTap(() => taps++).onLongPress(() => longPresses++)),
      ),
    ));
    await tester.longPress(find.text('Termux'));
    await tester.pumpAndSettle();
    expect(longPresses, 1);
    expect(taps, 0);
    expect(find.byType(Tooltip).hitTestable(), findsWidgets);
    expect(tester.widgetList<Tooltip>(find.byType(Tooltip)).every((Tooltip tip) => tip.triggerMode == TooltipTriggerMode.manual), isTrue,
        reason: 'the tooltip must not take the long press from the action');
    await tester.tap(find.text('Termux'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('a screen reader is offered the long press', (WidgetTester tester) async {
    int longPresses = 0;
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DVBox(const Icon(Icons.apps), DVModifier().tooltip('All apps').onTap(() {}).onLongPress(() => longPresses++)),
      ),
    ));
    final SemanticsNode node = tester.getSemantics(find.bySemanticsLabel('All apps'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);
    tester.binding.pipelineOwner.semanticsOwner!.performAction(node.id, SemanticsAction.longPress);
    await tester.pump();
    expect(longPresses, 1);
    semantics.dispose();
  });

  testWidgets('without a long press, the tooltip keeps it', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DVText('Open').modifier(DVModifier().onTap(() {})))));
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).triggerMode, TooltipTriggerMode.longPress);
  });
}
