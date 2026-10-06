import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Tab and Enter insert an element without dragging', (tester) async {
    final document = DVPageDocument(route: '/keyboard-insert');
    final controller = DVStudioEditorController(document);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DVStudioPalette(controller: controller)),
    ));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Search.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // First element.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(document.root.children, hasLength(1));
    expect(document.root.children.single.type, 'text');
    expect(controller.selectedId, document.root.children.single.id);
  });
}
