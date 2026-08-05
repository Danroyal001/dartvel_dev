// The Studio editing surface: controller semantics (selection, undo/redo)
// and the canvas driven by real drag gestures, not by calling the editor
// directly.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVStudioEditorController controllerWith(List<String> texts) {
  final document = DVPageDocument(route: '/page', title: 'Page');
  final editor = DVPageDocumentEditor(document);
  for (final text in texts) {
    editor.insert(DVPageNode.text(text), parent: document.root.id);
  }
  return DVStudioEditorController(document);
}

List<String> textsOf(DVPageDocument document) => <String>[
      for (final node in document.root.children)
        '${node.properties['text'] ?? node.type}',
    ];

void main() {
  group('controller', () {
    test('inserting selects what was just dropped', () {
      final controller = controllerWith(<String>[]);
      final node = DVPageNode.text('Dropped');

      controller.insert(node, parent: controller.document.root.id);

      // A drop the user cannot immediately edit is a drop they have to hunt
      // for.
      expect(controller.selectedId, node.id);
      expect(controller.selectedNode!.properties['text'], 'Dropped');
    });

    test('undo and redo walk the history', () {
      final controller = controllerWith(<String>['One']);
      expect(controller.canUndo, isFalse);

      controller.insert(
        DVPageNode.text('Two'),
        parent: controller.document.root.id,
      );
      expect(textsOf(controller.document), <String>['One', 'Two']);
      expect(controller.canUndo, isTrue);

      controller.undo();
      expect(textsOf(controller.document), <String>['One']);
      expect(controller.canRedo, isTrue);

      controller.redo();
      expect(textsOf(controller.document), <String>['One', 'Two']);
    });

    test('a new edit clears the redo stack', () {
      final controller = controllerWith(<String>['One']);
      controller.insert(
        DVPageNode.text('Two'),
        parent: controller.document.root.id,
      );
      controller.undo();
      expect(controller.canRedo, isTrue);

      // Branching from an undone state discards the abandoned future, or
      // redo would replay an edit the user has moved away from.
      controller.insert(
        DVPageNode.text('Three'),
        parent: controller.document.root.id,
      );

      expect(controller.canRedo, isFalse);
      expect(textsOf(controller.document), <String>['One', 'Three']);
    });

    test('a rejected mutation records no history', () {
      final controller = controllerWith(<String>[]);
      final box = DVPageNode.box();
      controller.insert(box, parent: controller.document.root.id);
      final undoDepthBefore = controller.canUndo;

      // Dropping a container into itself is refused by the editor.
      expect(
        () => controller.move(box.id, parent: box.id),
        throwsArgumentError,
      );

      controller.undo();
      // One undo returns to the empty document: the failed move left no
      // entry of its own.
      expect(undoDepthBefore, isTrue);
      expect(controller.document.root.children, isEmpty);
    });

    test('undo past the selected node clears the selection', () {
      final controller = controllerWith(<String>[]);
      final node = DVPageNode.text('Gone');
      controller.insert(node, parent: controller.document.root.id);
      expect(controller.selectedId, node.id);

      controller.undo();

      // An inspector bound to a node that no longer exists shows nothing
      // useful and edits nothing.
      expect(controller.selectedId, isNull);
      expect(controller.selectedNode, isNull);
    });

    test('removing the selected node clears the selection', () {
      final controller = controllerWith(<String>[]);
      final node = DVPageNode.text('Doomed');
      controller.insert(node, parent: controller.document.root.id);

      controller.remove(node.id);

      expect(controller.selectedId, isNull);
    });

    test('history is bounded', () {
      final controller =
          DVStudioEditorController(DVPageDocument(route: '/p'), historyLimit: 3);
      for (var i = 0; i < 10; i++) {
        controller.insert(
          DVPageNode.text('$i'),
          parent: controller.document.root.id,
        );
      }

      var undos = 0;
      while (controller.canUndo) {
        controller.undo();
        undos++;
      }
      expect(undos, 3);
    });

    test('setProperty and setAction edit through the inspector path', () {
      final controller = controllerWith(<String>['Label']);
      final id = controller.document.root.children.first.id;

      controller
        ..setProperty(id, 'fontSize', 24)
        ..setAction(id, <String, Object?>{'type': 'navigate', 'to': '/next'});

      final node = DVPageDocumentEditor(controller.document).find(id)!;
      expect(node.properties['fontSize'], 24);
      expect(node.action!['to'], '/next');

      controller.setAction(id, null);
      expect(
        DVPageDocumentEditor(controller.document).find(id)!.action,
        isNull,
      );
    });
  });

  group('canvas', () {
    // The palette is unbounded in a Row without a width, which is a layout
    // constraint of the host rather than of the editor.
    Widget host(DVStudioEditorController controller) => MaterialApp(
          home: Scaffold(
            body: Row(
              children: <Widget>[
                const SizedBox(width: 140, child: DVStudioPalette()),
                Expanded(child: DVStudioCanvas(controller: controller)),
              ],
            ),
          ),
        );

    testWidgets('renders the document as real widgets', (WidgetTester tester) async {
      final controller = controllerWith(<String>['Hello', 'World']);

      await tester.pumpWidget(host(controller));

      // The actual primitives, not a canvas facsimile.
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('World'), findsOneWidget);
      expect(find.byType(DVText), findsWidgets);
    });

    testWidgets('tapping a node selects it', (WidgetTester tester) async {
      final controller = controllerWith(<String>['Hello', 'World']);
      await tester.pumpWidget(host(controller));

      await tester.tap(find.text('World'));
      await tester.pump();

      expect(
        controller.selectedNode!.properties['text'],
        'World',
      );
    });

    testWidgets('dragging from the palette inserts a node',
        (WidgetTester tester) async {
      final controller = controllerWith(<String>['Existing']);
      await tester.pumpWidget(host(controller));
      expect(controller.document.root.children, hasLength(1));

      // A real drag gesture from the palette onto the canvas.
      await tester.drag(
        find.descendant(
          of: find.byType(DVStudioPalette),
          matching: find.text('Text'),
        ),
        tester.getCenter(find.text('Existing')) -
            tester.getCenter(
              find.descendant(
                of: find.byType(DVStudioPalette),
                matching: find.text('Text'),
              ),
            ),
      );
      await tester.pumpAndSettle();

      expect(controller.document.root.children, hasLength(2));
      expect(controller.document.root.children.last.type, 'text');
      // The drop is selected, ready to edit.
      expect(controller.selectedId, controller.document.root.children.last.id);
    });

    testWidgets('the canvas reflects controller changes without a rebuild',
        (WidgetTester tester) async {
      final controller = controllerWith(<String>['Before']);
      await tester.pumpWidget(host(controller));

      controller.setProperty(
        controller.document.root.children.first.id,
        'text',
        'After',
      );
      await tester.pump();

      expect(find.text('After'), findsOneWidget);
      expect(find.text('Before'), findsNothing);
    });

    testWidgets('undo is reflected on the canvas', (WidgetTester tester) async {
      final controller = controllerWith(<String>['Kept']);
      await tester.pumpWidget(host(controller));

      controller.insert(
        DVPageNode.text('Undone'),
        parent: controller.document.root.id,
      );
      await tester.pump();
      expect(find.text('Undone'), findsOneWidget);

      controller.undo();
      await tester.pump();

      expect(find.text('Undone'), findsNothing);
      expect(find.text('Kept'), findsOneWidget);
    });
  });

  group('inspector', () {
    testWidgets('shows nothing useful until something is selected',
        (WidgetTester tester) async {
      final controller = controllerWith(<String>['Label']);

      await tester.pumpWidget(
        MaterialApp(home: DVStudioInspector(controller: controller)),
      );

      expect(find.text('Nothing selected'), findsOneWidget);
    });

    testWidgets('edits the selected node and the edit is undoable',
        (WidgetTester tester) async {
      final controller = controllerWith(<String>['Label']);
      final id = controller.document.root.children.first.id;
      controller.select(id);

      await tester.pumpWidget(
        MaterialApp(home: DVStudioInspector(controller: controller)),
      );
      expect(find.text('text'), findsOneWidget);

      await tester.enterText(
        find.byType(EditableText).first,
        'Renamed',
      );
      await tester.pump();

      expect(
        DVPageDocumentEditor(controller.document).find(id)!.properties['text'],
        'Renamed',
      );
      controller.undo();
      expect(
        DVPageDocumentEditor(controller.document).find(id)!.properties['text'],
        'Label',
      );
    });
  });
}
