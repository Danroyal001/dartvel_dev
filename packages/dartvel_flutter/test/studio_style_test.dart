// Studio's style vocabulary, and the one thing it exists to get right.
//
// `DVStudioSection` is an extension seam: the Pro workflow builder attaches
// through it, and so does anything else a team writes. A seam with no style
// vocabulary produces sections that look foreign to the tool hosting them,
// and worse, sections written by copying an existing one inherit whatever was
// wrong with it. That is how this happened — Studio's own Pages section was
// never styled, the Pro workflow builder was written from it, and the copy
// came out the same.
//
// The defect worth a test is the layout one, because it is invisible in a
// unit test that only checks a widget is present: `DVBox.row` resolves
// `DVCrossAlign.stretch` to `CrossAxisAlignment.center` deliberately, so a
// list beside an editor came out as tall as its own contents and floated in
// the middle of the screen. `DVStudioStyle.panes` is the shape that does not.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('panes run the full height beside each other', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 800,
          height: 600,
          child: DVStudioStyle.panes(
            list: const SizedBox(key: ValueKey<String>('list')),
            detail: const SizedBox(key: ValueKey<String>('detail')),
          ),
        ),
      ),
    );

    // The whole height, not the height of what happens to be in them. A short
    // list in a tall window is the ordinary case and the one that looked
    // broken: three routes drew a small block adrift in an empty page.
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('list'))).height,
      600,
      reason: 'the list pane must fill the height it is given',
    );
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('detail'))).height,
      600,
      reason: 'the detail pane must fill the height it is given',
    );
  });

  testWidgets('the list pane takes a fixed width and the detail pane the rest',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 800,
          height: 600,
          child: DVStudioStyle.panes(
            listWidth: 200,
            list: const SizedBox(key: ValueKey<String>('list')),
            detail: const SizedBox(key: ValueKey<String>('detail')),
          ),
        ),
      ),
    );

    final double list =
        tester.getSize(find.byKey(const ValueKey<String>('list'))).width;
    final double detail =
        tester.getSize(find.byKey(const ValueKey<String>('detail'))).width;

    // Within a pixel: the rule between the panes is a one-pixel border on the
    // list pane, so its child is that much narrower than the width asked for.
    expect(list, closeTo(200, 1.01));
    expect(detail, closeTo(600, 1.01));
    expect(list + detail, closeTo(800, 1.01),
        reason: 'the two panes together fill the width, with no third thing '
            'taking space between them');
  });

  testWidgets('a control says whether it can be used', (
    WidgetTester tester,
  ) async {
    // Not a colour assertion — what matters is that the two states are not
    // the same widget, because an action with nothing to do that looks
    // identical to one that works is the whole problem.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: <Widget>[
            DVStudioStyle.control('Undo', enabled: false),
            DVStudioStyle.control('Publish', enabled: true),
            DVStudioStyle.control('Create', enabled: true, primary: true),
          ],
        ),
      ),
    );

    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Publish'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);

    Color? fill(String label) {
      final Container container = tester.widget<Container>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byType(Container),
            )
            .first,
      );
      return (container.decoration as BoxDecoration?)?.color;
    }

    expect(fill('Undo'), isNot(fill('Publish')),
        reason: 'a disabled control must not look like an enabled one');
    expect(fill('Create'), DVStudioStyle.accent,
        reason: 'the primary action carries the accent');
  });

  testWidgets('a control narrower than its label shrinks the label', (
    WidgetTester tester,
  ) async {
    // A label is as long as a translation or a larger system font makes it,
    // and a control is as wide as the row it sits in allows. The label was
    // an inflexible text in a shrink-wrapped row, so a control given less
    // room than its label threw an overflow instead of cutting the label
    // short — and the Pro sections, which put controls in narrow toolbars,
    // hit it seventeen times before shortening every label to route around
    // it, which only moves the failure to the next caller.
    const String label = 'A label longer than its box';
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 90,
            child: DVStudioStyle.control(
              label,
              enabled: true,
              icon: DVStudioIcons.publish,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull,
        reason: 'a narrow control overflowed rather than shrinking its label');
    expect(find.text(label), findsOneWidget,
        reason: 'the label is cut short, not removed');
    expect(tester.getSize(find.text(label)).width, lessThanOrEqualTo(90));
  });

  testWidgets('with room, a control is as wide as its label needs', (
    WidgetTester tester,
  ) async {
    // The other half: the label only shrinks under pressure. In the test font
    // every glyph is as wide as the font is tall, so "Publish" at 13 pixels
    // is 91 pixels wide when nothing cuts it.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: DVStudioStyle.control(
            'Publish',
            enabled: true,
            icon: DVStudioIcons.publish,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text('Publish')).width, closeTo(91, 0.5));
  });
}
