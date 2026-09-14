// Studio's editor panels, driven the way a person drives them.
//
// Layers, the inspector, the insert panel and the canvas each got the job a
// design tool's version of them does — a tree you can collapse and select
// from, a grouped inspector, tap-to-insert, a real artboard — and each of those
// is behaviour a screenshot can show and a test has to check, because every one
// of them has a quiet way to be wrong: a layer tap that highlights and selects
// nothing, a property that falls out of the inspector because nobody put it in
// a group, an insert that lands in the page instead of the card you selected.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Page > [Column > 'Hello'], 'World'.
({DVStudioEditorController controller, String box, String hello, String world})
    page() {
  final DVPageDocument document = DVPageDocument(route: '/p', title: 'P');
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  final DVPageNode box = DVPageNode.box();
  final DVPageNode hello = DVPageNode.text('Hello');
  final DVPageNode world = DVPageNode.text('World');
  editor.insert(box, parent: document.root.id);
  editor.insert(hello, parent: box.id);
  editor.insert(world, parent: document.root.id);
  return (
    controller: DVStudioEditorController(document),
    box: box.id,
    hello: hello.id,
    world: world.id,
  );
}

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('layers', () {
    testWidgets('tapping a layer selects its node', (WidgetTester tester) async {
      final p = page();
      await tester.pumpWidget(host(DVStudioLayers(controller: p.controller)));

      await tester.tap(find.byKey(ValueKey<String>('dv-studio-layer-${p.world}')));
      await tester.pump();

      expect(p.controller.selectedId, p.world);
    });

    testWidgets('a collapsed container hides what is inside it',
        (WidgetTester tester) async {
      final p = page();
      await tester.pumpWidget(host(DVStudioLayers(controller: p.controller)));
      expect(find.byKey(ValueKey<String>('dv-studio-layer-${p.hello}')),
          findsOneWidget);

      await tester.tap(
          find.byKey(ValueKey<String>('dv-studio-layer-toggle-${p.box}')));
      await tester.pump();
      expect(find.byKey(ValueKey<String>('dv-studio-layer-${p.hello}')),
          findsNothing);

      await tester.tap(
          find.byKey(ValueKey<String>('dv-studio-layer-toggle-${p.box}')));
      await tester.pump();
      expect(find.byKey(ValueKey<String>('dv-studio-layer-${p.hello}')),
          findsOneWidget);
    });

    testWidgets('a layer shows its content as a preview, not as a label',
        (WidgetTester tester) async {
      // The canvas already draws 'Hello'. A layer that drew it again as its own
      // text would be a second 'Hello' on the screen, which is ambiguous to a
      // reader and to anything finding the page's content by what it says.
      final p = page();
      await tester.pumpWidget(host(DVStudioLayers(controller: p.controller)));

      expect(find.text('Hello'), findsNothing);
      expect(find.textContaining('Hello', findRichText: true), findsOneWidget);
    });
  });

  group('inspector', () {
    List<String> groupedNames(DVPageNode node) => <String>[
          for (final (String _, List<String> names)
              in dvStudioInspectorGroupsFor(node))
            ...names,
        ];

    test('every property the renderer applies has a place in it', () {
      // The inspector used to be one flat list generated from the property
      // table, so nothing could be missing from it. Grouped, a property nobody
      // put in a group would simply vanish — offered by the table, applied by
      // the renderer, and unreachable from the screen.
      final List<DVPageNode> nodes = <DVPageNode>[
        DVPageNode.text('t'),
        DVPageNode.box(),
        DVPageNode.box(layout: 'grid'),
        DVPageNode.image('https://example.com/a.png'),
      ];
      for (final DVPageNode node in nodes) {
        final List<String> names = groupedNames(node);
        expect(names.toSet(), hasLength(names.length),
            reason: '${node.type}/${node.layout}: a property is in two groups');
        for (final DVStudioProperty property in dvStudioProperties) {
          expect(names, contains(property.name),
              reason: '${property.name} is unreachable on a '
                  '${node.type}/${node.layout}');
        }
        final bool isBox = dvStudioLeafTypeFor(node) == null;
        for (final DVStudioLayoutProperty property
            in dvStudioLayoutProperties) {
          final bool applies = isBox && property.appliesTo(node.layout);
          expect(names.contains(property.name), applies,
              reason: '${property.name} on a ${node.type}/${node.layout}');
        }
      }
    });

    testWidgets('each grouped property has a control on screen',
        (WidgetTester tester) async {
      final p = page();
      p.controller.select(p.box);
      await tester.pumpWidget(
          host(DVStudioInspector(controller: p.controller)));

      final DVPageNode box = p.controller.selectedNode!;
      for (final String name in groupedNames(box)) {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey<String>('dv-studio-inspector-${p.box}-$name')),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.byKey(ValueKey<String>('dv-studio-inspector-${p.box}-$name')),
          findsOneWidget,
          reason: '$name has no control',
        );
      }
    });

    testWidgets('a choice is a set of options, not a text field',
        (WidgetTester tester) async {
      final p = page();
      p.controller.select(p.box);
      await tester.pumpWidget(
          host(DVStudioInspector(controller: p.controller)));

      await tester.tap(find.byKey(
          ValueKey<String>('dv-studio-inspector-${p.box}-mainAxis-center')));
      await tester.pump();

      expect(p.controller.selectedNode!.properties['mainAxis'], 'center');
    });
  });

  group('insert panel', () {
    Finder item(String label) => find.descendant(
          of: find.byType(DVStudioPalette),
          matching: find.text(label),
        );

    testWidgets('tapping an element puts it in the selected container',
        (WidgetTester tester) async {
      final p = page();
      p.controller.select(p.box);
      await tester.pumpWidget(
          host(DVStudioPalette(controller: p.controller)));

      await tester.tap(item('Text'));
      await tester.pump();

      final DVPageNode box =
          DVPageDocumentEditor(p.controller.document).find(p.box)!;
      expect(box.children, hasLength(2));
      expect(p.controller.selectedId, box.children.last.id,
          reason: 'what was inserted is selected, ready to edit');
    });

    testWidgets('beside a selected leaf, it goes into that leaf\'s container',
        (WidgetTester tester) async {
      final p = page();
      p.controller.select(p.hello);
      await tester.pumpWidget(
          host(DVStudioPalette(controller: p.controller)));

      await tester.tap(item('Image'));
      await tester.pump();

      expect(
          DVPageDocumentEditor(p.controller.document).find(p.box)!.children,
          hasLength(2));
    });

    testWidgets('with nothing selected it goes into the page',
        (WidgetTester tester) async {
      final p = page();
      await tester.pumpWidget(
          host(DVStudioPalette(controller: p.controller)));

      await tester.tap(item('Spacer'));
      await tester.pump();

      expect(p.controller.document.root.children, hasLength(3));
    });

    testWidgets('search narrows the elements', (WidgetTester tester) async {
      await tester.pumpWidget(host(const DVStudioPalette()));

      await tester.enterText(find.byType(EditableText).first, 'gri');
      await tester.pump();

      expect(item('Grid'), findsOneWidget);
      expect(item('Text'), findsNothing);
    });
  });

  group('canvas', () {
    testWidgets('the artboard is the viewport\'s width',
        (WidgetTester tester) async {
      final p = page();
      await tester.pumpWidget(host(
          DVStudioCanvas(controller: p.controller, viewportWidth: 390)));

      expect(
        tester.getSize(find.byKey(const ValueKey<String>('dv-studio-artboard')))
            .width,
        390,
      );
    });

    testWidgets('tapping the empty workspace clears the selection',
        (WidgetTester tester) async {
      final p = page();
      p.controller.select(p.world);
      await tester.pumpWidget(host(
          DVStudioCanvas(controller: p.controller, viewportWidth: 390)));

      // Well to the left of a 390-wide artboard centred in an 800-wide canvas.
      await tester.tapAt(const Offset(30, 400));
      await tester.pump();

      expect(p.controller.selectedId, isNull);
    });

    testWidgets('a zoomed-out artboard is on screen, and taps reach its nodes',
        (WidgetTester tester) async {
      // A desktop-width page fitted into a narrow canvas, which is what a
      // shell's "Fit" zoom does. Scaling the drawing without scaling the layout
      // left the page laid out 1280 pixels wide and drawn shrunk around the
      // middle of that — off the right of the visible canvas, where a tap on
      // one of its nodes lands on nothing and selects nothing.
      final p = page();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 500,
              child: DVStudioCanvas(
                controller: p.controller,
                viewportWidth: 1280,
                zoom: 0.15,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      final Rect canvas = tester.getRect(find.byType(DVStudioCanvas));
      final Rect board =
          tester.getRect(find.byKey(const ValueKey<String>('dv-studio-artboard')));
      expect(board.width, closeTo(1280 * 0.15, 1),
          reason: 'the artboard is drawn at the zoom it was given');
      expect(board.left >= canvas.left && board.right <= canvas.right, isTrue,
          reason: 'the fitted artboard is inside the canvas, not beside it: '
              'canvas $canvas, artboard $board');

      await tester.tap(find.text('World'), warnIfMissed: false);
      await tester.pump();
      expect(p.controller.selectedId, p.world);
    });
  });

  group('narrow panels', () {
    // A panel is as wide as the shell hosting it decides, and the shell it is
    // hosted in today gives the inspector about 140 pixels at an 800-pixel
    // window. A fixed-width label column beside a control, or a badge and an
    // id side by side, overflows there — and an overflow is a red stripe on
    // the screen and a failure in every test that opens a page.
    Widget narrow(Widget child, double width) => MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, height: 600, child: child),
            ),
          ),
        );

    testWidgets('the inspector fits a narrow column for every kind of node',
        (WidgetTester tester) async {
      final DVPageDocument document = DVPageDocument(route: '/n', title: 'N');
      final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
      final List<DVPageNode> nodes = <DVPageNode>[
        DVPageNode.text('A heading that is long enough to wrap'),
        DVPageNode.box(),
        DVPageNode.box(layout: 'row'),
        DVPageNode.box(layout: 'grid'),
        DVPageNode.image('https://example.com/a-long-file-name.png'),
      ];
      for (final DVPageNode node in nodes) {
        editor.insert(node, parent: document.root.id);
      }
      final DVStudioEditorController controller =
          DVStudioEditorController(document);

      for (final DVPageNode node in <DVPageNode>[document.root, ...nodes]) {
        for (final double width in <double>[140, 200, 280]) {
          controller.select(node.id);
          await tester.pumpWidget(
              narrow(DVStudioInspector(controller: controller), width));
          await tester.pump();
          // Walk the whole scrollable, so fields below the fold are laid out.
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: '${node.type}/${node.layout} at $width px');
        }
      }
    });

    testWidgets('the insert panel and layers fit a narrow column',
        (WidgetTester tester) async {
      final p = page();
      for (final double width in <double>[84, 140, 240]) {
        await tester.pumpWidget(
            narrow(DVStudioPalette(controller: p.controller), width));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'palette at $width px');
      }
      p.controller.select(p.hello);
      for (final double width in <double>[120, 240]) {
        await tester.pumpWidget(
            narrow(DVStudioLayers(controller: p.controller), width));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'layers at $width px');
      }
    });
  });
}
