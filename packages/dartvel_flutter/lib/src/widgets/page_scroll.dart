/// The opt-in "To the bottom / Back to top" button for long pages.
///
/// dartvel.dev had it as a component of its own, so other Dartvel sites did
/// not (owner, 13 Nov 2026). An app turns it on with an attribute, not by
/// nesting a widget: `@DVFunctionalWidget(pageScroll: true)`, or
/// `pageScroll: true` on a DVClassWidget or DartvelLayout. [DVPageScrollFrame]
/// is what generated code and those classes put round the page; the button
/// takes the app theme's colours, light and dark.
library;

import 'package:flutter/material.dart';

/// Gives the page inside it a scroll controller of its own, and a round
/// button at the bottom right that jumps to the bottom, or back to the top
/// once the reader is there.
///
/// The page's main scroll view picks the controller up as its
/// PrimaryScrollController on every platform, desktop web included, where
/// Flutter would otherwise leave that to mobile. Scroll views that are not
/// the page (a sidebar) say `primary: false`. A page shorter than
/// [minimumScroll] of scrolling gets no button: it would only cover it.
class DVPageScrollFrame extends StatefulWidget {
  const DVPageScrollFrame({super.key, required this.child, this.minimumScroll = 400});

  final Widget child;

  /// How far a page must scroll before the button is worth showing.
  final double minimumScroll;

  @override
  State<DVPageScrollFrame> createState() => _DVPageScrollFrameState();
}

class _DVPageScrollFrameState extends State<DVPageScrollFrame> {
  final ScrollController _controller = ScrollController();

  /// Within this of the bottom counts as there.
  static const double _slack = 24;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _jump(bool toTop) {
    if (_controller.positions.length != 1) return;
    final ScrollPosition position = _controller.position;
    final double target = toTop ? 0 : position.maxScrollExtent;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      position.jumpTo(target);
    } else {
      position.animateTo(target, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PrimaryScrollController(
      controller: _controller,
      automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
      // A page that grows as it loads changes how far there is to go without
      // scrolling, which the controller alone does not report.
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (ScrollMetricsNotification _) {
          setState(() {});
          return false;
        },
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: widget.child),
            Positioned(
              right: 20,
              bottom: 20,
              child: ListenableBuilder(
                listenable: _controller,
                builder: (BuildContext context, Widget? _) {
                  if (_controller.positions.length != 1) return const SizedBox.shrink();
                  final ScrollPosition position = _controller.position;
                  if (!position.hasContentDimensions || position.maxScrollExtent < widget.minimumScroll) {
                    return const SizedBox.shrink();
                  }
                  final bool atBottom = position.pixels >= position.maxScrollExtent - _slack;
                  return _JumpButton(toTop: atBottom, onTap: () => _jump(atBottom));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JumpButton extends StatelessWidget {
  const _JumpButton({required this.toTop, required this.onTap});

  final bool toTop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final String label = toTop ? 'Back to top' : 'To the bottom';
    return Tooltip(
      message: label,
      // The Semantics below names the button; Tooltip would publish the same
      // message again and a screen reader would read the name twice.
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: Material(
          key: const ValueKey<String>('dv-page-scroll'),
          color: colours.surface,
          shape: CircleBorder(side: BorderSide(color: colours.outlineVariant)),
          elevation: 3,
          child: InkWell(
            customBorder: const CircleBorder(),
            mouseCursor: SystemMouseCursors.click,
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(toTop ? Icons.arrow_upward : Icons.arrow_downward, size: 20, color: colours.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
