// Switch control and hardware-key navigation.
//
// A kiosk or an embedded device is often driven by something other than a
// touchscreen: one or two switches, a TV remote's D-pad, a keypad. What the
// tests hold to: with switch control on, one key steps focus through the
// page in traversal order and wraps, another activates what is focused, and
// auto-scan does the stepping on a timer for a single-switch user; a remote's
// D-pad and select key navigate and activate without any of that; the
// generated toggle turns switch control on and off; and none of it fires
// while switch control is off, so an ordinary keyboard user is not hijacked.

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Three buttons that record their presses.
Widget buttons(List<String> pressed, {DVSwitchControlSettings? settings, Duration? autoScan}) =>
    DVSwitchControl(
      settings: settings,
      autoScan: autoScan,
      child: Column(
        children: <Widget>[
          for (final String name in <String>['one', 'two', 'three'])
            ElevatedButton(
              key: ValueKey<String>('btn-$name'),
              onPressed: () => pressed.add(name),
              child: Text(name),
            ),
        ],
      ),
    );

String? focused(WidgetTester tester) {
  final BuildContext? context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  final ElevatedButton? button = context.findAncestorWidgetOfExactType<ElevatedButton>() ??
      (context.widget is ElevatedButton ? context.widget as ElevatedButton : null);
  final Key? key = button?.key;
  return key is ValueKey<String> ? key.value : null;
}

void main() {
  setUp(() => DV.Accessibility.switchControl.reset());

  testWidgets('one key steps focus in order and wraps; another activates',
      (WidgetTester tester) async {
    final List<String> pressed = <String>[];
    DV.Accessibility.switchControl.enabled = true;
    await tester.pumpWidget(host(buttons(pressed)));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(focused(tester), 'btn-one');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(focused(tester), 'btn-two');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(pressed, <String>['two']);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(focused(tester), 'btn-one', reason: 'past the last, back to the first');
  });

  testWidgets('auto-scan steps on a timer for a single-switch user',
      (WidgetTester tester) async {
    final List<String> pressed = <String>[];
    DV.Accessibility.switchControl.enabled = true;
    await tester.pumpWidget(host(buttons(pressed, autoScan: const Duration(milliseconds: 200))));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 200));
    expect(focused(tester), 'btn-one');
    await tester.pump(const Duration(milliseconds: 200));
    expect(focused(tester), 'btn-two');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(pressed, <String>['two']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the switch keys are configurable', (WidgetTester tester) async {
    final List<String> pressed = <String>[];
    DV.Accessibility.switchControl.enabled = true;
    await tester.pumpWidget(host(buttons(
      pressed,
      settings: const DVSwitchControlSettings(
        next: LogicalKeyboardKey.f1,
        select: LogicalKeyboardKey.f2,
      ),
    )));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(focused(tester), isNull, reason: 'space is not a switch here');
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pump();
    expect(focused(tester), 'btn-one');
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    expect(pressed, <String>['one']);
  });

  testWidgets('off, the keys are left to the page', (WidgetTester tester) async {
    final List<String> pressed = <String>[];
    await tester.pumpWidget(host(buttons(pressed)));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(focused(tester), isNull);
    expect(pressed, isEmpty);
  });

  testWidgets("a remote's D-pad and select navigate and activate without switch control",
      (WidgetTester tester) async {
    final List<String> pressed = <String>[];
    await tester.pumpWidget(host(DVHardwareKeys(child: buttons(pressed))));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focused(tester), 'btn-one');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focused(tester), 'btn-two');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focused(tester), 'btn-one');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(pressed, <String>['one']);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pump();
    expect(pressed, <String>['one', 'one']);
  });

  testWidgets('the generated toggle turns switch control on and off',
      (WidgetTester tester) async {
    await tester.pumpWidget(host(const DVAccessibilityToggle()));
    await tester.pump();
    expect(DV.Accessibility.switchControl.enabled, isFalse);

    await tester.tap(find.byKey(const ValueKey<String>('dv-accessibility-toggle')));
    await tester.pump();
    expect(DV.Accessibility.switchControl.enabled, isTrue);
    expect(find.textContaining('on'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('dv-accessibility-toggle')));
    await tester.pump();
    expect(DV.Accessibility.switchControl.enabled, isFalse);
  });

  test('the keys accessibility needs are never the ones a kiosk blocks', () {
    // Kiosk blocks escape, never access: whatever else input.hardwareKeys:
    // block covers, stepping, activating and the platform's accessibility
    // shortcut get through.
    for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.tab,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
    ]) {
      expect(DVAccessibilityKeys.isExempt(<LogicalKeyboardKey>{key}), isTrue, reason: '$key');
    }
    expect(DVAccessibilityKeys.isExempt(DVAccessibilityKeys.platformShortcut), isTrue);
    for (final Set<LogicalKeyboardKey> combo in <Set<LogicalKeyboardKey>>[
      <LogicalKeyboardKey>{LogicalKeyboardKey.altLeft, LogicalKeyboardKey.tab},
      <LogicalKeyboardKey>{LogicalKeyboardKey.altLeft, LogicalKeyboardKey.f4},
      <LogicalKeyboardKey>{LogicalKeyboardKey.metaLeft},
      <LogicalKeyboardKey>{LogicalKeyboardKey.escape},
    ]) {
      expect(DVAccessibilityKeys.isExempt(combo), isFalse, reason: '$combo');
    }
  });
}
