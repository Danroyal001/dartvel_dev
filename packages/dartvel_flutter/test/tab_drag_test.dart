// Dragging in the tab strip.
//
// The controller could reorder and tear out; nothing in the strip could ask
// it to. Each tab was a GestureDetector with onTap and nothing else, so the
// spec's "drag within the strip" and "drag beyond the strip" were controller
// calls a test could make and a person could not.
//
// The gating matters as much as the gesture: reordering is pure UI and works
// everywhere, while tear-out is capability-gated and must be *absent* where it
// is unavailable rather than present and inert.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVTab tab(String path) => DVTab(DVRouteTarget(path));

Future<DVTabWorkspaceController> show(
  WidgetTester tester, {
  bool tearOut = true,
}) async {
  DVWindowManager.capabilityOverride =
      DVWindowingCapability(multiWindow: tearOut, tearOut: tearOut);
  addTearDown(() => DVWindowManager.capabilityOverride = null);

  final DVTabWorkspaceController controller = DVTabWorkspaceController(
    tabs: <DVTab>[tab('/orders'), tab('/customers'), tab('/reports')],
  );
  addTearDown(controller.dispose);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: DVTabWorkspace(controller: controller)),
  ));
  await tester.pumpAndSettle();
  return controller;
}

List<String> pathsOf(DVTabWorkspaceController c) =>
    c.tabs.map((DVTab t) => t.route.path).toList();

void main() {
  testWidgets('a tap still activates, because drag must not eat it',
      (WidgetTester tester) async {
    final DVTabWorkspaceController controller = await show(tester);

    await tester.tap(find.text('reports'));
    await tester.pumpAndSettle();

    expect(controller.activeIndex, 2);
  });

  testWidgets('dragging a tab onto another reorders the strip',
      (WidgetTester tester) async {
    final DVTabWorkspaceController controller = await show(tester);
    expect(pathsOf(controller), <String>['/orders', '/customers', '/reports']);

    await tester.drag(find.text('orders'), const Offset(200, 0));
    await tester.pumpAndSettle();

    expect(pathsOf(controller).first, isNot('/orders'),
        reason: 'the dragged tab should have moved along the strip');
  });

  testWidgets('a reorder keeps the same tab showing',
      (WidgetTester tester) async {
    // The subtle one. Selection is an index, so moving tabs under it changes
    // which page is on screen unless the index moves with the tab -- and the
    // reader did not ask to be taken somewhere else.
    final DVTabWorkspaceController controller = await show(tester);
    controller.activate(0);
    final String active = controller.active!.route.path;

    await tester.drag(find.text('orders'), const Offset(200, 0));
    await tester.pumpAndSettle();

    expect(controller.active!.route.path, active);
  });

  testWidgets('dragging beyond the strip tears the tab out',
      (WidgetTester tester) async {
    final DVTabWorkspaceController controller = await show(tester);

    await tester.drag(find.text('customers'), const Offset(0, 400));
    await tester.pumpAndSettle();

    expect(pathsOf(controller), isNot(contains('/customers')));
  });

  testWidgets('without the capability the tab stays put',
      (WidgetTester tester) async {
    // Absent rather than broken. A gesture that silently does nothing is
    // worse than one that is not offered.
    final DVTabWorkspaceController controller =
        await show(tester, tearOut: false);

    await tester.drag(find.text('customers'), const Offset(0, 400));
    await tester.pumpAndSettle();

    expect(pathsOf(controller), contains('/customers'));
  });

  testWidgets('reordering still works without the capability',
      (WidgetTester tester) async {
    // Reordering is pure UI and required on every target, including ones with
    // no windowing at all.
    final DVTabWorkspaceController controller =
        await show(tester, tearOut: false);

    await tester.drag(find.text('orders'), const Offset(200, 0));
    await tester.pumpAndSettle();

    expect(pathsOf(controller).first, isNot('/orders'));
  });

  testWidgets('a drag that goes nowhere changes nothing',
      (WidgetTester tester) async {
    final DVTabWorkspaceController controller = await show(tester);
    final List<String> before = pathsOf(controller);

    await tester.drag(find.text('orders'), const Offset(2, 0));
    await tester.pumpAndSettle();

    expect(pathsOf(controller), before);
  });
}
