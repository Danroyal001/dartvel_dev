// Scrolling a DVBox.scrollableList must not repaint what it scrolls.
//
// A page is usually one scrollable column (a site's layout puts the page and
// its footer in one), and SingleChildScrollView paints its child inside its
// own paint. With nothing between them every scroll frame re-recorded the
// whole page -- every line of text, on screen or not -- and the renderer
// replayed all of it. On a low-end phone that was most of each frame.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingPainter extends CustomPainter {
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) => paints++;

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}

void main() {
  testWidgets('scrolling the list repaints none of its content',
      (WidgetTester tester) async {
    final _CountingPainter painter = _CountingPainter();
    await tester.pumpWidget(Directionality(
      textDirection: .ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(400, 600)),
        child: DVBox.scrollableList(<Widget>[
          CustomPaint(painter: painter, size: const Size(400, 3000)),
        ]),
      ),
    ));
    final int afterFirstFrame = painter.paints;
    expect(afterFirstFrame, greaterThan(0));

    await tester.drag(find.byType(CustomPaint).first, const Offset(0, -300));
    await tester.pump();
    await tester.drag(find.byType(CustomPaint).first, const Offset(0, -300));
    await tester.pump();

    expect(painter.paints, afterFirstFrame,
        reason: 'the content is unchanged; only its offset moved');
  });
}
