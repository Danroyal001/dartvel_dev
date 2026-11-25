/// The list a scrollable DVBox list is: rows built near the screen, and on
/// the web the rest built while the page is idle.
///
/// A ListView builds the rows within its cache extent of the screen, a
/// quarter of a screen or so, and nothing past it: no element, no semantics
/// node, no text. On the web that left the end of a page -- a layout's
/// footer, the bottom of a long page -- out of reach of a screen reader's
/// line-by-line reading and of the browser's find after a navigation inside
/// the app (Tori and Learnacer, Dartvel 3.47.7). So when the page is idle the
/// cache extent grows a couple of screens at a time until it covers the whole
/// list (backfill.dart); from then on every row is built and stays built,
/// and Flutter reports every row's semantics, the ones off screen marked
/// hidden as it always does. The first frame builds exactly what it did.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'backfill.dart';

class DVLazyListView extends StatefulWidget {
  const DVLazyListView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.separatorBuilder,
    this.itemExtentBuilder,
    this.separatorExtent = 0,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Between two rows, when the list is spaced.
  final IndexedWidgetBuilder? separatorBuilder;

  /// Each row's extent along the scroll, by row index (separators are not
  /// counted). Called only for an index below [itemCount].
  final double Function(int index, SliverLayoutDimensions dimensions)? itemExtentBuilder;

  /// How long a separator is along the scroll, when [itemExtentBuilder] is
  /// set: Flutter asks a separated list's builder about separators too, and
  /// this list answers for them itself.
  final double separatorExtent;

  @override
  State<DVLazyListView> createState() => _DVLazyListViewState();
}

class _DVLazyListViewState extends State<DVLazyListView> implements DVBackfillable {
  final GlobalKey _listKey = GlobalKey();

  /// How far past the screen rows are built; null for Flutter's default.
  double? _cacheExtent;

  @override
  void initState() {
    super.initState();
    DVLazyBackfill.register(this);
  }

  @override
  void didUpdateWidget(DVLazyListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // More rows may be waiting than there were.
    if (widget.itemCount != oldWidget.itemCount) DVLazyBackfill.register(this);
  }

  @override
  void dispose() {
    DVLazyBackfill.unregister(this);
    super.dispose();
  }

  ScrollPosition? _position() {
    ScrollPosition? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is ScrollableState) {
        found = (element.state as ScrollableState).position;
        return;
      }
      element.visitChildElements(visit);
    }

    final BuildContext? list = _listKey.currentContext;
    if (list is Element) visit(list);
    return found;
  }

  @override
  bool backfillStep() {
    if (!mounted) return false;
    final ScrollPosition? position = _position();
    // Not laid out yet: another step will look again.
    if (position == null || !position.hasContentDimensions || !position.hasViewportDimension) return true;
    final double screen = position.viewportDimension;
    // The cache reaches this far on both sides of the screen, so the whole
    // list is covered, wherever it is scrolled, once it is as long as the
    // part of the list off screen. That length is the list's estimate, which
    // firms up as rows are built, so it is read again at every step.
    final double whole = position.maxScrollExtent - position.minScrollExtent;
    final double now = _cacheExtent ?? RenderAbstractViewport.defaultCacheExtent;
    if (now >= whole) return false;
    setState(() => _cacheExtent = now + screen * 2);
    return true;
  }

  /// [DVLazyListView.itemExtentBuilder] as Flutter asks it: by child
  /// index, separators included when [separated], and past the end (where
  /// Flutter wants null).
  ItemExtentBuilder? _extents({required bool separated}) {
    final double Function(int, SliverLayoutDimensions)? rows = widget.itemExtentBuilder;
    if (rows == null) return null;
    final int count = widget.itemCount;
    if (!separated) {
      return (int index, SliverLayoutDimensions dimensions) =>
          index < count ? rows(index, dimensions) : null;
    }
    return (int index, SliverLayoutDimensions dimensions) {
      if (index >= count * 2 - 1) return null;
      return index.isEven ? rows(index ~/ 2, dimensions) : widget.separatorExtent;
    };
  }

  @override
  Widget build(BuildContext context) {
    final IndexedWidgetBuilder? separator = widget.separatorBuilder;
    if (separator == null) {
      return ListView.builder(
        key: _listKey,
        cacheExtent: _cacheExtent,
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
        itemExtentBuilder: _extents(separated: false),
      );
    }
    return ListView.separated(
      key: _listKey,
      cacheExtent: _cacheExtent,
      itemCount: widget.itemCount,
      itemBuilder: widget.itemBuilder,
      itemExtentBuilder: _extents(separated: true),
      separatorBuilder: separator,
    );
  }
}
