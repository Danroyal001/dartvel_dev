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
/// On the web a row still waiting is read while the page is idle
/// (backfill.dart), so a screen reader and the browser's find reach it
/// without anyone scrolling. Reading it builds the row apart from the page --
/// its render objects attached to nothing, so nothing is laid out, painted or
/// shaped, and no frame is asked for -- takes its words, links and headings,
/// and lets the row go again: what stays is a stand-in of the same height
/// whose semantics say what the row says, links included, and whose words
/// the find runtime searches. Keeping every row built instead took
/// sigmadev.digital's phone heap from 15-21 MB to 50-58 MB and its frame
/// rate after the first frame from 39-48 to 4-7 (Dartvel 3.47.9 risk check).
/// A row that turns out to be cheap -- a paragraph, a line of text -- stays
/// built, up to [DVLazyBackfill.keepBudget] render objects across the app.
///
/// A stand-in becomes the real row the moment anything needs the row itself:
/// the page scrolls near it, Tab reaches it (lazy_traversal.dart), find
/// lands in it (find_in_page.dart), or a screen reader opens one of its links,
/// which then opens the real link.
///
/// Built at once when nothing scrolls around it, and while the build captures
/// the page ([DVLazyLists.buildWhole]).
library;

import 'package:dartvel_core/dartvel.dart' show DVFindBlock;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'backfill.dart';
import 'lazy_lists.dart';

class DVNearScreen extends StatefulWidget {
  const DVNearScreen({super.key, required this.child, this.estimatedHeight = 120, this.screensAhead = 3});

  final Widget child;

  /// How many screens below the top of the screen it is built: three in a
  /// page, so a long collection's rows are there before they are seen. A row
  /// of a lazy list takes a third of a screen past the bottom, about as close
  /// as the list itself builds, so the rows its cache grew into are read and
  /// not built: building the row past the bottom of sigmadev.digital's home
  /// took a frame of 600 ms on a phone.
  final double screensAhead;

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

/// A row that is not built but has been read: its words stand in for it.
///
/// Read by the find runtime (find_in_page.dart), which searches [findBlocks]
/// as it searches a paragraph the page drew, and calls [buildNow] when the
/// browser's find lands in one.
abstract class DVReadRow implements DVUnbuiltRow {
  /// The row's paragraphs, in order, as the find runtime reads a page; null
  /// while the row has not been read.
  List<DVFindBlock>? get findBlocks;
}

/// The rows waiting to be built, in no particular order.
Iterable<DVUnbuiltRow> get dvUnbuiltRows => _DVNearScreenState._waiting;

/// Where a row is.
enum _Phase {
  /// A place held at the estimated height.
  waiting,

  /// Read, still a place held: what it read lands in the page with the
  /// other rows read, in one frame.
  landing,

  /// Read: its words stand in for it.
  read,

  /// Built, as a row scrolled to is.
  built,
}

/// One thing a screen reader hears in a row: a paragraph, a heading, a link
/// or a button.
@immutable
class _Spoken {
  const _Spoken(this.label, {this.headingLevel = 0, this.link = false, this.button = false, this.linkUrl});

  final String label;
  final int headingLevel;
  final bool link;
  final bool button;
  final Uri? linkUrl;

  bool get control => link || button;
}

/// Render objects kept built by rows read while idle, across the app.
int _kept = 0;

class _DVNearScreenState extends State<DVNearScreen> implements DVReadRow, DVBackfillable {
  static final Set<_DVNearScreenState> _waiting = <_DVNearScreenState>{};

  _Phase _phase = DVLazyLists.buildWhole ? _Phase.built : _Phase.waiting;
  ScrollPosition? _position;

  List<_Spoken> _spoken = const <_Spoken>[];
  List<DVFindBlock>? _blocks;

  /// Render objects this row holds against [_kept].
  int _keeping = 0;

  @override
  List<DVFindBlock>? get findBlocks => _phase == _Phase.read ? _blocks : null;

  @override
  void initState() {
    super.initState();
    if (_phase != _Phase.built) {
      _waiting.add(this);
      // And read when the page is idle, on the web, so a screen reader and
      // the browser's find reach it without scrolling: see backfill.dart.
      DVLazyBackfill.register(this);
    }
  }

  @override
  bool get backfillFrameless => true;

