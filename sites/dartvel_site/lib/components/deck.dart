import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dartvel_client/dartvel_client.dart';
import 'site.dart';

/// A page that moves a section at a time, with a rail showing where you are.
///
/// Built on a scroll view over a Column rather than a PageView, and that is
/// the load-bearing decision. A PageView instantiates the pages around the
/// current one and nothing else, so the crawler-visible HTML -- which is
/// generated from the semantics tree of a real browser -- would contain
/// whichever two slides happened to be built. A Column builds all of them, and
/// PageScrollPhysics still snaps, because snapping is a property of the
/// physics and not of the widget.
class Deck extends StatefulWidget {
  const Deck({super.key, required this.slides, this.topInset = 0});

  /// Each slide's rail label and its content.
  final List<(String, Widget)> slides;

  /// Room at the top of every slide for a header floating over the deck.
  final double topInset;

  @override
  State<Deck> createState() => _DeckState();
}

class _DeckState extends State<Deck> {
  final ScrollController _controller = ScrollController();
  final FocusNode _keys = FocusNode();
  int _current = 0;
  double _extent = 0;
  DateTime? _lastMove;

  @override
  void dispose() {
    _controller.dispose();
    _keys.dispose();
    super.dispose();
  }

  /// One slide per flick, with a cooldown.
  ///
  /// A trackpad sends a stream of small deltas for a single gesture. Without
  /// the cooldown one swipe would run through the whole deck; without the
  /// threshold, the drift in a diagonal gesture would count as intent.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final double delta = event.scrollDelta.dy;
    if (delta.abs() < 4) return;
    final DateTime now = DateTime.now();
    if (_lastMove != null &&
        now.difference(_lastMove!) < const Duration(milliseconds: 620)) {
      return;
    }
    _lastMove = now;
    _goTo(_current + (delta > 0 ? 1 : -1));
  }

  void _goTo(int index) {
    final int target = index.clamp(0, widget.slides.length - 1);
    if (_extent <= 0) return;
    if (target == _current) return;
    setState(() => _current = target);
    final double offset = target * _extent;
    if (!context.screen.reducedMotion) {
      _controller.animateTo(
        offset,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _controller.jumpTo(offset);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // The keys a deck is expected to answer. Without these the rail is
    // reachable by mouse and by nothing else.
    final Set<LogicalKeyboardKey> forward = <LogicalKeyboardKey>{
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.space,
    };
    final Set<LogicalKeyboardKey> back = <LogicalKeyboardKey>{
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.pageUp,
    };
    if (forward.contains(event.logicalKey)) {
      _goTo(_current + 1);
      return KeyEventResult.handled;
    }
    if (back.contains(event.logicalKey)) {
      _goTo(_current - 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.home) {
      _goTo(0);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      _goTo(widget.slides.length - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final DVScreenInfo screen = context.screen;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _extent = constraints.maxHeight;

        return Focus(
          focusNode: _keys,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            children: <Widget>[
              Listener(
                onPointerSignal: _onPointerSignal,
                child: GestureDetector(
                  // Touch, where there is no wheel. The direction of the
                  // flick is what matters, not how far it went.
                  onVerticalDragEnd: (DragEndDetails details) {
                    final double velocity =
                        details.velocity.pixelsPerSecond.dy;
                    if (velocity.abs() < 120) return;
                    _goTo(_current + (velocity < 0 ? 1 : -1));
                  },
                  child: SingleChildScrollView(
                  controller: _controller,
                  // Driven entirely by _goTo. PageScrollPhysics was the
                  // obvious choice and is wrong here: a wheel notch is about
                  // 120px against a slide of 800-odd, so every notch is under
                  // half a page and carries no fling velocity -- the physics
                  // snapped each one straight back and the deck could not be
                  // moved by a mouse at all.
                  //
                  // A deck moves one slide per flick, which is a decision
                  // about intent rather than distance, so the scroll view
                  // does not get a say.
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    children: <Widget>[
                      for (final (String, Widget) entry in widget.slides)
                        // A minimum, not a fixed height. A slide that fits is
                        // exactly one screen and snaps cleanly; one that is
                        // taller grows, and the deck's own scroll reaches all
                        // of it.
                        //
                        // No scroll view of its own, deliberately. Nesting one
                        // per slide meant the inner view took every wheel
                        // event and the deck never advanced -- and a slide
                        // with a fixed height would have clipped its content
                        // on a short window with no way to reach the rest.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                            minWidth: double.infinity,
                          ),
                          child: Padding(
                            padding: EdgeInsets.only(top: widget.topInset),
                            child: Center(child: entry.$2),
                          ),
                        ),
                    ],
                  ),
                  ),
                ),
              ),
              if (!screen.isMobile)
                Positioned(
                  right: 26,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Rail(
                      labels: <String>[
                        for (final (String, Widget) entry in widget.slides)
                          entry.$1,
                      ],
                      current: _current,
                      onTap: _goTo,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The dots down the right, and where you are among them.
@DVFunctionalWidget()
Widget _rail(
  BuildContext context, {
  required List<String> labels,
  required int current,
  required void Function(int index) onTap,
}) =>
    DVBox.list(<Widget>[
      for (int i = 0; i < labels.length; i++)
        Dot(
          label: labels[i],
          active: i == current,
          onTap: () => onTap(i),
        ),
    ], spacing: 0, crossAlign: DVCrossAlign.end);

/// One position on the rail.
///
/// The label appears on hover as well as when active, which is a sibling of
/// the indicator rather than the indicator itself -- so this reads the hover
/// through DVModifier.onHoverChanged into a signal rather than owning a
/// State to hold it.
@DVFunctionalWidget()
Widget _dot(
  BuildContext context, {
  required String label,
  required bool active,
  required VoidCallback onTap,
}) {
  final Palette palette = Palette.of(context);
  final DVSignal<bool> over = context.signal(false);
  final bool show = over.value || active;

  return DVBox(
    DVBox.row(<Widget>[
      DVBox(
        DVText(label).modifier(const DVModifier()
            .fontSize(11.5)
            .fontWeight(FontWeight.w700)
            .letterSpacing(0.6)
            .color(active ? palette.accent : palette.muted)),
        const DVModifier().opacity(show ? 1 : 0).paddingOnly(right: 10),
      ),
      // A bar rather than a dot when active: it reads as a position on a
      // track, which is what it is.
      DVBox(
        const DVBox(),
        const DVModifier()
            .width(active ? 26 : 12)
            .height(active ? 4 : 3)
            // rule is the colour of a hairline between sections and is
            // invisible as a control. An indicator nobody can see is not an
            // indicator.
            .backgroundColor(active
                ? palette.accent
                : (over.value ? palette.ink : palette.faint))
            .rounded(999)
            .animate(const Duration(milliseconds: 220)),
      ),
    ], align: DVAlign.end),
    const DVModifier()
        .paddingSymmetric(vertical: 7)
        .onHoverChanged((bool value) => over.value = value)
        .onTap(onTap)
        // A real label, not a decorative dot: this is how the rail is
        // announced and how it is reached without a mouse.
        .semanticLabel('Go to $label')
        .semanticButton()
        .minimumTapTarget(),
  );
}
