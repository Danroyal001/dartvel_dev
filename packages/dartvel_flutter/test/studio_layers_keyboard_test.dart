import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a keyboard can select the page and a child layer', (tester) async {
    final document = DVPageDocument(route: '/keyboard');
    final child = DVPageNode.text('Selectable content');
    DVPageDocumentEditor(document).insert(child, parent: document.root.id);
    final controller = DVStudioEditorController(document);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DVStudioLayers(controller: controller)),
    ));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.selectedId, document.root.id);
    // The next control expands/collapses the page; the child follows it.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(controller.selectedId, child.id);
  });

  testWidgets('layer selection is exposed as an accessible named action',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final document = DVPageDocument(route: '/accessible');
    final controller = DVStudioEditorController(document);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DVStudioLayers(controller: controller)),
    ));
    final data = tester.getSemantics(find.byKey(
      ValueKey('dv-studio-layer-${document.root.id}'),
    )).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.label, contains('Page'));
    semantics.dispose();
  });
}
