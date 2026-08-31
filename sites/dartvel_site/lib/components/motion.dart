// Motion, and the one rule that governs all of it.
//
// Every animation here is off when the reader has asked for reduced motion.
// That is a system setting people turn on because movement makes them ill,
// and a site that ignores it is not being lively, it is being rude. It costs
// one check -- context.screen.reducedMotion -- which reads the platform
// setting as well as any explicit DV.Accessibility override.
//
// Reveal-on-scroll and lift-on-hover used to live here as StatefulWidgets.
// They are DVModifier.revealOnScroll() and DVModifier.hover() now: they are
// framework concerns, and having them here meant every application that
// wanted either wrote its own and remembered the reduced-motion check by hand.
//
// What is left is the two animations that are specific to this site, and
// neither needs a State: a tween that runs once on first build is exactly
// what TweenAnimationBuilder is.
import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';

/// Counts up to [value] the first time it is built.
///
/// A number that arrives already at rest is a number nobody reads. This is
/// the one place on the page where animation carries meaning rather than
/// decoration: it says the figure is a count of something.
@DVFunctionalWidget()
Widget _countUp(
  BuildContext context,
  String value, {
  double size = 42,
  Color color = const Color(0xFF2F6BFF),
}) {
  final int? target = int.tryParse(value);
  final DVModifier style = const DVModifier()
      .fontSize(size)
      .fontWeight(FontWeight.w800)
      .color(color)
      .height(1.05);

  // Not a whole number, or reduced motion: show it and stop.
  if (target == null || context.screen.reducedMotion) {
    return DVText(value).modifier(style);
  }

  return TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: target.toDouble()),
    duration: Duration(milliseconds: 700 + target * 12),
    curve: Curves.easeOutCubic,
    builder: (BuildContext context, double current, Widget? _) =>
        DVText(current.round().toString()).modifier(style),
  );
}

/// Types itself out, once.
///
/// The hero shows a command being run, and a command that is simply present
/// is a screenshot. This one arrives the way it would if you were watching
/// someone type it.
@DVFunctionalWidget()
Widget _typewriter(
  BuildContext context,
  List<TextSpan> spans, {
  TextStyle style = const TextStyle(fontFamily: 'RobotoMono', fontSize: 13.5),
  Duration perCharacter = const Duration(milliseconds: 13),
}) {
  final int length = spans.fold<int>(
      0, (int total, TextSpan span) => total + (span.text?.length ?? 0));

  /// The spans up to [count] characters, cutting the one it lands in.
  ///
  /// Local rather than a private top-level helper: the body is lowered into
  /// the generated widget, and a private symbol from this file cannot be
  /// reached from there.
  List<TextSpan> upTo(int count) {
    final List<TextSpan> out = <TextSpan>[];
    int remaining = count;
    for (final TextSpan span in spans) {
      final String text = span.text ?? '';
      if (remaining <= 0) break;
      if (text.length <= remaining) {
        out.add(span);
        remaining -= text.length;
      } else {
        out.add(
            TextSpan(text: text.substring(0, remaining), style: span.style));
        remaining = 0;
      }
    }
    return out;
  }

  // A reader with reduced motion on should never see the first character of
  // this: the finished line is there from the first frame.
  if (context.screen.reducedMotion || length == 0) {
    return SelectableText.rich(TextSpan(style: style, children: spans));
  }

  return TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: 1),
    duration: perCharacter * length,
    curve: Curves.linear,
    builder: (BuildContext context, double progress, Widget? _) =>
        SelectableText.rich(
      TextSpan(
        style: style,
        children: upTo((progress * length).round()),
      ),
    ),
  );
}
