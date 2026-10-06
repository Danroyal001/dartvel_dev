import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compact spacing fields announce their complete property names',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final document = DVPageDocument(route: '/labels');
    final box = DVPageNode.box();
    DVPageDocumentEditor(document).insert(box, parent: document.root.id);
    final controller = DVStudioEditorController(document)..select(box.id);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DVStudioInspector(controller: controller)),
    ));
    for (final name in ['marginTop', 'marginRight', 'paddingBottom', 'width']) {
      final field = find.byKey(ValueKey('dv-studio-inspector-${box.id}-$name'));
      await tester.scrollUntilVisible(field, 100,
          scrollable: find.byType(Scrollable).first);
      final editable = find.descendant(of: field, matching: find.byType(EditableText));
      final label = tester.getSemantics(editable).getSemanticsData().label;
      final expected = switch (name) {
        'marginTop' => 'Margin top',
        'marginRight' => 'Margin right',
        'paddingBottom' => 'Padding bottom',
        _ => 'Width',
      };
      expect(label, contains(expected), reason: '$name must be distinguishable');
    }
    semantics.dispose();
  });
}