  /// Reads the row apart from the page, now: no frame. What it read lands
  /// in the page with the other rows read ([DVLazyBackfill.land]): a cheap
  /// row is built for good, any other leaves a stand-in.
  @override
  bool backfillStep() {
    if (!mounted || _phase != _Phase.waiting) return false;
    _DVReadingAnchorElement? anchor;
    (context as Element).visitChildElements((Element child) {
      if (child is _DVReadingAnchorElement) anchor = child;
    });
    // Not built yet: another step looks again.
    if (anchor == null) return true;
    final _Reading reading = anchor!.read(widget.child);
    _phase = _Phase.landing;
    final bool cheap = reading.renderObjects <= DVLazyBackfill.keepRowAtMost &&
        reading.renderObjects <= DVLazyBackfill.keepBudget - _kept;
    if (reading.needsLayout || cheap) {
      // Cheap, or its words are only there once it is laid out (a
      // LayoutBuilder builds its child during layout): built for good.
      if (!reading.needsLayout) {
        _keeping = reading.renderObjects;
        _kept += _keeping;
      }
      DVLazyBackfill.land(buildNow);
      return false;
    }
    _spoken = reading.spoken;
    _blocks = reading.blocks;
    DVLazyBackfill.land(_land);
    return false;
  }

  void _land() {
    if (!mounted || _phase != _Phase.landing) return;
    setState(() => _phase = _Phase.read);
  }

  @override
  void buildNow() {
    if (_phase == _Phase.built || !mounted) return;
    _waiting.remove(this);
    DVLazyBackfill.unregister(this);
    _position?.removeListener(_check);
    _position = null;
    setState(() {
      _phase = _Phase.built;
      _spoken = const <_Spoken>[];
      _blocks = null;
    });
  }

  /// A screen reader opened [spoken], a link or button of the stand-in: the
  /// row is built and the same control in it is opened.
  ///
  /// The row is brought on screen first, as a screen reader's focus going
  /// there would bring it: a control far off screen is not in the semantics
  /// tree to be opened.
  Future<void> _open(_Spoken spoken) async {
    buildNow();
    await SchedulerBinding.instance.endOfFrame;
    for (int settle = 0; settle < 3 && mounted; settle++) {
      await Scrollable.ensureVisible(context, alignment: 0.25);
      await SchedulerBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    _activate(context, spoken.label);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_phase == _Phase.built) return;
    final ScrollPosition? position = Scrollable.maybeOf(context)?.position;
    if (position == null) {
      _phase = _Phase.built;
      _waiting.remove(this);
      DVLazyBackfill.unregister(this);
      return;
    }
    if (!identical(position, _position)) {
      _position?.removeListener(_check);
      _position = position..addListener(_check);
    }
    SchedulerBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_phase == _Phase.built || !mounted) return;
    final RenderObject? box = context.findRenderObject();
    final ScrollPosition? position = _position;
    if (box is! RenderBox || !box.attached || !box.hasSize || position == null || !position.hasViewportDimension) return;
    final RenderAbstractViewport? viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final double top = viewport.getOffsetToReveal(box, 0).offset;
    final double screen = position.viewportDimension;
    final bool near = top < position.pixels + screen * widget.screensAhead &&
        top + box.size.height > position.pixels - screen * (widget.screensAhead - 1);
    if (!near) return;
    buildNow();
  }

  @override
  void dispose() {
    _waiting.remove(this);
    DVLazyBackfill.unregister(this);
    _position?.removeListener(_check);
    _kept -= _keeping;
    _keeping = 0;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DVReadingAnchor(child: _row(context));

  Widget _row(BuildContext context) {
    switch (_phase) {
      case _Phase.waiting:
      case _Phase.landing:
        return _DVRowHost(mode: _HostMode.placeholder, estimatedHeight: widget.estimatedHeight);
      case _Phase.read:
        return _DVRowHost(
          mode: _HostMode.standIn,
          estimatedHeight: widget.estimatedHeight,
          child: _spoken.isEmpty ? null : _StandIn(spoken: _spoken, open: _open),
        );
      case _Phase.built:
        // Its own layer, as each row of a Flutter ListView has: once built,
        // the row stays in the page, and without a boundary the scroll view
        // repainted every row built so far on every frame of a scroll.
        return RepaintBoundary(
          child: _DVRowHost(
            mode: _HostMode.built,
            estimatedHeight: widget.estimatedHeight,
            child: SelectionRegistrarScope(
              registrar: SelectionContainer.maybeOf(context) ?? const _NoSelection(),
              child: widget.child,
            ),
          ),
        );
    }
  }
}

/// Where a row is read from: its elements under the row's own, so it sees
/// the theme, the media query and everything else the row would, and its
/// render objects under a root attached to nothing.
class _DVReadingAnchor extends ProxyWidget {
  const _DVReadingAnchor({required super.child});

  @override
  Element createElement() => _DVReadingAnchorElement(this);
}

class _DVReadingAnchorElement extends ProxyElement {
  _DVReadingAnchorElement(_DVReadingAnchor super.widget);

  @override
  void notifyClients(ProxyWidget oldWidget) {}

