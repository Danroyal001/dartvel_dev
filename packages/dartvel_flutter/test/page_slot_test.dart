// Text that changes by request, marked so the server can fill it.
//
// The web-server binary serves the page the build captured, so a date or
// "today's menu" read at build time was served for as long as that build was
// live. `pageSlot` marks the text; the build writes the mark into the page
// and the route's page data fills it on every request.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a slot reaches the semantics tree with its text', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        // ignore: prefer_const_constructors
        body: DVText("TODAY'S MENU · TUESDAY 17 NOVEMBER")
            .modifier(const DVModifier().pageSlot('menu-date')),
      ),
    ));
    final SemanticsNode node = tester.getSemantics(find.byType(DVText));
    expect(node.identifier, 'dartvel:slot:menu-date');
    expect(node.label, "TODAY'S MENU · TUESDAY 17 NOVEMBER");
    handle.dispose();
  });

  test('a slot name must be a plain word, or the server could not find it', () {
    expect(() => const DVModifier().pageSlot('menu date'), throwsArgumentError);
  });
}
