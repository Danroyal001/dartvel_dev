import 'dart:async';

import 'package:flutter/material.dart';

/// Motion, and the one rule that governs all of it.
///
/// Every animation here is off when the reader has asked for reduced motion.
/// That is a system setting people turn on because movement makes them ill,
/// and a site that ignores it is not being lively, it is being rude. Flutter
/// surfaces it as `MediaQuery.disableAnimations`, so it costs one check.
class Motion {
  const Motion._();

  static bool enabled(BuildContext context) =>
      !MediaQuery.of(context).disableAnimations;
}

/// Fade and rise as it comes into view.
///
/// The section is laid out at full size from the first frame and only its
/// opacity and offset animate, so nothing reflows and the scrollbar does not
/// jump while the page settles.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 26,
  });

  final Widget child;

  /// A stagger, for a row of cards that should not all arrive at once.
  final Duration delay;

  /// How far it rises, in logical pixels.
  final double offset;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> {
  bool _shown = false;
  bool _scheduled = false;
  Timer? _failsafe;

  void _reveal() {
    if (_scheduled) return;
    _scheduled = true;
    Future<void>.delayed(widget.delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  void _check() {
    if (_shown || _scheduled) return;
    final RenderObject? box = context.findRenderObject();
    // No size yet. On Flutter web the first frames arrive before layout, so
    // this is the normal case on load rather than an edge -- and retrying is
    // what makes it recoverable.
    if (box is! RenderBox || !box.hasSize) return;

    final double top = box.localToGlobal(Offset.zero).dy;
    final double height = MediaQuery.sizeOf(context).height;
    // A little above the bottom edge: any earlier and the animation finishes
    // before it is on screen, any later and the reader watches it happen
    // instead of arriving to it already done.
    if (top < height * 0.88) _reveal();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Every frame until it is shown, not once. The first version checked a
    // single time after mount, and on web that ran before the render object
    // had a size -- so it returned early, nothing retried without a scroll,
    // and the section below the hero stayed blank for as long as the page
    // was open. Content a decoration can hide permanently is a worse bug
    // than no decoration.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());

    // And a fallback, so this always fails open. If the check never gets a
    // usable position -- no scrollable ancestor, a layout it does not
    // anticipate -- the content appears anyway.
    _failsafe ??= Timer(const Duration(milliseconds: 1600), () {
      if (mounted) _reveal();
    });
  }

  @override
  void dispose() {
    _failsafe?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Motion.enabled(context)) return widget.child;

    if (!_shown) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        _check();
        // False: this is watching, not consuming. Returning true would stop
        // the notification reaching the scrollbar and any Reveal above it.
        return false;
      },
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : Offset(0, widget.offset / 100),
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOut,
          // Load-bearing. Opacity 0 drops its children from the semantics
          // tree, and a reveal-on-scroll starts every section at 0 -- so the
          // crawler-visible HTML, which is built from that tree, lost every
          // section the reader had not reached. The docs page went from nine
          // headings and nine code blocks to one of each, silently.
          //
          // It is also right for a screen reader: this animation is
          // decoration, and content should not be unreachable because nobody
          // has scrolled past it yet.
          alwaysIncludeSemantics: true,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Lifts under the pointer.
///
/// The card gains a shadow and a couple of pixels of height. Small on
/// purpose: a card that jumps is a card that draws attention away from the
/// one being read.
class Lift extends StatefulWidget {
  const Lift({super.key, required this.builder});

  /// Given whether the pointer is over it, so the caller decides what changes.
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<Lift> createState() => _LiftState();
}

class _LiftState extends State<Lift> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final bool animate = Motion.enabled(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _over = true),
      onExit: (_) => setState(() => _over = false),
      child: AnimatedSlide(
        offset: _over && animate ? const Offset(0, -0.014) : Offset.zero,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: widget.builder(context, _over),
      ),
    );
  }
}

/// Counts up to [value] the first time it is seen.
///
/// A number that arrives already at rest is a number nobody reads. This is
/// the one place on the page where animation carries meaning rather than
/// decoration: it says the figure is a count of something.
class CountUp extends StatelessWidget {
  const CountUp(this.value, {super.key, required this.style});

  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final int? target = int.tryParse(value);
    // Not a whole number, or reduced motion: show it and stop.
    if (target == null || !Motion.enabled(context)) {
      return Text(value, style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target.toDouble()),
      duration: Duration(milliseconds: 700 + target * 12),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double current, Widget? _) => Text(
        current.round().toString(),
        style: style,
      ),
    );
  }
}

/// Types itself out, once.
///
/// The hero shows a command being run, and a command that is simply present
/// is a screenshot. This one arrives the way it would if you were watching
/// someone type it.
class Typewriter extends StatefulWidget {
  const Typewriter({
    super.key,
    required this.spans,
    required this.style,
    this.perCharacter = const Duration(milliseconds: 13),
  });

  /// The finished text, already coloured. Revealed left to right.
  final List<TextSpan> spans;
  final TextStyle style;
  final Duration perCharacter;

  @override
  State<Typewriter> createState() => _TypewriterState();
}

class _TypewriterState extends State<Typewriter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final int _length;

  @override
  void initState() {
    super.initState();
    _length = widget.spans.fold<int>(
        0, (int total, TextSpan span) => total + (span.text?.length ?? 0));
    _controller = AnimationController(
      vsync: this,
      duration: widget.perCharacter * _length,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Started here rather than in initState: MediaQuery is not available yet
    // in initState, and a reader with reduced motion on should never see the
    // first character of this.
    if (!Motion.enabled(context)) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The spans up to [count] characters, cutting the one it lands in.
  List<TextSpan> _upTo(int count) {
    final List<TextSpan> out = <TextSpan>[];
    var remaining = count;
    for (final TextSpan span in widget.spans) {
      final String text = span.text ?? '';
      if (remaining <= 0) break;
      if (text.length <= remaining) {
        out.add(span);
        remaining -= text.length;
      } else {
        out.add(TextSpan(text: text.substring(0, remaining), style: span.style));
        remaining = 0;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? _) {
          final int shown = (_controller.value * _length).round();
          return SelectableText.rich(
            TextSpan(style: widget.style, children: _upTo(shown)),
          );
        },
      );
}