  /// Builds [row] apart from the page, reads it and lets it go, all before
  /// returning. Its paragraphs register for no selection and its controls
  /// for no focus, as neither will ever have a size.
  _Reading read(Widget row) {
    late Element root;
    // A collection inside the row is read whole, not as the places its own
    // rows would hold.
    final bool whole = DVLazyLists.buildWhole;
    DVLazyLists.buildWhole = true;
    try {
      owner!.buildScope(this, () {
        root = inflateWidget(
          _DVDetached(
            child: SelectionRegistrarScope(registrar: const _NoSelection(), child: ExcludeFocus(child: row)),
          ),
          _detachedSlot,
        );
      });
    } finally {
      DVLazyLists.buildWhole = whole;
    }
    final _Reading reading;
    try {
      reading = _Reading.of(root);
    } finally {
      owner!.lockState(() => deactivateChild(root));
    }
    // What was read is unmounted now, not at the end of a frame that is not
    // coming.
    owner!.finalizeTree();
    return reading;
  }
}

/// The slot a row being read occupies: never one the anchor's own child has.
const Object _detachedSlot = Object();

/// The root of a row being read: its render object is attached to nothing,
/// so nothing under it is laid out, painted or asks for a frame.
class _DVDetached extends SingleChildRenderObjectWidget {
  const _DVDetached({super.child});

  @override
  SingleChildRenderObjectElement createElement() => _DVDetachedElement(this);

  @override
  RenderProxyBox createRenderObject(BuildContext context) => RenderProxyBox();
}

class _DVDetachedElement extends SingleChildRenderObjectElement {
  _DVDetachedElement(_DVDetached super.widget);

  @override
  void attachRenderObject(Object? newSlot) {}

  @override
  void detachRenderObject() {}
}

/// What a row built for reading says, read from its elements: it has not
/// been laid out, so nothing here asks for a size.
class _Reading {
  _Reading._();

  final List<_Spoken> spoken = <_Spoken>[];
  final List<DVFindBlock> blocks = <DVFindBlock>[];
  int renderObjects = 0;
  bool needsLayout = false;

  static _Reading of(BuildContext row) {
    final _Reading reading = _Reading._();
    if (row is Element) row.visitChildElements((Element child) => reading._visit(child, 0, null, false));
    return reading;
  }

  /// A paragraph: one node with the plain paragraphs read just before it,
  /// so a card is a link and a line of text rather than a node per line.
  void _say(String text, int heading) {
    final _Spoken? last = spoken.isEmpty ? null : spoken.last;
    if (heading == 0 && last != null && !last.control && last.headingLevel == 0) {
      spoken[spoken.length - 1] = _Spoken('${last.label}\n$text');
      return;
    }
    spoken.add(_Spoken(text, headingLevel: heading));
  }

  /// [heading] is the level of the heading it is in, [control] the labelled
  /// link or button whose label stands for everything in it, [silent] true
  /// inside what semantics exclude.
  void _visit(Element element, int heading, _Spoken? control, bool silent) {
    final Widget widget = element.widget;
    if (widget is Offstage && widget.offstage) return;
    if (widget is ConstrainedLayoutBuilder) needsLayout = true;
    if (widget is ExcludeSemantics && widget.excluding) silent = true;
    if (widget is Semantics) {
      final SemanticsProperties properties = widget.properties;
      final int? declared = properties.headingLevel;
      if (declared != null && declared > 0) heading = declared;
      final String? label = properties.label;
      final bool link = properties.link ?? false;
      final bool button = properties.button ?? false;
      if (!silent && label != null && label.trim().isNotEmpty && (link || button)) {
        final _Spoken spoken = _Spoken(label.trim(), link: link, button: button, linkUrl: properties.linkUrl, headingLevel: heading);
        this.spoken.add(spoken);
        control = spoken;
        if (widget.excludeSemantics) silent = true;
      }
    }
    if (element is RenderObjectElement) {
      renderObjects++;
      final RenderObject render = element.renderObject;
      if (render is RenderParagraph) {
        final String text = render.text.toPlainText(includeSemanticsLabels: false, includePlaceholders: false).trim();
        if (text.isNotEmpty) {
          blocks.add(DVFindBlock(text, headingLevel: heading == 0 ? null : heading));
          if (!silent && text != control?.label) _say(text, heading);
        }
      }
    }
    element.visitChildElements((Element child) => _visit(child, heading, control, silent));
  }
}

/// Opens the control labelled [label] in the row at [row], just built: the
/// tap of a labelled Semantics in it, else whatever has that label and a
/// tap in the semantics tree, nearest the row.
void _activate(BuildContext row, String label) {
  VoidCallback? tap;
  void visit(Element element) {
    if (tap != null) return;
    final Widget widget = element.widget;
    if (widget is Semantics && widget.properties.label?.trim() == label && widget.properties.onTap != null) {
      tap = widget.properties.onTap;
      return;
    }
    element.visitChildElements(visit);
  }

  if (row is Element) row.visitChildElements(visit);
  if (tap != null) {
    tap!();
    return;
  }
  final RenderObject? box = row.findRenderObject();
  final SemanticsOwner? owner = box?.owner?.semanticsOwner;
  final SemanticsNode? root = owner?.rootSemanticsNode;
  if (owner == null || root == null || box is! RenderBox || !box.hasSize) return;
  // Semantics rects are in the root's physical pixels.
  final double ratio = View.maybeOf(row)?.devicePixelRatio ?? 1;
  final Offset centre = box.localToGlobal(box.size.center(Offset.zero)) * ratio;
  SemanticsNode? best;
  double bestDistance = double.infinity;
  void search(SemanticsNode node, Matrix4 transform) {
    final Matrix4 here = node.transform == null ? transform : (transform.clone()..multiply(node.transform!));
    final SemanticsData data = node.getSemanticsData();
    // Its own words may be merged into the node with the rest of the row's.
    if (data.label.contains(label) && data.hasAction(SemanticsAction.tap)) {
      final double distance = (MatrixUtils.transformRect(here, node.rect).center - centre).distance;
      if (distance < bestDistance) {
        best = node;
        bestDistance = distance;
      }
    }
    node.visitChildren((SemanticsNode child) {
      search(child, here);
      return true;
    });
  }

  search(root, Matrix4.identity());
  if (best != null) owner.performAction(best!.id, SemanticsAction.tap);
}

/// Where a row's paragraphs register for selection while it is read, and
/// where they register when the page has no selection: nowhere.
class _NoSelection implements SelectionRegistrar {
  const _NoSelection();

