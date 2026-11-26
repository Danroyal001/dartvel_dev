/// Paint that says what it paints: gradients over a box and gradient-filled
/// text, drawn by Flutter in the app and read back by the SSR-first capture
/// (`dartvel.web.ssrFirst`) so the server-rendered document draws the same
/// thing in CSS before the app starts.
///
/// A `CustomPainter` or a `ShaderMask` is code the capture cannot read: it
/// sees a box, not what was drawn in it, so a page whose hero glows come
/// from a painter changes at the handover. These are the same effects built
/// from values the capture can read:
///
/// * [DVRadialGradient], an elliptical radial gradient sized to the box, the
///   one CSS's `radial-gradient(60% 80% at 85% 0%, ...)` draws; usable
///   anywhere a Flutter `Gradient` is (`DVModifier.gradient`,
///   `BoxDecoration`);
/// * [DVGradientPainter], several gradients stacked over a box, and
///   [DVDescribedPainter], which any painter of an application's own
///   implements to say which gradients it draws;
/// * [DVGradientSpan] in a [DVGradientText], text filled with a gradient
///   that runs along its line pieces laid end to end, as CSS
///   `background-clip: text` on an inline element draws it.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A radial gradient whose ending shape is an ellipse sized to the box:
/// [radiusX] of its width across and [radiusY] of its height down, centred
/// at [center]. CSS `radial-gradient(60% 80% at 85% 0%, a, b 60%)` is
/// `DVRadialGradient(center: Alignment(0.7, -1), radiusX: 0.6, radiusY: 0.8,
/// colors: [a, b], stops: [0, 0.6])`.
///
/// Flutter's `RadialGradient` is a circle sized to the box's shorter side; a
/// glow that is wider than it is tall needs a transform, and a transform is
/// a matrix the capture cannot turn back into CSS. This one says its shape.
class DVRadialGradient extends Gradient {
  const DVRadialGradient({
    this.center = Alignment.center,
    this.radiusX = 0.5,
    this.radiusY = 0.5,
    required super.colors,
    super.stops,
  });

  final AlignmentGeometry center;

  /// The ellipse's horizontal radius, as a fraction of the box's width.
  final double radiusX;

  /// The ellipse's vertical radius, as a fraction of the box's height.
  final double radiusY;

  @override
  Shader createShader(Rect rect, {TextDirection? textDirection}) {
    final Offset centre = center.resolve(textDirection).withinRect(rect);
    final double across = math.max(0.001, radiusX * rect.width);
    final double down = math.max(0.001, radiusY * rect.height);
    // A circle of the horizontal radius, squashed or stretched to the
    // vertical one about the centre.
    final Matrix4 matrix = Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..scaleByDouble(1, down / across, 1, 1)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
    return ui.Gradient.radial(
      centre,
      across,
      colors,
      _stops,
      TileMode.clamp,
      matrix.storage,
    );
  }

  List<double>? get _stops {
    if (stops != null) return stops;
    if (colors.length == 2) return null;
    return <double>[
      for (int index = 0; index < colors.length; index++)
        index / (colors.length - 1),
    ];
  }

  @override
  DVRadialGradient scale(double factor) => DVRadialGradient(
    center: center,
    radiusX: radiusX,
    radiusY: radiusY,
    colors: <Color>[
      for (final Color colour in colors) Color.lerp(null, colour, factor)!,
    ],
    stops: stops,
  );

  @override
  DVRadialGradient withOpacity(double opacity) => DVRadialGradient(
    center: center,
    radiusX: radiusX,
    radiusY: radiusY,
    colors: <Color>[
      for (final Color colour in colors) colour.withValues(alpha: colour.a * opacity),
    ],
    stops: stops,
  );

  @override
  bool operator ==(Object other) =>
      other is DVRadialGradient &&
      other.center == center &&
      other.radiusX == radiusX &&
      other.radiusY == radiusY &&
      listEquals(other.colors, colors) &&
      listEquals(other.stops, stops);

  @override
  int get hashCode => Object.hash(
    center,
    radiusX,
    radiusY,
    Object.hashAll(colors),
    stops == null ? null : Object.hashAll(stops!),
  );
}

