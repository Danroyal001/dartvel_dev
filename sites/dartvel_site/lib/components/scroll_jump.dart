// One button for every long page: to the bottom, and back to the top once
// the reader is there.
//
// Raw Flutter rather than a @DVFunctionalWidget, for the same reason the mark
// painter is: it owns a ScrollController and listens to it, which is state a
// functional widget has no place to keep.
import 'package:flutter/material.dart';

import 'site.dart' show Palette;

/// Gives the page inside it a scroll controller of its own, and a button that
/// jumps to the bottom or back to the top.
///
/// The page's main scroll view picks the controller up as its
/// PrimaryScrollController on every platform, the web's desktop browsers
/// included, where Flutter would otherwise leave it to mobile only. Scroll
/// views that are not the page -- the docs sidebar -- say `primary: false`.
class const PageScroll({super.key, required final Widget child})
    extends StatefulWidget {
  @override
  State<PageScroll> createState() => _PageScrollState();
}

class _PageScrollState extends State<PageScroll> {
  final ScrollController _controller = ScrollController();

  /// Below this much to scroll the page is short enough to see at a glance,
  /// and a button would only cover it.
  static const double _worthIt = 400;

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
      position.animateTo(target,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PrimaryScrollController(
      controller: _controller,
      automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
      // A page that grows as it loads changes how far there is to go
      // without scrolling, which the controller alone does not report.
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
                  if (_controller.positions.length != 1) {
                    return const SizedBox.shrink();
                  }
                  final ScrollPosition position = _controller.position;
                  if (!position.hasContentDimensions ||
                      position.maxScrollExtent < _worthIt) {
                    return const SizedBox.shrink();
                  }
                  final bool atBottom =
                      position.pixels >= position.maxScrollExtent - _slack;
                  return _JumpButton(
                    toTop: atBottom,
                    onTap: () => _jump(atBottom),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class const _JumpButton({
  required final bool toTop,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette palette = Palette.of(context);
    final String label = toTop ? 'Back to top' : 'To the bottom';
    return Tooltip(
      message: label,
      // The Semantics below already names this button. Tooltip publishes its
      // message as a label too, and the two merge into one node whose name is
      // the string twice -- which is what a screen reader reads out and what
      // the captured tree carried at the top of every page on the site.
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          key: const ValueKey<String>('scroll-jump'),
          color: palette.page,
          shape: CircleBorder(side: BorderSide(color: palette.rule)),
          elevation: 3,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                toTop ? Icons.arrow_upward : Icons.arrow_downward,
                size: 20,
                color: palette.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
