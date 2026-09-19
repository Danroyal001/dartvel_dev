// A workflow's inputs and result are set in the builder, not only in code.
//
// The builder had no way to say what a workflow takes: its inputs existed
// only in a document written by hand. With nothing selected on the canvas the
// inspector now shows the function itself -- each input with its name, its
// type and whether it may be left out, and the type of what it returns.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVWorkflowEditorController fresh() =>
    DVWorkflowEditorController(DVWorkflowDocument(name: 'welcome'));

void main() {
  group('the controller', () {
    test('adds an input as Text, and undo takes it away', () {
      final DVWorkflowEditorController controller = fresh();

      controller.addInput();
      expect(controller.document.parameters,
          const <DVWorkflowParameter>[DVWorkflowParameter('input1', DVWorkflowType.text)]);

      controller.undo();
      expect(controller.document.parameters, isEmpty);
    });

    test('changes an input and the result type', () {
      final DVWorkflowEditorController controller = fresh()..addInput();

      controller.setInput(0, const DVWorkflowParameter('email', DVWorkflowType.text));
      controller.setInput(0,
          controller.document.parameters.first.copyWith(optional: true));
      controller.setReturns(DVWorkflowType.yesNo);

      expect(controller.document.parameters.single,
          const DVWorkflowParameter('email', DVWorkflowType.text, optional: true));
      expect(controller.document.returns, DVWorkflowType.yesNo);
      controller.setReturns(null);
      expect(controller.document.returns, isNull);
    });

    test('removes an input', () {
      final DVWorkflowEditorController controller = fresh()
        ..addInput()
        ..addInput();

      controller.removeInput(0);

      expect(controller.document.parameters.single.name, 'input2');
    });
  });

  testWidgets('with nothing selected the inspector edits the inputs',
      (WidgetTester tester) async {
    final DVWorkflowEditorController controller = fresh();
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Material(child: DVWorkflowInspector(controller: controller)),
    ));

    expect(find.text('INPUTS'), findsOneWidget);
    expect(find.text('RETURNS'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('dv-workflow-add-input')));
    await tester.pumpAndSettle();

    expect(controller.document.parameters, hasLength(1));
    expect(find.text('Text'), findsWidgets);
  });

  testWidgets('an input with no type says so', (WidgetTester tester) async {
    final DVWorkflowEditorController controller = DVWorkflowEditorController(
      DVWorkflowDocument.fromJson(
          <String, Object?>{'name': 'old', 'parameters': <Object?>['email']}),
    );
    await tester.pumpWidget(MaterialApp(
      home: Material(child: DVWorkflowInspector(controller: controller)),
    ));

    expect(find.text('Choose a type'), findsOneWidget);
  });
}
