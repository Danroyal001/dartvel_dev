// The Dartvel mark, drawn rather than loaded.
//
// A @DVFunctionalWidget like everything else the site is built from: Dartvel
// generates the class and its const constructor, and the header uses
// `DartvelMark(size: 24)` through the generated barrel.
//
// The painter below is the one piece of raw Flutter here, and it is here
// because the mark is a bezier path with an even-odd counter -- there is no
// primitive for that, and there should not be. Drawing a logo is not layout.
// A bitmap would have been the way to avoid it, and it would have to be
// picked per density and would still be soft on a display nobody sized it
// for; the path is exact at 22 points and at 220.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';

/// The mark, at [size] points square.
///
/// [color] draws it flat instead of in the brand gradient, for somewhere that
/// cannot take one -- a print stylesheet, a monochrome header.
@DVFunctionalWidget()
Widget _dartvelMark(BuildContext context, {double size = 22, Color? color}) =>
    DVBox(
      CustomPaint(painter: DartvelMarkPainter(color)),
      const DVModifier().width(size).height(size),
    );

/// The painter behind [DartvelMark].
///
/// Public because a @DVFunctionalWidget body is lowered into the generated
/// widget file, where a class private to this one cannot be seen. The
/// generator says so rather than emitting code that will not compile.
class DartvelMarkPainter extends CustomPainter {
  const DartvelMarkPainter(this.color);

  final Color? color;

  /// The D, with the dart as its counter.
  ///
  /// The same numbers the SVGs in `assets/brand` carry, in the same 512-unit
  /// space, so the header and the logo files can be compared line for line
  /// and cannot drift into two different marks. The counter is a second
  /// sub-path and the fill is even-odd, which is what makes it a hole rather
  /// than a shape sitting on top.
  static final Path _d = Path()
    ..fillType = PathFillType.evenOdd
    ..moveTo(112, 100)
    ..lineTo(256, 100)
    ..cubicTo(336, 100, 400, 170, 400, 256)
    ..cubicTo(400, 342, 336, 412, 256, 412)
    ..lineTo(112, 412)
    ..close()
    ..moveTo(176, 170)
    ..lineTo(256, 170)
    ..lineTo(320, 256)
    ..lineTo(256, 342)
    ..lineTo(176, 342)
    ..lineTo(240, 256)
    ..close();

  /// The mark's own bounds, which are not the 512 square it is drawn in.
  static const Rect _bounds = Rect.fromLTRB(112, 100, 400, 412);

  @override
  void paint(Canvas canvas, Size size) {
    // Fitted to the taller side so the mark keeps its proportions in a box
    // that is not square, and centred on whatever is left over.
    final double scale = size.shortestSide / _bounds.longestSide;
    canvas.save();
    canvas.translate(
      (size.width - _bounds.width * scale) / 2,
      (size.height - _bounds.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-_bounds.left, -_bounds.top);

    final Paint paint = Paint()..isAntiAlias = true;
    if (color != null) {
      paint.color = color!;
    } else {
      paint.shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFF7A3BFF),
          Color(0xFF2F6BFF),
          Color(0xFF1FB6F5),
        ],
        stops: <double>[0, 0.55, 1],
      ).createShader(_bounds);
    }
    canvas.drawPath(_d, paint);

    // The fold: the bowl turned away from the stem, which is the whole reason
    // the mark is not a flat letter. Clipped to the D so the crease stops
    // where the shape does. Left off a flat mark, where a shadow with no
    // gradient under it is a grey wedge.
    if (color == null) {
      canvas.clipPath(_d);
      canvas.drawPath(
        Path()
          ..moveTo(112, 412)
          ..lineTo(400, 140)
          ..lineTo(512, 140)
          ..lineTo(512, 512)
          ..lineTo(112, 512)
          ..close(),
        Paint()..color = const Color(0x330B1020),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DartvelMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
