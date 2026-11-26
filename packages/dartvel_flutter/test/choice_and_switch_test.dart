// DVChoice and DVSwitch: picking one of a few values, and turning one thing
// on or off, as Dartvel primitives. Keyboard, screen reader and large text
// work, and both take the modifier chain.
@TestOn('vm')
library;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Size { standard, large, larger }

String _name(_Size size) => switch (size) { _Size.standard => 'Default', _Size.large => 'Large', _Size.larger => 'Larger' };

Widget _host(Widget child, {double textScale = 1, double width = 800}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 844), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: width, child: child))),
      ),
    );

void main() {
  group('DVChoice chips', () {
    testWidgets('shows every option and reports the one picked', (WidgetTester tester) async {
      _Size picked = _Size.standard;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => DVChoice<_Size>(
          options: _Size.values,
          selected: picked,
          name: _name,
          optionTooltip: (_Size size) => '${_name(size)} text',
          label: 'Text size',
          onChanged: (_Size next) => setState(() => picked = next),
        ),
      )));
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Larger'), findsOneWidget);
      await tester.tap(find.text('Large'));
      await tester.pumpAndSettle();
      expect(picked, _Size.large);
      expect(find.byTooltip('Larger text'), findsOneWidget);
    });

    testWidgets('each option is a selectable button a screen reader hears, in a named group', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(DVChoice<_Size>(options: _Size.values, selected: _Size.large, name: _name, label: 'Text size', onChanged: (_) {})));
      final SemanticsNode large = tester.getSemantics(find.text('Large'));
      expect(large.getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
      expect(large.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(tester.getSemantics(find.text('Default')).getSemanticsData().flagsCollection.isSelected, Tristate.isFalse);
      expect(find.bySemanticsLabel('Text size'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the keyboard reaches and picks an option', (WidgetTester tester) async {
      _Size? picked;
      await tester.pumpWidget(_host(DVChoice<_Size>(options: _Size.values, selected: _Size.standard, name: _name, onChanged: (_Size next) => picked = next)));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(picked, _Size.large);
    });

    testWidgets('wraps rather than overflows at twice the text size on a phone', (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        DVChoice<_Size>(options: _Size.values, selected: _Size.larger, name: (_Size s) => '${_name(s)} reading size', onChanged: (_) {}),
        textScale: 2,
        width: 390,
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('takes the modifier chain', (WidgetTester tester) async {
      await tester.pumpWidget(_host(DVChoice<_Size>(options: _Size.values, selected: _Size.standard, name: _name, onChanged: (_) {}).paddingOnly(top: 24)));
      expect(find.byWidgetPredicate((Widget w) => w is Padding && w.padding == const EdgeInsets.only(top: 24)), findsOneWidget);
    });
  });

  group('DVChoice menu', () {
    testWidgets('shows the selected name under its label and picks from the opened list', (WidgetTester tester) async {
      _Size picked = _Size.standard;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => DVChoice<_Size>(
          options: _Size.values,
          selected: picked,
          name: _name,
          label: 'Reading size',
          style: DVChoiceStyle.menu,
          onChanged: (_Size next) => setState(() => picked = next),
        ),
      )));
      expect(find.text('Reading size'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Larger'), findsNothing);
      await tester.tap(find.text('Default'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Larger').last);
      await tester.pumpAndSettle();
      expect(picked, _Size.larger);
      expect(find.text('Larger'), findsOneWidget);
    });

    testWidgets('fits a phone at twice the text size', (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        DVChoice<_Size>(options: _Size.values, selected: _Size.larger, name: (_Size s) => '${_name(s)} with a long name that would not fit', label: 'Reading size', style: DVChoiceStyle.menu, onChanged: (_) {}),
        textScale: 2,
        width: 390,
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('DVSwitch', () {
    testWidgets('a tap anywhere on the row turns it on, and the switch says so', (WidgetTester tester) async {
      bool on = false;
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => DVSwitch(
          label: 'High contrast',
          explanation: 'Pure black and white with strong outlines.',
          value: on,
          onChanged: (bool next) => setState(() => on = next),
        ),
      )));
      await tester.tap(find.text('Pure black and white with strong outlines.'));
      await tester.pumpAndSettle();
      expect(on, isTrue);
      final SemanticsNode node = tester.getSemantics(find.byType(DVSwitch));
      expect(node.label, 'High contrast');
      expect(node.hint, 'Pure black and white with strong outlines.');
      expect(node.getSemanticsData().flagsCollection.isToggled, Tristate.isTrue);
      expect(find.byTooltip('High contrast'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the keyboard reaches it once and toggles it', (WidgetTester tester) async {
      bool on = false;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => Column(children: <Widget>[
          DVSwitch(label: 'Reduce motion', value: on, onChanged: (bool next) => setState(() => on = next)),
          TextButton(onPressed: () {}, child: const Text('After')),
        ]),
      )));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(on, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final BuildContext? focused = FocusManager.instance.primaryFocus?.context;
      expect(focused?.findAncestorWidgetOfExactType<TextButton>(), isNotNull, reason: 'one tab stop: the second tab leaves the row');
    });

    testWidgets('without onChanged it is shown as given and cannot be changed', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(const DVSwitch(label: 'Reduce motion', explanation: 'Already on, because your device asks for less motion.', value: true)));
      await tester.tap(find.text('Reduce motion'));
      await tester.pumpAndSettle();
      final SemanticsNode node = tester.getSemantics(find.byType(DVSwitch));
      expect(node.getSemanticsData().flagsCollection.isToggled, Tristate.isTrue);
      expect(node.getSemanticsData().flagsCollection.isEnabled, Tristate.isFalse);
      semantics.dispose();
    });

    testWidgets('wraps its words at twice the text size on a phone', (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        DVSwitch(label: 'High contrast for every page', explanation: 'Pure black and white with strong outlines on every control.', value: false, onChanged: (_) {}),
        textScale: 2,
        width: 390,
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('takes the modifier chain', (WidgetTester tester) async {
      await tester.pumpWidget(_host(DVSwitch(label: 'Reduce motion', value: false, onChanged: (_) {}).paddingOnly(top: 12)));
      expect(find.byWidgetPredicate((Widget w) => w is Padding && w.padding == const EdgeInsets.only(top: 12)), findsOneWidget);
    });
  });
}
