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

import 'package:dartvel_core/dartvel.dart' show DVDocumentRowPart;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'backfill.dart';
import 'document_rows.dart';
import 'lazy_lists.dart';

class DVNearScreen extends StatefulWidget {
  const DVNearScreen({
    super.key,
    required this.child,
    this.estimatedHeight = 120,
  });

  final Widget child;

  /// The height it holds before it is built, so the page's scroll length is
  /// roughly right. Rows are built two screens before they are seen, so the
  /// difference never shows.
  final double estimatedHeight;

  @override
  State<DVNearScreen> createState() => _DVNearScreenState();
}

/// A row [DVNearScreen] holds a place for and has not built yet.
///
/// Read by keyboard traversal (lazy_traversal.dart): a row that is not built
/// has no focus node, so Tab would jump over it to whatever is built after
/// it. Traversal builds the rows between the focus and the next control
/// first.
abstract class DVUnbuiltRow {
  /// The placeholder's element, for where it is on screen.
  BuildContext get context;

  /// Builds the row now, wherever the page is scrolled.
  void buildNow();
}

/// The rows waiting to be built, in no particular order.
Iterable<DVUnbuiltRow> get dvUnbuiltRows => _DVNearScreenState._waiting;

class _DVNearScreenState extends State<DVNearScreen> implements DVUnbuiltRow, DVBackfillable, DVStandInRow {
  static final Set<_DVNearScreenState> _waiting = <_DVNearScreenState>{};

  bool _built = DVLazyLists.buildWhole;

  /// What the document says it holds, while it is not built.
  List<DVDocumentRowPart>? _standIn;

  @override
  bool get built => _built;

  @override
  bool get settled => _built || _standIn != null || _elsewhere;

  @override
  void standIn(List<DVDocumentRowPart> parts) {
    if (settled || !mounted) return;
    DVDocumentRows.waiting.remove(this);
    setState(() => _standIn = parts);
  }

  /// Read after the rows of the scrollable list it is in: nothing in place.
  bool _elsewhere = false;

  @override
  void standElsewhere() {
    _elsewhere = true;
    DVDocumentRows.waiting.remove(this);
  }
  ScrollPosition? _position;

  @override
  void initState() {
    super.initState();
    if (!_built) {
      _waiting.add(this);
      DVDocumentRows.waiting.add(this);
      // And built when the page is idle, on the web, so a screen reader and
      // the browser's find reach it without scrolling: see backfill.dart.
      DVLazyBackfill.register(this);
    }
  }

  @override
  bool backfillStep() {
    buildNow();
    return false;
  }

  @override
  void buildNow() {
    if (_built || !mounted) return;
    _waiting.remove(this);
    DVLazyBackfill.unregister(this);
    _position?.removeListener(_check);
    _position = null;
    DVDocumentRows.waiting.remove(this);
    setState(() {
      _built = true;
      _standIn = null;
    });
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    if (_elsewhere) DVDocumentRows.built.notifyListeners();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built) return;
    final ScrollPosition? position = Scrollable.maybeOf(context)?.position;
    if (position == null) {
      _built = true;
      _waiting.remove(this);
      DVLazyBackfill.unregister(this);
      DVDocumentRows.waiting.remove(this);
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
    buildNow();
  }

  @override
  void dispose() {
    _waiting.remove(this);
    DVDocumentRows.waiting.remove(this);
    DVLazyBackfill.unregister(this);
    _position?.removeListener(_check);
    super.dispose();
  }

  @override
  // Its own layer, as each row of a Flutter ListView has: once built, the
  // row stays in the page, and without a boundary the scroll view repainted
  // every row built so far on every frame of a scroll.
  Widget build(BuildContext context) {
    if (_built) return RepaintBoundary(child: widget.child);
    final List<DVDocumentRowPart>? parts = _standIn;
    return parts == null ? SizedBox(height: widget.estimatedHeight) : dvStandIn(parts, widget.estimatedHeight);
  }
}
