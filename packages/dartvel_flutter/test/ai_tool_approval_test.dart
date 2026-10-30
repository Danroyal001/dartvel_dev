// DV.AI.registerTool takes the approval a tool needs, and an application can
// name what an agent run hands back when it stops for one.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    const DVAIToolRegistry().clear();
    DV.AI.configure(const LocalDVAIAdapter());
  });

  test('a tool registered as needing approval pauses the run', () async {
    final List<DVJsonObject> refunds = <DVJsonObject>[];
    DV.AI.registerTool(
      'issueRefund',
      (DVJsonObject input) {
        refunds.add(input);
        return const DVJsonString('refunded');
      },
      description: 'Issue a refund',
      approval: DVToolApproval.required,
    );
    DV.AI.configure(const LocalDVAIAdapter());

    final DVAIAgentResult result = await DV.AI.runAgent(
      const DVAIAgentRequest(
        goal: 'Refund order 7',
        context: <String, DVJsonValue>{'amount': DVJsonNumber(40)},
        tools: <String>['issueRefund'],
      ),
    );

    expect(refunds, isEmpty);
    final DVAIToolPause pause = result.pause!;
    expect(pause.tool, 'issueRefund');
    await pause.approve();
    expect(refunds, hasLength(1));
  });

  test('calling it directly is DV-AI-010', () async {
    DV.AI.registerTool(
      'issueRefund',
      (DVJsonObject input) => const DVJsonString('refunded'),
      approval: DVToolApproval.required,
    );
    await expectLater(
      const DVAIToolRegistry().call('issueRefund'),
      throwsA(isA<DVAIToolApprovalRequired>()),
    );
  });
}
