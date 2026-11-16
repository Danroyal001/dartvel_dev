// Request-time text keeps its mark through the build.
//
// `DVModifier.pageSlot(name)` travels as the semantics identifier
// `dartvel:slot:<name>`, which the capture reads as the node's role. The
// document must carry the name, or the server has nothing to fill and the
// page shows the build's day forever (EatingToday's "TODAY'S MENU").
import 'package:dartvel_cli/src/build/semantic_html.dart';
import 'package:test/test.dart';

void main() {
  test('a slotted paragraph keeps its name on a span inside the paragraph', () {
    expect(
      dvSemanticHtml(const <DVSemanticNode>[
        DVSemanticNode(role: 'slot:menu-date', label: "TODAY'S MENU · MONDAY 16 NOVEMBER"),
      ]),
      '''<p><span data-dv-slot="menu-date">TODAY'S MENU · MONDAY 16 NOVEMBER</span></p>''',
    );
  });

  test('a slotted heading stays a heading', () {
    expect(
      dvSemanticHtml(const <DVSemanticNode>[
        DVSemanticNode(role: 'slot:greeting', headingLevel: 2, label: 'Good morning'),
      ]),
      '<h2><span data-dv-slot="greeting">Good morning</span></h2>',
    );
  });

  test('a name that is not a plain word is written as plain text', () {
    expect(
      dvSemanticHtml(const <DVSemanticNode>[
        DVSemanticNode(role: 'slot:a"b', label: 'x'),
      ]),
      '<p>x</p>',
    );
  });
}
