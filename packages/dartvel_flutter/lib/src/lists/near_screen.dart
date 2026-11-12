/// A row of a long DVBox list or grid that is built when it comes near the
/// screen.
///
/// A page is usually one scrolling list whose child is the page itself, and the
/// page holds the long collection: a catalogue of tools, a grid of products.
/// That collection does not scroll by itself, so it cannot be a ListView, and
/// it was built whole: every card of a 177-tool catalogue before the first
/// frame (sigmadev.digital crashed on a phone, 12 Nov 2026). A row stands in
/// for itself at an estimated height until the page has scrolled to within
/// two screens of it, then builds and stays built.
///
/// Built at once when nothing scrolls around it, and while the build captures
/// the page ([DVLazyLists.buildWhole]).
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'lazy_lists.dart';

class DVNearScreen extends StatefulWidget {
  const DVNearScreen({super.key, required this.child, this.estimatedHeight = 120});

  final Widget child;

  /// The height it holds before it is built, so the page's scroll length is
  /// roughly right. Rows are built two screens before they are seen, so the
  /// difference never shows.
  final double estimatedHeight;

  @override
  State<DVNearScreen> createState() => _DVNearScreenState();
}

class _DVNearScreenState extends State<DVNearScreen> {
  bool _built = DVLazyLists.buildWhole;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built) return;
    final ScrollPosition? position = Scrollable.maybeOf(context)?.position;
    if (position == null) {
      _built = true;
      return;
    }
    if (!identical(position, _position)) {
      _position?.removeListener(_check);
      _position = position..addListener(_check);
    }
    SchedulerBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_built || !mounted) return;
    final RenderObject? box = context.findRenderObject();
    final ScrollPosition? position = _position;
    if (box is! RenderBox || !box.attached || !box.hasSize || position == null || !position.hasViewportDimension) return;
    final RenderAbstractViewport? viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final double top = viewport.getOffsetToReveal(box, 0).offset;
    final double screen = position.viewportDimension;
    final bool near = top < position.pixels + screen * 3 && top + box.size.height > position.pixels - screen * 2;
    if (!near) return;
    _position?.removeListener(_check);
    _position = null;
    setState(() => _built = true);
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _built ? widget.child : SizedBox(height: widget.estimatedHeight);
}