/// A painter that says what it paints: the gradients, bottom first, that
/// fill its box. The SSR-first capture draws them under (or, for a
/// `foregroundPainter`, over) the box's content, so the document shows them
/// before the app starts. Whatever else the painter draws is not described
/// and appears at the handover.
abstract interface class DVDescribedPainter {
  /// The gradients over a box of [size], bottom first. Each fills the box.
  List<Gradient> describePaint(Size size);
}

/// The outline a painter fills, as SVG path data in the box's own pixels
/// (0, 0 at its top left), filled even-odd when [evenOdd] (a letter with a
/// counter) and non-zero otherwise.
class DVShape {
  const DVShape(this.path, {this.evenOdd = false});

  /// SVG path data: `M`, `L`, `C`, `Q`, `A`, `Z` and the rest, with numbers.
  final String path;
  final bool evenOdd;
}

/// A [DVDescribedPainter] whose gradients fill an outline rather than the
/// whole box: a logo drawn as a path. The SSR-first document clips the box
/// to it (CSS `clip-path: path(...)`), so the mark is there from the first
/// paint instead of appearing at the handover.
abstract interface class DVDescribedShape {
  /// The outline over a box of [size]; null fills the box.
  DVShape? describeShape(Size size);
}

/// Gradients stacked over a box, bottom first: two soft glows behind a hero,
/// a sheen over a card. Use it as a `CustomPaint`'s painter; the SSR-first
/// document draws the same layers in CSS.
class DVGradientPainter extends CustomPainter implements DVDescribedPainter {
  const DVGradientPainter(this.layers);

  /// Bottom first; each fills the box.
  final List<Gradient> layers;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect box = Offset.zero & size;
    for (final Gradient layer in layers) {
      canvas.drawRect(box, Paint()..shader = layer.createShader(box));
    }
  }

  @override
  List<Gradient> describePaint(Size size) => layers;

  @override
  bool shouldRepaint(DVGradientPainter oldDelegate) =>
      !listEquals(oldDelegate.layers, layers);
}

/// A run of text filled with [gradient] rather than its colour, inside a
/// [DVGradientText]. The gradient runs along the run's line pieces laid end
/// to end, the way CSS draws `background-clip: text` on an inline element
/// that wraps: a run over two lines fades across both, not on each.
///
/// A `LinearGradient` is drawn the way CSS draws `linear-gradient(<angle>)`,
/// the angle being the direction from its `begin` to its `end`, over a strip
/// as long as the run and one line high.
class DVGradientSpan extends TextSpan {
  const DVGradientSpan({
    required String super.text,
    required this.gradient,
    super.style,
    super.semanticsLabel,
  });

  final Gradient gradient;

  @override
  bool operator ==(Object other) =>
      other is DVGradientSpan &&
      other.gradient == gradient &&
      super == other;

  @override
  int get hashCode => Object.hash(super.hashCode, gradient);
}

/// Text in which [DVGradientSpan] runs are filled with their gradients and
/// every other run keeps its colour. It is one paragraph, selectable and
/// read as one by a screen reader, as a `Text.rich` is.
class DVGradientText extends StatelessWidget {
  const DVGradientText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final InlineSpan text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final Widget paragraph = Text.rich(
      text,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
    if (!_hasGradient(text)) return paragraph;
    final DefaultTextStyle inherited = DefaultTextStyle.of(context);
    final TextStyle effective = inherited.style.merge(style);
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final TextDirection direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (Rect bounds) => dvGradientTextMask(
          text,
          style: effective,
          textAlign: textAlign ?? inherited.textAlign ?? TextAlign.start,
          textDirection: direction,
          textScaler: scaler,
          maxLines: maxLines ?? inherited.maxLines,
          maxWidth: box.maxWidth,
          size: bounds.size,
        ),
        child: paragraph,
      ),
    );
  }
}

bool _hasGradient(InlineSpan span) {
  bool found = false;
  span.visitChildren((InlineSpan child) {
    if (child is DVGradientSpan) found = true;
    return !found;
  });
  return found;
}

