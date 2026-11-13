// `@DVFunctionalWidget(pageScroll: true)`: the long-page "To the bottom /
// Back to top" button as an attribute of the annotation, not a widget an app
// nests its page in (owner, 13 Nov 2026: "we don't do that nesting in
// Dartvel"). The generated class wraps what the function builds; the button
// itself is framework-internal.
import 'package:test/test.dart';

import 'functional_widget_class_test.dart' show widgetsFor;

const String _imports = "import 'package:flutter/widgets.dart';\n"
    "import 'package:dartvel_flutter/dartvel_flutter.dart';\n";

void main() {
  test('pageScroll: true wraps what the function builds in the page-scroll frame', () async {
    final String widgets = await widgetsFor('$_imports'
        '@DVFunctionalWidget(pageScroll: true)\n'
        "Widget _shell(Widget child) => DVBox.scrollableList([child]);\n");
    expect(widgets, contains('class const Shell(final Widget child, {super.key}) extends StatelessWidget'));
    expect(widgets, contains('DVPageScrollFrame(child: _build(context))'));
    expect(widgets, contains('Widget _build(BuildContext context) {'));
  });

  test('a block body keeps its own returns inside the wrapped build', () async {
    final String widgets = await widgetsFor('$_imports'
        '@DVFunctionalWidget(pageScroll: true)\n'
        'Widget _shell(BuildContext context, Widget child) {\n'
        '  final List<Widget> rows = [child];\n'
        '  return DVBox.scrollableList(rows);\n'
        '}\n');
    expect(widgets, contains('DVPageScrollFrame(child: _build(context))'));
    expect(widgets, contains('final List<Widget> rows = [child];'));
  });

  test('without it, or with pageScroll: false, nothing changes', () async {
    for (final String annotation in <String>['@DVFunctionalWidget()', '@DVFunctionalWidget(pageScroll: false)']) {
      final String widgets = await widgetsFor('$_imports'
          '$annotation\n'
          "Widget _badge(String label) => DVText(label);\n");
      expect(widgets, contains('class const Badge(final String label, {super.key}) extends StatelessWidget'), reason: annotation);
      expect(widgets, isNot(contains('DVPageScrollFrame')), reason: annotation);
    }
  });
}
