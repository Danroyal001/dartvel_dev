/// The list a scrollable DVBox list is: rows built near the screen, and on
/// the web the rest built while the page is idle.
///
/// A ListView builds the rows within its cache extent of the screen, a
/// quarter of a screen or so, and nothing past it: no element, no semantics
/// node, no text. On the web that left the end of a page -- a layout's
/// footer, the bottom of a long page -- out of reach of a screen reader's
/// line-by-line reading and of the browser's find after a navigation inside
/// the app (Tori and Learnacer, Dartvel 3.47.7). So when the page is idle the
/// cache extent grows, a frame at a time, until it covers the whole list
/// (backfill.dart): first by four screens, then by as many as the last
/// growth's build and layout say fit in [DVLazyBackfill.growBudgetMs]. Every
/// frame rasters the whole screen however little changed, so fewer, fuller
/// growths cost less than many small ones. From then on every row is built and stays built,
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
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Between two rows, when the list is spaced.
  final IndexedWidgetBuilder? separatorBuilder;

  @override
  State<DVLazyListView> createState() => _DVLazyListViewState();
}

class _DVLazyListViewState extends State<DVLazyListView> implements DVBackfillable {
  final GlobalKey _listKey = GlobalKey();

  /// How far past the screen rows are built; null for Flutter's default.
  double? _cacheExtent;

  /// How many screens the last growth added, and how long building and
  /// laying out the rows it reached took, in microseconds: what the next
  /// growth is sized from.
  double _grownScreens = 0;
  int _spentMicroseconds = 0;

  void _spent(int microseconds) => _spentMicroseconds += microseconds;

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
  bool get backfillFrameless => false;

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
    // Building the rows a growth reaches is most of its layout: as many
    // screens as fit in the budget at the rate the last growth went.
    double screens = 4;
    if (_grownScreens > 0) {
      final double perScreenMs = _spentMicroseconds / 1000 / _grownScreens;
      screens = perScreenMs <= 0 ? 64 : (DVLazyBackfill.growBudgetMs / perScreenMs).clamp(1, 64).toDouble();
    }
    _grownScreens = screens;
    _spentMicroseconds = 0;
    setState(() => _cacheExtent = now + screen * screens);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final IndexedWidgetBuilder? separator = widget.separatorBuilder;
    Widget row(BuildContext context, int index) => _RowClock(onSpent: _spent, child: widget.itemBuilder(context, index));
    if (separator == null) {
      return ListView.builder(
        key: _listKey,
        cacheExtent: _cacheExtent,
        itemCount: widget.itemCount,
        itemBuilder: row,
      );
    }
    return ListView.separated(
      key: _listKey,
      cacheExtent: _cacheExtent,
      itemCount: widget.itemCount,
      itemBuilder: row,
      separatorBuilder: separator,
    );
  }
}

/// Times what a row costs the frame it arrives in: building it, which
/// builds everything in it at once, and laying it out.
class _RowClock extends SingleChildRenderObjectWidget {
  const _RowClock({required this.onSpent, super.child});

  final ValueChanged<int> onSpent;

  @override
  SingleChildRenderObjectElement createElement() => _RowClockElement(this);

  @override
  _RenderRowClock createRenderObject(BuildContext context) => _RenderRowClock(onSpent);

  @override
  void updateRenderObject(BuildContext context, _RenderRowClock renderObject) => renderObject.onSpent = onSpent;
}

class _RowClockElement extends SingleChildRenderObjectElement {
  _RowClockElement(_RowClock super.widget);

  @override
  void mount(Element? parent, Object? newSlot) {
    final Stopwatch clock = Stopwatch()..start();
    super.mount(parent, newSlot);
    (widget as _RowClock).onSpent(clock.elapsedMicroseconds);
  }
}

class _RenderRowClock extends RenderProxyBox {
  _RenderRowClock(this.onSpent);

  ValueChanged<int> onSpent;

  @override
  void performLayout() {
    final Stopwatch clock = Stopwatch()..start();
    super.performLayout();
    onSpent(clock.elapsedMicroseconds);
  }
}
