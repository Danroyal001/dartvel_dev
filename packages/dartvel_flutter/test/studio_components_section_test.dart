// Components in free Studio: a section of their own, an Insert panel that
// lists them beside the built-in elements, props set per use in the style
// panel, and any selection turned into a component in one step.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _key(String key) => find.byKey(ValueKey<String>(key));

DVPageDocument _card() => dvStudioComponent(
      'PriceCard',
      root: DVPageNode(type: 'box', children: <DVPageNode>[
        DVPageNode(
          type: 'text',
          properties: <String, Object?>{'text': '{{title}} a month'},
        ),
      ]),
      props: const <DVStudioComponentProp>[
        DVStudioComponentProp('title', DVStudioPropKind.text, '£5'),
      ],
    );

Widget _studio() => const MaterialApp(home: Material(child: DVStudioScreen()));

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

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> openPage(WidgetTester tester, String route) async {
    await tester.enterText(
        find.descendant(of: _key('dv-studio-new-page'), matching: find.byType(EditableText)),
        route);
    await tester.tap(_key('dv-studio-create'));
    await tester.pumpAndSettle();
  }

  testWidgets('Components is a section of free Studio, where a component is '
      'made, given props, and saved', (WidgetTester tester) async {
    desktop(tester);
    await tester.pumpWidget(_studio());
    await tester.pumpAndSettle();

    await tester.tap(_key('dv-studio-section-components'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: _key('dv-studio-component-name'),
            matching: find.byType(EditableText)),
        'PriceCard');
    await tester.tap(_key('dv-studio-component-create'));
    await tester.pumpAndSettle();

    await tester.tap(_key('dv-studio-component-add-prop'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: _key('dv-studio-component-prop-name-0'),
            matching: find.byType(EditableText)),
        'title');
    await tester.tap(_key('dv-studio-component-save'));
    await tester.pumpAndSettle();

    final DVPageDocument? saved =
        await const DVPageStore().load('/_dartvel/components/PriceCard');
    expect(saved, isNotNull);
    expect(<String>[for (final p in dvStudioComponentPropsOf(saved!)) p.name],
        <String>['title']);
    expect(_key('dv-studio-component-row-PriceCard'), findsOneWidget);
  });

  testWidgets('the Insert panel lists the project\'s components, and a use of '
      'one has its props set in the style panel', (WidgetTester tester) async {
    desktop(tester);
    await const DVPageStore().save(_card());
    await tester.pumpWidget(_studio());
    await tester.pumpAndSettle();
    // Not a page: a component is not listed with the site's pages.
    expect(_key('dv-studio-route-/_dartvel/components/PriceCard'), findsNothing);

    await openPage(tester, '/pricing');
    expect(find.text('Components'), findsWidgets);
    await tester.tap(find.widgetWithText(GestureDetector, 'PriceCard').first);
    await tester.pumpAndSettle();
    expect(find.text('£5 a month'), findsOneWidget);

    await tester.tap(find.text('£5 a month'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: _key('dv-studio-instance-prop-title'),
            matching: find.byType(EditableText)),
        '£9');
    await tester.pumpAndSettle();
    expect(find.text('£9 a month'), findsOneWidget);
    expect(_key('dv-studio-edit-component'), findsOneWidget);
  });

  testWidgets('a selection becomes a component, and the page uses it in its '
      'place', (WidgetTester tester) async {
    desktop(tester);
    await tester.pumpWidget(_studio());
    await tester.pumpAndSettle();
    await openPage(tester, '/about');
    await tester.tap(find.widgetWithText(GestureDetector, 'Text').first);
    await tester.pumpAndSettle();

    // Ctrl+Alt+K, Figma's shortcut for it.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: _key('dv-studio-make-component-name'),
            matching: find.byType(EditableText)),
        'Greeting');
    await tester.pump();
    await tester.tap(_key('dv-studio-make-component-confirm'));
    await tester.pumpAndSettle();

    final DVPageDocument? component =
        await const DVPageStore().load('/_dartvel/components/Greeting');
    expect(component, isNotNull);
    expect(component!.root.type, 'text');
    expect(_key('dv-studio-instance-props'), findsOneWidget,
        reason: 'the selection is now a use of the component');
  });
}
