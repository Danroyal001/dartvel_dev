// The DVModifier chain on the widget itself, as the spec writes it:
// DVText('Save').fontSize(17).fontWeight(.w700).color(ink), DVBox(child)
// .padding(12).tooltip('Open').onTap(open). Every DVModifier step is on the
// widget, with the same parameters, and draws what the modifier form draws.
@TestOn('vm')
library;

import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

import '../tool/modifier_chain_source.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('the chain never drifts from DVModifier', () {
    final String library = File('lib/dartvel_flutter.dart').readAsStringSync();
    final List<ChainMethod> methods = modifierMethods(library);

    test('DVModifier has the steps the spec names', () {
      final Set<String> names = methods.map((ChainMethod m) => m.name).toSet();
      expect(names, containsAll(<String>['padding', 'paddingOnly', 'fontSize', 'fontWeight', 'color', 'onTap', 'tooltip', 'semanticButton', 'heading', 'minimumTapTarget', 'input', 'hover', 'animate', 'dropTarget', 'draggable']));
      expect(names, isNot(contains('merge')));
    });

    test('every DVModifier step is on the widget, with the same parameters', () {
      final String chain = File('lib/src/primitives/modifier_chain.dart').readAsStringSync();
      for (final ChainMethod method in methods) {
        expect(chain, contains('  W ${method.name}(${method.parameters}) => withModifier(_base.${method.name}(${method.arguments}));'),
            reason: 'DVModifier.${method.name}(${method.parameters}) is not on the chain; run dart run tool/modifier_chain_source.dart');
      }
    });

    test('the checked-in chain is what the tool writes', () {
      expect(File('lib/src/primitives/modifier_chain.dart').readAsStringSync(), mixinSource(methods),
          reason: 'run dart run tool/modifier_chain_source.dart');
    });
  });

  group('DVText', () {
    testWidgets('the chain styles the text as the modifier form does', (WidgetTester tester) async {
      await tester.pumpWidget(_host(DVText('Where voice mode sits').fontSize(17).fontWeight(FontWeight.w700).color(const Color(0xFF112233))));
      final TextStyle style = tester.widget<Text>(find.text('Where voice mode sits')).style!;
      expect(style.fontSize, 17);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.color, const Color(0xFF112233));
    });

    testWidgets('a chain after a constructor modifier layers on it', (WidgetTester tester) async {
      await tester.pumpWidget(_host(DVText('Help', const DVModifier().fontSize(14)).color(const Color(0xFF445566))));
      final TextStyle style = tester.widget<Text>(find.text('Help')).style!;
      expect(style.fontSize, 14);
      expect(style.color, const Color(0xFF445566));
    });

    testWidgets('a heading and padding from the chain', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(DVText('Accessibility').fontSize(24).heading(2).paddingOnly(top: 8)));
      final SemanticsNode node = tester.getSemantics(find.text('Accessibility'));
      expect(node.label, 'Accessibility');
      expect(node.getSemanticsData().headingLevel, 2);
      final Padding padding = tester.widget<Padding>(find.ancestor(of: find.text('Accessibility'), matching: find.byType(Padding)).first);
      expect(padding.padding, const EdgeInsets.only(top: 8));
      semantics.dispose();
    });
  });

  group('DVBox', () {
    test('a tap from the chain is reported at the line that wrote it, not inside the chain', () {
      final DVBox<dynamic> box = DVBox(DVText('Open')).onTap(() {});
      expect(box.chainModifier!.tapSite, contains('modifier_chain_test.dart'));
    });

    testWidgets('padding, tooltip and a tap from the chain', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_host(DVBox(const Icon(Icons.close)).padding(12).minimumTapTarget().tooltip('Close').onTap(() => taps++)));
      await tester.tap(find.byIcon(Icons.close));
      expect(taps, 1);
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('a list and a row take the chain too', (WidgetTester tester) async {
      await tester.pumpWidget(_host(DVBox.list(<Widget>[
        DVBox.row(<Widget>[DVText('One'), DVText('Two')]).backgroundColor(const Color(0xFFEEEEEE)),
      ]).padding(16)));
      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
    });

    testWidgets('two gestures accumulate, as they do on a DVModifier', (WidgetTester tester) async {
      int taps = 0;
      int doubleTaps = 0;
      await tester.pumpWidget(_host(DVBox(DVText('Card')).tooltip('Card').onTap(() => taps++).onDoubleTap(() => doubleTaps++)));
      expect(tester.widget<DVBox<dynamic>>(find.byType(DVBox<dynamic>)).chainModifier!.onTapCallback, isNotNull);
      expect(tester.widget<DVBox<dynamic>>(find.byType(DVBox<dynamic>)).chainModifier!.gestureSet, isNotNull);
    });
  });
}