  @override
  void add(Selectable selectable) {}

  @override
  void remove(Selectable selectable) {}
}

/// What a read row says, as semantics only: one node for each paragraph,
/// heading, link and button, stacked in the row's height so each has a place
/// on screen, as a node must to be read. Nothing is drawn, and nothing is
/// under each node: a box with no child fills the tight height its Expanded
/// gives it.
class _StandIn extends StatelessWidget {
  const _StandIn({required this.spoken, required this.open});

  final List<_Spoken> spoken;
  final void Function(_Spoken) open;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final _Spoken item in spoken)
            Expanded(
              child: Semantics(
                container: true,
                label: item.label,
                link: item.link,
                linkUrl: item.linkUrl,
                button: item.button,
                headingLevel: item.headingLevel == 0 ? null : item.headingLevel,
                onTap: item.control ? () => open(item) : null,
              ),
            ),
        ],
      );
}

enum _HostMode { placeholder, standIn, built }

/// The box a row lives in: its estimated height until it is built, with the
/// stand-in laid out at that height once it has been read.
class _DVRowHost extends SingleChildRenderObjectWidget {
  const _DVRowHost({required this.mode, required this.estimatedHeight, super.child});

  final _HostMode mode;
  final double estimatedHeight;

  @override
  _RenderRowHost createRenderObject(BuildContext context) => _RenderRowHost(mode, estimatedHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderRowHost renderObject) {
    renderObject
      ..mode = mode
      ..estimatedHeight = estimatedHeight;
  }
}

class _RenderRowHost extends RenderProxyBox {
  _RenderRowHost(this._mode, this._estimatedHeight);

  _HostMode _mode;
  set mode(_HostMode value) {
    if (value == _mode) return;
    _mode = value;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  double _estimatedHeight;
  set estimatedHeight(double value) {
    if (value == _estimatedHeight) return;
    _estimatedHeight = value;
    markNeedsLayout();
  }

  bool get _real => _mode == _HostMode.built;

  bool get _childIsLaidOut => child != null && (_mode == _HostMode.built || _mode == _HostMode.standIn);

  @override
  void performLayout() {
    if (_real && child != null) {
      child!.layout(constraints, parentUsesSize: true);
      size = child!.size;
      return;
    }
    // At least a pixel wide, so a stand-in's nodes have a place to be read
    // in a column that does not stretch its rows.
    size = constraints.constrain(Size(1, _estimatedHeight));
    if (_childIsLaidOut) child!.layout(BoxConstraints.tight(size));
  }

  @override
  double computeMinIntrinsicHeight(double width) => _real ? super.computeMinIntrinsicHeight(width) : _estimatedHeight;

  @override
  double computeMaxIntrinsicHeight(double width) => _real ? super.computeMaxIntrinsicHeight(width) : _estimatedHeight;

  @override
  double computeMinIntrinsicWidth(double height) => _real ? super.computeMinIntrinsicWidth(height) : 0;

  @override
  double computeMaxIntrinsicWidth(double height) => _real ? super.computeMaxIntrinsicWidth(height) : 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _real ? super.computeDryLayout(constraints) : constraints.constrain(Size(1, _estimatedHeight));

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_real) super.paint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _real && super.hitTestChildren(result, position: position);

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_childIsLaidOut) super.visitChildrenForSemantics(visitor);
  }
}
