// The workflow editing surface: tree edits into condition branches, undo/redo,
// and the canvas driven by real drag gestures.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVWorkflowEditorController controllerWith(List<DVWorkflowStep> steps) =>
    DVWorkflowEditorController(
      DVWorkflowDocument(name: 'welcome', steps: steps),
    );

void main() {
  group('controller', () {
    test('inserting selects the new step', () {
      final controller = controllerWith(<DVWorkflowStep>[]);
      final step = DVWorkflowStep.call('sendMail');

      controller.insert(step);

      expect(controller.selectedId, step.id);
      expect(controller.document.steps.single.name, 'sendMail');
    });

    test('a step can be dropped into a condition branch', () {
      final condition = DVWorkflowStep.condition(
        const DVWorkflowValue.literal(true),
      );
      final controller = controllerWith(<DVWorkflowStep>[condition]);
      final inner = DVWorkflowStep.call('audit');

      controller.insert(inner, parent: '${condition.id}/then');

      final branch = controller.document.steps.single.branches['then']!;
      expect(branch.single.name, 'audit');
      // And nothing leaked to the top level.
      expect(controller.document.steps, hasLength(1));
    });

    test('a step moves between branches', () {
      final condition = DVWorkflowStep.condition(
        const DVWorkflowValue.literal(true),
      );
      final controller = controllerWith(<DVWorkflowStep>[condition]);
      final step = DVWorkflowStep.call('audit');
      controller.insert(step, parent: '${condition.id}/then');

      controller.move(step.id, parent: '${condition.id}/else');

      final current = controller.document.steps.single;
      expect(current.branches['then'], isEmpty);
      expect(current.branches['else']!.single.name, 'audit');
    });

    test('a condition cannot be moved into its own branch', () {
      final condition = DVWorkflowStep.condition(
        const DVWorkflowValue.literal(true),
      );
      final controller = controllerWith(<DVWorkflowStep>[condition]);

      // Otherwise the tree would be detached from itself and everything
      // below it lost.
      expect(
        () => controller.move(condition.id, parent: '${condition.id}/then'),
        throwsArgumentError,
      );
      expect(controller.document.steps.single.id, condition.id);
    });

    test('undo and redo walk the history', () {
      final controller = controllerWith(<DVWorkflowStep>[]);
      controller.insert(DVWorkflowStep.call('first'));
      controller.insert(DVWorkflowStep.call('second'));
      expect(controller.document.steps, hasLength(2));

      controller.undo();
      expect(controller.document.steps, hasLength(1));

      controller.redo();
      expect(controller.document.steps, hasLength(2));
      expect(controller.document.steps.last.name, 'second');
    });

    test('undo past the selected step clears the selection', () {
      final controller = controllerWith(<DVWorkflowStep>[]);
      final step = DVWorkflowStep.call('gone');
      controller.insert(step);

      controller.undo();

      expect(controller.selectedId, isNull);
      expect(controller.selectedStep, isNull);
    });

    test('editing a step keeps its identity so selection survives', () {
      final controller = controllerWith(<DVWorkflowStep>[]);
      final step = DVWorkflowStep.call('old');
      controller.insert(step);

      controller.update(
        step.id,
        (DVWorkflowStep s) => s.withName('new').withAssignTo('result'),
      );

      // Same id: an edit is not a replacement, or the inspector would lose
      // the step it is editing on every keystroke.
      expect(controller.selectedId, step.id);
      expect(controller.selectedStep!.name, 'new');
      expect(controller.selectedStep!.assignTo, 'result');
    });

    test('viewCode exports the workflow being edited', () {
      final controller = controllerWith(<DVWorkflowStep>[
        DVWorkflowStep.returns(const DVWorkflowValue.literal('done')),
      ]);

      final code = controller.viewCode();

      expect(code, contains('@DVBackendFunction()'));
      expect(code, contains("return 'done';"));
    });
  });

  group('canvas', () {
    Widget host(DVWorkflowEditorController controller) => MaterialApp(
          home: Scaffold(
            body: Row(
              children: <Widget>[
                const SizedBox(width: 140, child: DVWorkflowPalette()),
                Expanded(child: DVWorkflowCanvas(controller: controller)),
              ],
            ),
          ),
        );

    testWidgets('renders steps in execution order', (WidgetTester tester) async {
      final controller = controllerWith(<DVWorkflowStep>[
        DVWorkflowStep.call('sendMail'),
        DVWorkflowStep.returns(const DVWorkflowValue.literal('ok')),
      ]);

      await tester.pumpWidget(host(controller));

      expect(find.text('call sendMail'), findsOneWidget);
      expect(find.text('return'), findsOneWidget);
    });

    testWidgets('a condition renders both branches as drop zones',
        (WidgetTester tester) async {
      final controller = controllerWith(<DVWorkflowStep>[
        DVWorkflowStep.condition(const DVWorkflowValue.literal(true)),
      ]);

      await tester.pumpWidget(host(controller));

      expect(find.text('then'), findsOneWidget);
      expect(find.text('else'), findsOneWidget);
      expect(find.textContaining('drop here'), findsNWidgets(2));
    });

    testWidgets('tapping a step selects it', (WidgetTester tester) async {
      final controller = controllerWith(<DVWorkflowStep>[
        DVWorkflowStep.call('sendMail'),
      ]);
      await tester.pumpWidget(host(controller));

      await tester.tap(find.text('call sendMail'));
      await tester.pump();

      expect(controller.selectedStep!.name, 'sendMail');
    });

    testWidgets('dragging from the palette adds a step',
        (WidgetTester tester) async {
      final controller = controllerWith(<DVWorkflowStep>[
        DVWorkflowStep.call('existing'),
      ]);
      await tester.pumpWidget(host(controller));

      final source = find.descendant(
        of: find.byType(DVWorkflowPalette),
        matching: find.text('Return'),
      );
      await tester.drag(
        source,
        tester.getCenter(find.text('call existing')) -
            tester.getCenter(source),
      );
      await tester.pumpAndSettle();

      expect(controller.document.steps, hasLength(2));
      expect(controller.document.steps.last.type, 'return');
    });

    testWidgets('dropping into a branch nests the step',
        (WidgetTester tester) async {
      final condition = DVWorkflowStep.condition(
        const DVWorkflowValue.literal(true),
      );
      final controller = controllerWith(<DVWorkflowStep>[condition]);
      await tester.pumpWidget(host(controller));

      final source = find.descendant(
        of: find.byType(DVWorkflowPalette),
        matching: find.text('Call'),
      );
      // The 'then' zone is the first empty drop target under the condition.
      final target = find.text('drop here: ${condition.id}/then');
      await tester.drag(
        source,
        tester.getCenter(target) - tester.getCenter(source),
      );
      await tester.pumpAndSettle();

      expect(controller.document.steps, hasLength(1));
      expect(
        controller.document.steps.single.branches['then'],
        hasLength(1),
      );
    });

    testWidgets('the canvas follows undo', (WidgetTester tester) async {
      final controller = controllerWith(<DVWorkflowStep>[]);
      await tester.pumpWidget(host(controller));

      controller.insert(DVWorkflowStep.call('audit'));
      await tester.pump();
      expect(find.text('call audit'), findsOneWidget);

      controller.undo();
      await tester.pump();

      expect(find.text('call audit'), findsNothing);
    });
  });

  group('inspector', () {
    testWidgets(r'edits the selected step, and a $-prefix means a reference',
        (WidgetTester tester) async {
      final step = DVWorkflowStep.call(
        'sendMail',
        arguments: <String, DVWorkflowValue>{
          'to': const DVWorkflowValue.literal(''),
        },
      );
      final controller = controllerWith(<DVWorkflowStep>[step])
        ..select(step.id);

      await tester.pumpWidget(
        MaterialApp(home: DVWorkflowInspector(controller: controller)),
      );

      // A plain value is a literal.
      await tester.enterText(find.byType(EditableText).last, 'ada@example.com');
      await tester.pump();
      expect(
        controller.selectedStep!.arguments['to']!.literal,
        'ada@example.com',
      );

      // A leading $ makes it read a variable instead.
      await tester.enterText(find.byType(EditableText).last, r'$email');
      await tester.pump();
      expect(controller.selectedStep!.arguments['to']!.variable, 'email');
    });

    testWidgets('says so when nothing is selected', (WidgetTester tester) async {
      final controller = controllerWith(<DVWorkflowStep>[]);

      await tester.pumpWidget(
        MaterialApp(home: DVWorkflowInspector(controller: controller)),
      );

      expect(find.text('No step selected'), findsOneWidget);
    });
  });
}
