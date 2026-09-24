// The brand, drawn.
//
// The same geometry the SVGs in assets/brand carry, in the same coordinate
// boxes, so a number here and a number there are the same number.
// `test/brand_geometry_test.dart` reads both and says so.
//
// Why Dart and not the SVG: nothing on the PATH here renders these files
// correctly, and an exported raster that quietly loses the gradient is worse
// than no export. The site already draws the mark this way for the page, so
// the paths were half written before this existed.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The mark's box, and the badge's.
const Size kMarkBox = Size(512, 512);

/// The horizontal lockup's box.
const Size kLockupBox = Size(892, 264);

/// The social card's box.
const Size kCardBox = Size(1200, 630);

/// The brand gradient: deep clay, the accent, ember.
///
/// Three stops rather than two because the fold across the bowl is read as a
/// change in value, and a two-stop ramp across a shape this small does not
/// give it enough to turn against.
const List<Color> kBrandStops = <Color>[
  Color(0xFF7A2E10),
  Color(0xFFB03E19),
  Color(0xFFF0824B),
];

const List<double> kBrandOffsets = <double>[0, 0.55, 1];

/// The ink the fold and the wordmark are drawn in.
const Color kInk = Color(0xFF191210);

/// The paper the wordmark takes on a dark ground.
const Color kPaper = Color(0xFFF6F1EA);

/// The quiet text on the social card.
const Color kCardMuted = Color(0xFFB5A697);

/// The D, with the dart as its counter. Even-odd, so the counter is a hole.
Path dartvelD() => Path()
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

/// The fold: the bowl turned away from the stem, clipped to the D.
Path dartvelFold() => Path()
  ..moveTo(112, 412)
  ..lineTo(400, 140)
  ..lineTo(512, 140)
  ..lineTo(512, 512)
  ..lineTo(112, 512)
  ..close();

Shader _brandShader(Rect bounds) => ui.Gradient.linear(
      bounds.topLeft,
      bounds.bottomRight,
      kBrandStops,
      kBrandOffsets,
    );

/// The mark on its own, transparent behind it.
void paintMark(Canvas canvas, Size size) {
  final Path d = dartvelD();
  canvas.drawPath(
    d,
    Paint()
      ..isAntiAlias = true
      ..shader = _brandShader(d.getBounds()),
  );
  canvas.save();
  canvas.clipPath(d);
  canvas.drawPath(
    dartvelFold(),
    Paint()
      ..isAntiAlias = true
      ..color = kInk.withValues(alpha: 0.20),
  );
  canvas.restore();
}

/// The app icon: a rounded tile of the gradient with the mark knocked out.
///
/// Flat, with no fold. Below about 64 points the crease turns into a grey
/// smudge across the white D and costs more than it adds.
void paintBadge(Canvas canvas, Size size) {
  final Rect tile = Offset.zero & size;
  canvas.drawRRect(
    RRect.fromRectAndRadius(tile, const Radius.circular(116)),
    Paint()
      ..isAntiAlias = true
      ..shader = _brandShader(tile),
  );
  _knockOutMark(canvas, size, scale: 0.82);
}

/// The maskable form: square to the edge, and the mark smaller inside it,
/// because the launcher picks the shape and crops into whatever it likes.
void paintMaskableBadge(Canvas canvas, Size size) {
  final Rect tile = Offset.zero & size;
  canvas.drawRect(
    tile,
    Paint()
      ..isAntiAlias = true
      ..shader = _brandShader(tile),
  );
  _knockOutMark(canvas, size, scale: 0.6);
}

void _knockOutMark(Canvas canvas, Size size, {required double scale}) {
  canvas.save();
  canvas.translate(size.width / 2, size.height / 2);
  canvas.scale(scale);
  canvas.translate(-size.width / 2, -size.height / 2);
  canvas.drawPath(
    dartvelD(),
    Paint()
      ..isAntiAlias = true
      ..color = const Color(0xFFFFFFFF),
  );
  canvas.restore();
}

