// A box with a tooltip, a long press and a double tap: the long press runs the
// box's own action. The tooltip is shown on hover and focus; a long press that
// the box answers is the box's, as it is on a pressable with a tap.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final (String, bool, bool) shape in const <(String, bool, bool)>[
    ('long press only', false, false),
    ('with a double tap', true, false),
    ('with a tap', false, true),
    ('with a tap and a double tap', true, true),
  ]) {
    testWidgets('a long press on a box with a tooltip runs onLongPress (${shape.$1})', (WidgetTester tester) async {
      int longPresses = 0;
      DVModifier modifier = DVModifier().tooltip('Long-press for settings');
      if (shape.$2) modifier = modifier.onDoubleTap(() {});
      if (shape.$3) modifier = modifier.onTap(() {});
      modifier = modifier.onLongPress(() => longPresses++);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: DVBox.list(<Widget>[const DVText('12:06'), const DVText('Tue')], modifier: modifier))),
      ));
      await tester.longPress(find.text('12:06'));
      await tester.pumpAndSettle();
      expect(longPresses, 1);
    });
  }
}
