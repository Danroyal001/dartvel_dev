// Everything hoverable has a tooltip, and the same words are its name.
//
// "We are not doing guess games": a control that is only a picture is a
// control a pointer user has to guess at and a screen reader cannot name. The
// framework makes the name a precondition of the control, not a courtesy.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void _nothing() {}

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
  group('an icon-only control named with .tooltip()', () {
    Widget settings() => DVBox(
          const Icon(Icons.settings),
          DVModifier().tooltip('Settings').onTap(_nothing),
        );

    testWidgets('shows its tooltip on mouse hover', (WidgetTester tester) async {
      await tester.pumpWidget(_app(settings()));
      await _hover(tester, find.byIcon(Icons.settings));
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('shows its tooltip on keyboard focus', (WidgetTester tester) async {
      await tester.pumpWidget(_app(settings()));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('shows its tooltip on a long press', (WidgetTester tester) async {
      await tester.pumpWidget(_app(settings()));
      await tester.longPress(find.byIcon(Icons.settings));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('is named for a screen reader with the same words', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(settings()));
      expect(find.bySemanticsLabel('Settings'), findsOneWidget);
      handle.dispose();
    });
  });

  group('a control that has text needs no extra argument', () {
    testWidgets('DVText takes its tooltip from its words', (WidgetTester tester) async {
      await tester.pumpWidget(_app(DVText("Save", DVModifier().onTap(_nothing))));
      await _hover(tester, find.text('Save'));
      expect(find.text('Save'), findsNWidgets(2));
    });

    testWidgets('a DVBox takes it from the text inside', (WidgetTester tester) async {
      await tester.pumpWidget(_app(DVBox.row(
        const <Widget>[Icon(Icons.shopping_cart), DVText('Cart')],
        modifier: DVModifier().onTap(_nothing),
      )));
      await _hover(tester, find.byIcon(Icons.shopping_cart));
      expect(find.text('Cart'), findsNWidgets(2));
    });
  });

  group('an icon-only control with no name is refused', () {
    testWidgets('and the error names this file and line', (WidgetTester tester) async {
      await tester.pumpWidget(_app(DVBox(
        const Icon(Icons.delete),
        DVModifier().onTap(_nothing),
      )));
      final Object? error = tester.takeException();
      expect(error, isNotNull);
      expect(error.toString(), contains('tooltip_required_test.dart:'));
      expect(error.toString(), contains('tooltip'));
    });
  });

  group('an icon-only control is a DVBox', () {
    testWidgets('its tooltip is the tooltip and the name', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(DVBox(
        const Icon(Icons.add),
        DVModifier().tooltip('Add item').onTap(_nothing),
      )));
      expect(find.bySemanticsLabel('Add item'), findsOneWidget);
      await _hover(tester, find.byIcon(Icons.add));
      expect(find.text('Add item'), findsOneWidget);
      handle.dispose();
    });
  });

  group('Studio draws its controls the same way', () {
    testWidgets('an enabled icon button shows its tooltip on hover and focus',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(DVStudioIconButton(
        icon: Icons.refresh,
        tooltip: 'Refresh the preview',
        onTap: _nothing,
      )));
      await _hover(tester, find.byIcon(Icons.refresh));
      expect(find.text('Refresh the preview'), findsOneWidget);
    });

    testWidgets('a text button shows its label as its tooltip', (WidgetTester tester) async {
      await tester.pumpWidget(_app(DVStudioControl(
        label: 'Create page',
        enabled: true,
        onTap: _nothing,
      )));
      await _hover(tester, find.text('Create page'));
      expect(find.text('Create page'), findsNWidgets(2));
    });
  });

  group('hover without a press', () {
    testWidgets('a badge with .tooltip() still says what it is', (WidgetTester tester) async {
      await tester.pumpWidget(_app(DVBox(
        const Icon(Icons.verified),
        DVModifier().tooltip('Verified account'),
      )));
      await _hover(tester, find.byIcon(Icons.verified));
      expect(find.text('Verified account'), findsOneWidget);
    });
  });

  group('a page node linked in Studio', () {
    test('is named by its words, else by where it goes', () {
      final DVPageNode image = DVPageNode(
        id: 'a',
        type: 'image',
        action: <String, Object?>{'type': 'navigate', 'to': '/pricing'},
      );
      expect(dvStudioActionName(image, <String, Object?>{}), 'Go to /pricing');
      expect(dvStudioActionName(image, <String, Object?>{'alt': 'Pricing table'}),
          'Pricing table');
    });
  });

  testWidgets(
      'semanticButton() with onTap is one named button, not a nameless one '
      'wrapped around a named one', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(
      DVText('Deploy with dartvel deploy').modifier(
        DVModifier().semanticButton().onTap(() {}),
      ),
    ));
    await tester.pumpAndSettle();
    final List<SemanticsData> buttons = <SemanticsData>[];
    void visit(SemanticsNode node) {
      final SemanticsData data = node.getSemanticsData();
      if (data.flagsCollection.isButton) buttons.add(data);
      node.visitChildren((SemanticsNode child) {
        visit(child);
        return true;
      });
    }

    visit(tester.getSemantics(find.byType(MaterialApp)).owner!.rootSemanticsNode!);
    expect(buttons.map((SemanticsData data) => data.label).toList(),
        <String>['Deploy with dartvel deploy']);
    handle.dispose();
  });
}