/// The wordmark, drawn rather than set: constant-width strokes on a
/// geometric skeleton, so it needs no font and cannot be substituted by one.
void paintWordmark(Canvas canvas, Color color) {
  final Paint stroke = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = 24
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color;

  canvas.save();
  canvas.translate(20, 12);

  // d
  canvas.drawCircle(const Offset(54, 96), 36, stroke);
  canvas.drawLine(const Offset(102, 12), const Offset(102, 132), stroke);

  // a
  canvas.save();
  canvas.translate(134, 0);
  canvas.drawCircle(const Offset(54, 96), 36, stroke);
  canvas.drawLine(const Offset(102, 60), const Offset(102, 132), stroke);
  canvas.restore();

  // r
  canvas.save();
  canvas.translate(268, 0);
  canvas.drawLine(const Offset(12, 60), const Offset(12, 132), stroke);
  canvas.drawPath(
    Path()
      ..moveTo(12, 92)
      ..arcToPoint(const Offset(54, 60), radius: const Radius.circular(38)),
    stroke,
  );
  canvas.restore();

  // t
  canvas.save();
  canvas.translate(340, 0);
  canvas.drawPath(
    Path()
      ..moveTo(36, 30)
      ..lineTo(36, 106)
      ..arcToPoint(const Offset(62, 132),
          radius: const Radius.circular(26), clockwise: false),
    stroke,
  );
  canvas.drawLine(const Offset(10, 60), const Offset(64, 60), stroke);
  canvas.restore();

  // v
  canvas.save();
  canvas.translate(424, 0);
  canvas.drawPath(
    Path()
      ..moveTo(12, 60)
      ..lineTo(42, 132)
      ..lineTo(72, 60),
    stroke,
  );
  canvas.restore();

  // e
  canvas.save();
  canvas.translate(510, 0);
  canvas.drawPath(
    Path()
      ..moveTo(18, 96)
      ..lineTo(90, 96)
      ..arcToPoint(const Offset(66, 130),
          radius: const Radius.circular(36), largeArc: true, clockwise: false),
    stroke,
  );
  canvas.restore();

  // l
  canvas.save();
  canvas.translate(632, 0);
  canvas.drawLine(const Offset(12, 12), const Offset(12, 132), stroke);
  canvas.restore();

  canvas.restore();
}

/// The horizontal lockup: the mark, then the name.
void paintLockup(Canvas canvas, Size size, {required bool onDark}) {
  if (onDark) {
    canvas.drawRect(Offset.zero & size, Paint()..color = kInk);
  }
  canvas.save();
  canvas.translate(-39.8, -32.1);
  canvas.scale(0.641);
  paintMark(canvas, kMarkBox);
  canvas.restore();

  canvas.save();
  canvas.translate(236.8, 55);
  canvas.scale(0.9167);
  paintWordmark(canvas, onDark ? kPaper : kInk);
  canvas.restore();
}

/// The card a link to the site unfurls into.
///
/// The ground is the deep warm ink the site's own dark bands use, and the
/// texture is grain. It used to be a radial bloom of the accent over navy,
/// which is the first thing the article about generated interfaces names.
void paintSocialCard(Canvas canvas, Size size) {
  canvas.drawRect(Offset.zero & size, Paint()..color = kInk);

  canvas.save();
  canvas.translate(192, 173);
  canvas.scale(0.75);
  canvas.translate(-112, -100);
  paintMark(canvas, kMarkBox);
  canvas.restore();

  canvas.save();
  canvas.translate(478, 225);
  canvas.scale(0.78);
  paintWordmark(canvas, kPaper);
  canvas.restore();

  final TextPainter tagline = TextPainter(
    text: const TextSpan(
      text: 'Flutter, full stack.',
      style: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 32,
        letterSpacing: 1,
        color: kCardMuted,
        fontWeight: FontWeight.w500,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tagline.paint(
    canvas,
    Offset((size.width - tagline.width) / 2, 486 - tagline.height * 0.8),
  );
  tagline.dispose();
}
