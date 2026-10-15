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
// What is left is the one animation that is specific to this site, and it
// needs no State: a tween that runs once on first build is exactly what
// TweenAnimationBuilder is. The hero's typewriter went with the terminal it
// typed into; the hero runs real code now instead of acting out a command.
import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';
import 'site.dart';

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
  Color? color,
}) {
  final int? target = int.tryParse(value);
  final DVModifier style = const DVModifier()
      .fontSize(size)
      .fontWeight(.w700)
      // The palette's, unless a caller on a dark band says otherwise. It
      // used to default to a hard-coded blue, which is how the accent came
      // to exist in four places at once.
      .color(color ?? Palette.of(context).accent)
      .lineHeight(1.05);

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
