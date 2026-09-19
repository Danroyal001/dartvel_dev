// The workflow canvas says what kind of step each card is, before any of the
// text on the card has to be read.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('each card says what kind of step it is',
      (WidgetTester tester) async {
    final DVWorkflowEditorController controller = DVWorkflowEditorController(
      DVWorkflowDocument(name: 'welcome', steps: <DVWorkflowStep>[
        DVWorkflowStep.call('sendMail'),
        DVWorkflowStep.condition(const DVWorkflowValue.literal(true)),
      ]),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DVWorkflowCanvas(controller: controller)),
    ));

    expect(find.text('CALL'), findsOneWidget);
    expect(find.text('CONDITION'), findsOneWidget);
  });
}
