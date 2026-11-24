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
/// growths cost less than many small ones.
///
/// A row the cache grows into is not built and kept: it is a DVNearScreen,
/// held at the height of the rows built so far, read for its words while the
/// page is idle (near_screen.dart) and built when the page scrolls near it.
/// Building and keeping every row of sigmadev.digital's home, a section a
/// row, cost its first fifteen seconds a fifth of their frames. A row built
/// because the reader scrolled to it is built as it always was. From then on
/// Flutter reports every row's semantics, read or built, the ones off screen
/// marked hidden as it always does. The first frame builds exactly what it
/// did.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'backfill.dart';
import 'near_screen.dart';

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

  /// The rows the cache grew into, read rather than built; a row once read
  /// stays one, so it keeps its element when the list rebuilds.
  final Set<int> _readRows = <int>{};

  /// Whether a row built now is one the cache grew into: from a growth until
  /// the reader scrolls. A row the reader scrolls to is built at once.
  bool _growing = false;
  ScrollPosition? _watched;

  /// The rows built in full so far, and their height: the height a row read
  /// holds until it is built.
  double _builtHeight = 0;
  int _builtRows = 0;

  void _sized(double height) {
    _builtHeight += height;
    _builtRows++;
  }

  void _scrolled() => _growing = false;

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
    _watched?.removeListener(_scrolled);
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
    if (!identical(position, _watched)) {
      _watched?.removeListener(_scrolled);
      _watched = position..addListener(_scrolled);
    }
    _growing = true;
    setState(() => _cacheExtent = now + screen * screens);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final IndexedWidgetBuilder? separator = widget.separatorBuilder;
    Widget row(BuildContext context, int index) {
      final Widget child = widget.itemBuilder(context, index);
      if (_growing) _readRows.add(index);
      if (!_readRows.contains(index)) return _RowClock(onSpent: _spent, onSized: _sized, child: child);
      final double estimate = _builtRows == 0 ? 120 : _builtHeight / _builtRows;
      return _RowClock(onSpent: _spent, child: DVNearScreen(estimatedHeight: estimate, child: child));
    }

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
  const _RowClock({required this.onSpent, this.onSized, super.child});

  final ValueChanged<int> onSpent;

  /// Hears the row's height the first time it is laid out.
  final ValueChanged<double>? onSized;

  @override
  SingleChildRenderObjectElement createElement() => _RowClockElement(this);

  @override
  _RenderRowClock createRenderObject(BuildContext context) => _RenderRowClock(onSpent, onSized);

  @override
  void updateRenderObject(BuildContext context, _RenderRowClock renderObject) => renderObject
    ..onSpent = onSpent
    ..onSized = onSized;
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
  _RenderRowClock(this.onSpent, this.onSized);

  ValueChanged<int> onSpent;
  ValueChanged<double>? onSized;
  bool _sizedOnce = false;

  @override
  void performLayout() {
    final Stopwatch clock = Stopwatch()..start();
    super.performLayout();
    onSpent(clock.elapsedMicroseconds);
    if (!_sizedOnce && onSized != null) {
      _sizedOnce = true;
      onSized!(size.height);
    }
  }
}