/// The mask a [DVGradientText] paints its paragraph through: each run's own
/// colour where it is, and each gradient run's gradient along its line
/// pieces laid end to end. Public for tests.
Shader dvGradientTextMask(
  InlineSpan text, {
  required TextStyle style,
  required TextAlign textAlign,
  required TextDirection textDirection,
  required TextScaler textScaler,
  int? maxLines,
  required double maxWidth,
  required Size size,
}) {
  final TextPainter painter = TextPainter(
    text: TextSpan(style: style, children: <InlineSpan>[text]),
    textAlign: textAlign,
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: maxLines,
  )..layout(maxWidth: maxWidth.isFinite ? maxWidth : size.width);

  // Each run: where it is in the plain text, and its colour or gradient.
  final List<(int, int, Color, Gradient?)> runs = <(int, int, Color, Gradient?)>[];
  int offset = 0;
  void walk(InlineSpan span, TextStyle inherited) {
    final TextStyle own = span.style == null ? inherited : inherited.merge(span.style);
    if (span is TextSpan) {
      final String? value = span.text;
      if (value != null && value.isNotEmpty) {
        runs.add((
          offset,
          offset + value.length,
          own.color ?? const Color(0xFF000000),
          span is DVGradientSpan ? span.gradient : null,
        ));
        offset += value.length;
      }
      for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
        walk(child, own);
      }
    } else {
      offset += 1; // A placeholder is one character.
    }
  }

  walk(text, style);

  final double width = math.max(1, size.width), height = math.max(1, size.height);
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = style.color ?? const Color(0xFF000000),
  );
  for (final (int start, int end, Color colour, Gradient? gradient) in runs) {
    final List<TextBox> pieces = _linePieces(
      painter.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end)),
    );
    if (pieces.isEmpty) continue;
    if (gradient == null) {
      for (final TextBox piece in pieces) {
        canvas.drawRect(piece.toRect(), Paint()..color = colour);
      }
      continue;
    }
    final double strip = pieces.fold(0, (double sum, TextBox piece) => sum + piece.right - piece.left);
    final double line = pieces.first.bottom - pieces.first.top;
    double along = 0;
    for (final TextBox piece in pieces) {
      // The strip of every piece laid end to end, placed so this piece's
      // part of it is under this piece.
      final Rect whole = Rect.fromLTWH(piece.left - along, piece.top, strip, line);
      canvas.drawRect(
        piece.toRect(),
        Paint()..shader = _stripShader(gradient, whole, textDirection),
      );
      along += piece.right - piece.left;
    }
  }
  painter.dispose();
  final ui.Image mask = recorder.endRecording().toImageSync(width.ceil(), height.ceil());
  return ui.ImageShader(mask, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage);
}

/// [boxes] with the pieces on one line joined: one box per line.
List<TextBox> _linePieces(List<TextBox> boxes) {
  final List<TextBox> lines = <TextBox>[];
  for (final TextBox piece in boxes) {
    if (lines.isNotEmpty && (lines.last.top - piece.top).abs() < 1) {
      final TextBox last = lines.removeLast();
      lines.add(TextBox.fromLTRBD(
        math.min(last.left, piece.left),
        last.top,
        math.max(last.right, piece.right),
        math.max(last.bottom, piece.bottom),
        last.direction,
      ));
    } else {
      lines.add(piece);
    }
  }
  return lines;
}

/// [gradient] over [strip] as CSS draws it: a linear gradient by its angle
/// along CSS's gradient line, anything else by its own shader.
Shader _stripShader(Gradient gradient, Rect strip, TextDirection direction) {
  if (gradient is! LinearGradient) {
    return gradient.createShader(strip, textDirection: direction);
  }
  final double radians = dvCssGradientAngle(gradient, direction) * math.pi / 180;
  final double across = math.sin(radians), down = -math.cos(radians);
  // CSS's gradient line: through the centre, as long as the box projects
  // onto it.
  final double half = (strip.width * across.abs() + strip.height * down.abs()) / 2;
  final Offset step = Offset(across * half, down * half);
  return ui.Gradient.linear(
    strip.center - step,
    strip.center + step,
    gradient.colors,
    gradient.stops,
  );
}

/// The CSS angle of [gradient] (degrees clockwise from "to top"): the
/// direction from its `begin` to its `end`, as alignments.
double dvCssGradientAngle(LinearGradient gradient, [TextDirection direction = TextDirection.ltr]) {
  final Alignment begin = gradient.begin.resolve(direction);
  final Alignment end = gradient.end.resolve(direction);
  final double degrees = math.atan2(end.x - begin.x, -(end.y - begin.y)) * 180 / math.pi;
  return (degrees + 360) % 360;
}
