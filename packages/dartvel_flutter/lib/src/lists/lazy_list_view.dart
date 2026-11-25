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

import 'package:dartvel_core/dartvel.dart' show DVDocumentRow, DVDocumentRowPart;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'backfill.dart';
import 'document_rows.dart';

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

class _DVLazyListViewState extends State<DVLazyListView> implements DVBackfillable, DVStandInList {
  final GlobalKey _listKey = GlobalKey();

  /// Its rows as the document has them, once given (document_rows.dart).
  List<DVDocumentRow>? _documentRows;

  /// What the rows it has not built say, read after the rows it has.
  List<DVDocumentRowPart> _standIns = const <DVDocumentRowPart>[];

  ScrollPosition? _watched;

  @override
  bool get settled => _documentRows != null;

  @override
  void standInRows(List<DVDocumentRow> rows) {
    if (!mounted) return;
    _documentRows = rows;
    DVDocumentRows.waiting.remove(this);
    _refreshStandIns();
  }

  /// The stand-ins again, for the rows not built now: after the rows are
  /// given, and whenever a scroll ends.
  void _refreshStandIns() {
    final List<DVDocumentRow>? rows = _documentRows;
    if (!mounted || rows == null) return;
    final ScrollPosition? position = _position();
    if (!identical(position, _watched)) {
      _watched?.isScrollingNotifier.removeListener(_scrolled);
      _watched = position?..isScrollingNotifier.addListener(_scrolled);
    }
    final BuildContext? list = _listKey.currentContext;
    final List<DVDocumentRowPart> parts = list is Element ? dvListStandIns(list, rows) : const <DVDocumentRowPart>[];
    if (listEquals(parts, _standIns)) return;
    setState(() => _standIns = parts);
  }

  void _scrolled() {
    if (_watched?.isScrollingNotifier.value ?? true) return;
    _refreshSoon();
  }

  bool _refreshing = false;

  /// After the frame that builds what was asked for.
  void _refreshSoon() {
    if (_refreshing || _documentRows == null) return;
    _refreshing = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _refreshing = false;
      _refreshStandIns();
    });
  }

  /// How far past the screen rows are built; null for Flutter's default.
  double? _cacheExtent;

  @override
  void initState() {
    super.initState();
    DVLazyBackfill.register(this);
    DVDocumentRows.waiting.add(this);
    DVDocumentRows.built.addListener(_refreshSoon);
  }

  @override
  void didUpdateWidget(DVLazyListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // More rows may be waiting than there were.
    if (widget.itemCount != oldWidget.itemCount) DVLazyBackfill.register(this);
  }

  @override
  void dispose() {
    _watched?.isScrollingNotifier.removeListener(_scrolled);
    DVLazyBackfill.unregister(this);
    DVDocumentRows.built.removeListener(_refreshSoon);
    DVDocumentRows.waiting.remove(this);
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

  @override
  Widget build(BuildContext context) {
    final bool standIns = _standIns.isNotEmpty;
    // The same shape with stand-ins or without, so the list is never moved
    // (a moved list builds its rows again): they are read after it.
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        Semantics(container: standIns, sortKey: standIns ? const OrdinalSortKey(0) : null, child: _list()),
        if (standIns) Positioned(left: 0, top: 0, right: 0, child: dvListStandInsBox(_standIns)),
      ],
    );
  }

  Widget _list() {
    final IndexedWidgetBuilder? separator = widget.separatorBuilder;
    if (separator == null) {
      return ListView.builder(
        key: _listKey,
        cacheExtent: _cacheExtent,
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
      );
    }
    return ListView.separated(
      key: _listKey,
      cacheExtent: _cacheExtent,
      itemCount: widget.itemCount,
      itemBuilder: widget.itemBuilder,
      separatorBuilder: separator,
    );
  }
}
