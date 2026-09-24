// The Dartvel mark in Studio's rail: the D with the dart as its counter.
//
// The same path, in the same 512-unit space, as the SVGs in the site's
// assets/brand and the site header's DartvelMarkPainter, so Studio and
// dartvel.dev cannot drift into two different marks.
import 'package:flutter/widgets.dart';

/// Paints the Dartvel mark in its brand gradient, or flat in [color].
class DVStudioMarkPainter extends CustomPainter {
  const DVStudioMarkPainter([this.color]);

  final Color? color;

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

  static const Rect _bounds = Rect.fromLTRB(112, 100, 400, 412);

  @override
  void paint(Canvas canvas, Size size) {
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
        colors: <Color>[Color(0xFF7A2E10), Color(0xFFB03E19), Color(0xFFF0824B)],
        stops: <double>[0, 0.55, 1],
      ).createShader(_bounds);
    }
    canvas.drawPath(_d, paint);
    // The fold that turns the bowl away from the stem.
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
  bool shouldRepaint(DVStudioMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
