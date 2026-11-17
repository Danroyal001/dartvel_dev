/// Every Dartvel page scrolls, with nothing in the application asking for it
/// (owner, 17 Nov 2026: "DVPages should already be scrollable").
///
/// The page shell puts one [DVPageViewport] round each page. It is the page's
/// scroll view when the page is taller than the screen and has none of its
/// own, and it steps aside -- lays the page out at the screen's height and
/// scrolls nothing -- when the page fills the screen itself:
///
/// * it has its own scroll view (a SingleChildScrollView, a ListView, a
///   CustomScrollView, a scrollable DVBox list, a PageView), or
/// * it is laid out to the screen's height: an Expanded, Flexible or Spacer
///   in a column, a Scaffold, a stretched row, `SizedBox.expand`, a Stack
///   that expands, a platform view such as a map.
///
/// The rule is read from the page's own layout every time it is laid out, so
/// a page that shows a spinner and then a ListView changes over by itself.
/// `@DVPage(scroll: false)` turns it off for a page.
///
/// Mouse wheel, trackpad, touch with the platform's physics, the keyboard
/// (DVKeyboardScroll finds it as the page's first scrollable), the scrollbar,
/// focus traversal (it is a real viewport, so a focused control is scrolled
/// into view) and the browser's find all use this one scroll view. A
/// screen reader sees one scroll container: this one when the shell scrolls,
/// the page's own when it does not.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'page_history_stub.dart'
    if (dart.library.js_interop) 'page_history_web.dart' as history;
import 'page_scroll.dart' show DVPageJumpButton;

/// Where each page was scrolled to, so back and forward return the reader
/// there, and the test seams for the browser's part.
abstract final class DVPageScrollMemory {
  static final Map<String, double> _offsets = <String, double>{};

  /// How many pages are remembered. A session that has seen more starts the
  /// oldest at the top, as a browser does with a page it has evicted.
  static const int capacity = 64;

  /// The address a back or forward just went to, once. Tests replace it.
  static String? Function() takeHistoryNavigation =
      history.dvTakeHistoryNavigation;

  /// The browser's key for the history entry on screen. Tests replace it.
  static Object? Function() historyEntryKey = history.dvHistoryEntryKey;

  /// How far the server-rendered document was scrolled when the app took
  /// over, once. Tests replace it.
  static double Function() takeTakeoverScroll = history.dvTakeTakeoverScroll;

  static double? recall(String key) => _offsets[key];

  static void remember(String key, double offset) {
    _offsets.remove(key);
    _offsets[key] = offset;
    while (_offsets.length > capacity) {
      _offsets.remove(_offsets.keys.first);
    }
  }

  /// Forgets everything and puts the browser hooks back, for tests.
  static void reset() {
    _offsets.clear();
    takeHistoryNavigation = history.dvTakeHistoryNavigation;
    historyEntryKey = history.dvHistoryEntryKey;
    takeTakeoverScroll = history.dvTakeTakeoverScroll;
    dvPrimaryPointerIsTouch = history.dvPrimaryPointerIsTouch;
  }
}

/// Lets a [DVPageScrollFrame] inside a page hand its back-to-top button to
/// the shell, which draws it outside the scroll view.
class DVPageViewportScope extends InheritedWidget {
  const DVPageViewportScope({super.key, required this.host, required super.child});

  final DVPageViewportState host;

  static DVPageViewportState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DVPageViewportScope>()?.host;

  @override
  bool updateShouldNotify(DVPageViewportScope oldWidget) => !identical(host, oldWidget.host);
}

/// The page shell's scroll view. See the library comment.
class DVPageViewport extends StatefulWidget {
  const DVPageViewport({
    super.key,
    required this.child,
    this.address,
    this.onTop = true,
  });

  final Widget child;

  /// The page's own address, for remembering where it was scrolled to.
  /// Null for a body inside a layout (DartvelLayout's header and footer),
  /// whose page shell remembers for it.
  final Uri Function()? address;

  /// Whether the page is the one on top of its navigator.
  final bool onTop;

  @override
  State<DVPageViewport> createState() => DVPageViewportState();
}

class DVPageViewportState extends State<DVPageViewport> {
  final ScrollController _controller = ScrollController(debugLabel: 'DVPageViewport');
  final GlobalKey<ScrollableState> _scrollableKey = GlobalKey<ScrollableState>();

  /// Keeps the page's state when the scroll view round it changes shape: the
  /// semantics and the scrollbar come and go as layout decides whether the
  /// shell scrolls, and the page is moved, not built again (a page that
  /// loads its data in initState would load it twice).
  final GlobalKey _bodyKey = GlobalKey(debugLabel: 'DVPageViewport body');

  /// Ticks on every scroll and every change of scroll extent on the page, for
  /// the back-to-top button.
  final ValueNotifier<int> _ticks = ValueNotifier<int>(0);

  /// Whether the shell is scrolling the page right now (rather than the page
  /// scrolling itself). Read from layout; the semantics follow it.
  bool _scrolls = false;

  /// The controllers of the back-to-top frames inside the page.
  final Set<ScrollController> _jumpFrames = <ScrollController>{};

  /// The key this page's position is remembered under, fixed when it is
  /// first shown: by the time it is left the browser is on another entry.
  String? _memoryKey;
  bool _shown = false;

  /// Inside another page viewport: a layout's scrolling body. The outer one
  /// remembers and restores; this one only scrolls.
  bool _nested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _nested = DVPageViewportScope.maybeOf(context) != null;
  }

  /// The shell's own scroll position, when it has one.
  ScrollPosition? get ownPosition =>
      _controller.positions.length == 1 ? _controller.position : null;

  /// The page's main scroll position: the shell's while it scrolls the page,
  /// otherwise the first vertical scroll view inside the page that has
  /// somewhere to go.
  ScrollPosition? get primaryPosition {
    final ScrollPosition? own = ownPosition;
    if (own != null && own.hasContentDimensions && own.maxScrollExtent > own.minScrollExtent) {
      return own;
    }
    ScrollPosition? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement &&
          element.state is ScrollableState &&
          !identical(element.state, _scrollableKey.currentState)) {
        final ScrollableState scrollable = element.state as ScrollableState;
        final ScrollPosition position = scrollable.position;
        if (axisDirectionToAxis(scrollable.axisDirection) == Axis.vertical &&
            position.hasContentDimensions &&
            position.maxScrollExtent > position.minScrollExtent) {
          found = position;
          return;
        }
      }
      element.visitChildren(visit);
    }

    final BuildContext? scrollable = _scrollableKey.currentContext;
    if (scrollable == null) return null;
    scrollable.visitChildElements(visit);
    return found;
  }

  /// A back-to-top frame inside the page asks for its button.
  void addJumpFrame(ScrollController frame) {
    if (_jumpFrames.add(frame)) _afterFrame(() => setState(() {}));
  }

  void removeJumpFrame(ScrollController frame) {
    if (_jumpFrames.remove(frame)) _afterFrame(() => setState(() {}));
  }

  void _afterFrame(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  /// The position the back-to-top button moves: the shell's while it
  /// scrolls the page, otherwise the frame's own.
  ScrollPosition? get _jumpPosition {
    final ScrollPosition? own = ownPosition;
    if (own != null && own.hasContentDimensions && own.maxScrollExtent > 0) return own;
    for (final ScrollController frame in _jumpFrames) {
      if (frame.positions.length == 1) return frame.position;
    }
    // A layout's scrolling body, or a page scrolling itself without the frame's
    // controller: as last found after a frame, since the tree cannot be
    // walked while this builds.
    return _tracked;
  }

  @override
  void initState() {
    super.initState();
    history.dvPageHistoryInstall();
    if (widget.onTop) _afterFrame(_firstShown);
  }

  @override
  void didUpdateWidget(DVPageViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onTop && !_shown) _afterFrame(_firstShown);
  }

  /// Fixes the key the page is remembered under, and puts the reader back
  /// where they were after a back or forward, or where the server-rendered
  /// document was when the app took over.
  void _firstShown() {
    if (_shown || !widget.onTop) return;
    _shown = true;
    final Uri Function()? addressOf = widget.address;
    if (_nested || addressOf == null) return;
    final Uri address = addressOf();
    _memoryKey = '${DVPageScrollMemory.historyEntryKey() ?? ''}|$address';
    _tracked = primaryPosition;
    double target = DVPageScrollMemory.takeTakeoverScroll();
    if (target <= 0) {
      final String? popped = DVPageScrollMemory.takeHistoryNavigation();
      if (popped != null && _samePage(Uri.tryParse(popped), address)) {
        target = DVPageScrollMemory.recall(_memoryKey!) ?? 0;
      }
    }
    if (target > 0) _restore(target, 60);
  }

  static bool _samePage(Uri? popped, Uri address) {
    if (popped == null) return false;
    // Under the hash strategy the route is the fragment.
    final String poppedRoute = popped.fragment.startsWith('/') ? popped.fragment : popped.path;
    final String route = address.path.isEmpty ? '/' : address.path;
    final Uri poppedUri = Uri.parse(poppedRoute.isEmpty ? '/' : poppedRoute);
    return poppedUri.path == route;
  }

  /// Scrolls the page to [target] once it is long enough to get there, for
  /// up to [frames] frames while what it loads arrives.
  void _restore(double target, int frames) {
    if (!mounted) return;
    final ScrollPosition? position = primaryPosition;
    if (position != null && position.maxScrollExtent >= target) {
      position.jumpTo(target);
      return;
    }
    if (frames <= 0) {
      if (position != null) position.jumpTo(math.min(target, position.maxScrollExtent));
      return;
    }
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _restore(target, frames - 1))
      ..scheduleFrame();
  }

  /// The page's main scroll position as last found, read again when the page
  /// is left: the element tree cannot be walked while it is being torn down.
  ScrollPosition? _tracked;

  void _remember({bool leaving = false}) {
    if (_nested) return;
    final String? key = _memoryKey;
    if (key == null) return;
    final ScrollPosition? position = leaving ? _tracked : (_tracked = primaryPosition);
    if (position == null || !position.hasPixels) return;
    DVPageScrollMemory.remember(key, position.pixels);
  }

  @override
  void deactivate() {
    // Before the page's scroll views are disposed beneath it.
    _remember(leaving: true);
    super.deactivate();
  }

  @override
  void dispose() {
    _controller.dispose();
    _ticks.dispose();
    super.dispose();
  }

  /// A scroll notification from inside the page. It is sent on from above
  /// the shell's scrollbar and overscroll indicator, so they answer only the
  /// shell's own scrolling and a page with its own scroll view never shows
  /// two scrollbars; everything above the shell still hears it.
  bool _fromInside(Notification notification) {
    if (notification is ScrollNotification || notification is ScrollMetricsNotification) {
      _scheduleTrack();
      if (notification is ScrollEndNotification) _remember();
      _ticks.value++;
      notification.dispatch(context);
      return true;
    }
    return false;
  }

  bool _fromShell(Notification notification) {
    if (notification is ScrollNotification || notification is ScrollMetricsNotification) {
      _scheduleTrack();
      if (notification is ScrollEndNotification) _remember();
      _ticks.value++;
    }
    return false;
  }

  bool _trackPending = false;

  /// Finds the page's main scroll position again once the frame is drawn, for
  /// the back-to-top button and for remembering where the page was.
  void _scheduleTrack() {
    if (_trackPending) return;
    _trackPending = true;
    _afterFrame(() {
      _trackPending = false;
      final ScrollPosition? found = primaryPosition;
      if (!identical(found, _tracked)) {
        _tracked = found;
        _ticks.value++;
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Layout decided whether the shell scrolls; the semantics follow a frame
  /// later. A page that scrolls itself keeps the semantics tree it had: the
  /// shell adds no node.
  void _layoutDecided(bool scrolls) {
    _decided = scrolls;
    if (_decisionPending || scrolls == _scrolls) return;
    _decisionPending = true;
    _afterFrame(() {
      _decisionPending = false;
      if (_decided != _scrolls) setState(() => _scrolls = _decided);
    });
  }

  /// What the last layout decided, and whether a frame is due to apply it.
  bool _decided = false;
  bool _decisionPending = false;

  @override
  Widget build(BuildContext context) {
    // The page's text registers with the page's selection area directly, as
    // it did before the shell scrolled: a Scrollable between them makes a
    // selection container of its own, and the menu then offered no Select
    // all while nothing was selected. Hidden from the Scrollable, handed back
    // inside it.
    final SelectionRegistrar? registrar = SelectionContainer.maybeOf(context);
    Widget body = KeyedSubtree(
      key: _bodyKey,
      child: DVPageViewportScope(host: this, child: widget.child),
    );
    if (registrar != null) body = SelectionRegistrarScope(registrar: registrar, child: body);
    final Widget scrollable = NotificationListener<Notification>(
      onNotification: _fromShell,
      child: Scrollable(
        key: _scrollableKey,
        controller: _controller,
        axisDirection: AxisDirection.down,
        // No scrollbar where scrolling is a finger's: a permanent groove only
        // takes width from the page. Desktop keeps it.
        // And none at all while the page scrolls itself: its own scroll view
        // has the scrollbar.
        scrollBehavior: !_scrolls
            ? ScrollConfiguration.of(context).copyWith(scrollbars: false, overscroll: false)
            : dvPageScrollsByTouch(context)
                ? ScrollConfiguration.of(context).copyWith(scrollbars: false)
                : null,
        excludeFromSemantics: !_scrolls,
        viewportBuilder: (BuildContext context, ViewportOffset offset) =>
            NotificationListener<Notification>(
              onNotification: _fromInside,
              child: _DVPageViewportBox(
                offset: offset,
                onDecided: _layoutDecided,
                child: body,
              ),
            ),
      ),
    );
    final Widget shell = registrar == null ? scrollable : SelectionContainer.disabled(child: scrollable);
    if (_jumpFrames.isEmpty) return shell;
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        shell,
        Positioned(
          right: 20,
          bottom: 20,
          child: ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[_ticks, _controller, ..._jumpFrames]),
            builder: (BuildContext context, Widget? _) {
              final ScrollPosition? position = _jumpPosition;
              if (position == null) return const SizedBox.shrink();
              return DVPageJumpButton.forPosition(position);
            },
          ),
        ),
      ],
    );
  }
}

class _DVPageViewportBox extends SingleChildRenderObjectWidget {
  const _DVPageViewportBox({required this.offset, required this.onDecided, super.child});

  final ViewportOffset offset;
  final ValueChanged<bool> onDecided;

  @override
  RenderDVPageViewport createRenderObject(BuildContext context) =>
      RenderDVPageViewport(offset: offset, onDecided: onDecided);

  @override
  void updateRenderObject(BuildContext context, RenderDVPageViewport renderObject) {
    renderObject
      ..offset = offset
      ..onDecided = onDecided;
  }
}

/// How a page's layout relates to the screen's height.
enum DVPageFit {
  /// It takes the height its content needs: the shell scrolls it.
  grows,

  /// It fills the screen by itself, or scrolls itself.
  fills,

  /// Not built yet (a LayoutBuilder that builds during layout).
  unknown,
}

/// Whether the page under [node] fills the screen by itself. [screen] is the
/// space the page is given.
///
/// Walks down until it meets something that settles it. A column's children
/// that are not flexible already take the height they need, so a column is
/// as far as the walk goes; a scroll view is the page scrolling itself; a
/// flexible child, a Scaffold, a stretched row, an expanding box or a
/// platform view needs the screen's height.
DVPageFit dvPageFitOf(RenderObject node, BoxConstraints screen) {
  if (node is RenderDVPageAndFooter) {
    final RenderBox? page = node.page;
    return page == null ? DVPageFit.grows : dvPageFitOf(page, screen);
  }
  if (node is RenderAbstractViewport) return DVPageFit.fills;
  if (node is RenderFlex) {
    if (node.direction == Axis.vertical) {
      RenderBox? child = node.firstChild;
      while (child != null) {
        final FlexParentData data = child.parentData! as FlexParentData;
        if ((data.flex ?? 0) > 0) return DVPageFit.fills;
        child = data.nextSibling;
      }
      return DVPageFit.grows;
    }
    if (node.crossAxisAlignment == CrossAxisAlignment.stretch) return DVPageFit.fills;
    return _childrenFit(node, screen);
  }
  if (node is RenderStack) {
    if (node.fit == StackFit.expand) return DVPageFit.fills;
    DVPageFit result = DVPageFit.grows;
    bool anyInFlow = false;
    RenderBox? child = node.firstChild;
    while (child != null) {
      final StackParentData data = child.parentData! as StackParentData;
      if (!data.isPositioned) {
        anyInFlow = true;
        result = _combine(result, dvPageFitOf(child, screen));
        if (result == DVPageFit.fills) return result;
      }
      child = data.nextSibling;
    }
    return anyInFlow ? result : DVPageFit.fills;
  }
  if (node is RenderConstrainedBox) {
    final BoxConstraints added = node.additionalConstraints;
    if (added.minHeight == double.infinity) return DVPageFit.fills;
    if (added.hasBoundedHeight) return DVPageFit.grows;
  }
  if (node is RenderLimitedBox && node.maxHeight.isFinite) return DVPageFit.grows;
  if (node is RenderAspectRatio) return DVPageFit.grows;
  if (node is RenderFractionallySizedOverflowBox && node.heightFactor != null) {
    return DVPageFit.fills;
  }
  if (node is RenderConstrainedOverflowBox) return DVPageFit.fills;
  if (node is RenderCustomMultiChildLayoutBox || node is RenderFlow) return DVPageFit.fills;
  if (node is RenderWrap ||
      node is RenderTable ||
      node is RenderListBody ||
      node is RenderParagraph ||
      node is RenderEditable) {
    return DVPageFit.grows;
  }
  if (node is RenderConstrainedLayoutBuilder) {
    bool built = false;
    node.visitChildren((_) => built = true);
    if (!built) return DVPageFit.unknown;
  }
  // ignore: invalid_use_of_protected_member
  if (node is RenderBox && node.sizedByParent) {
    // Sized by its constraints alone: a platform view, a texture. Taking the
    // whole height means it wants the screen.
    try {
      final Size size = node.getDryLayout(screen.loosen());
      if (size.height >= screen.maxHeight) return DVPageFit.fills;
    } on Object {
      return DVPageFit.fills;
    }
  }
  return _childrenFit(node, screen);
}

DVPageFit _childrenFit(RenderObject node, BoxConstraints screen) {
  DVPageFit result = DVPageFit.grows;
  node.visitChildren((RenderObject child) {
    if (result == DVPageFit.fills) return;
    result = _combine(result, dvPageFitOf(child, screen));
  });
  return result;
}

DVPageFit _combine(DVPageFit a, DVPageFit b) {
  if (a == DVPageFit.fills || b == DVPageFit.fills) return DVPageFit.fills;
  if (a == DVPageFit.unknown || b == DVPageFit.unknown) return DVPageFit.unknown;
  return DVPageFit.grows;
}

/// The page shell's viewport: the page laid out at the screen's height when
/// it fills the screen itself, otherwise at least the screen's height and as
/// tall as it needs, scrolled.
class RenderDVPageViewport extends RenderBox
    with RenderObjectWithChildMixin<RenderBox>
    implements RenderAbstractViewport {
  RenderDVPageViewport({required ViewportOffset offset, required this.onDecided})
      : _offset = offset;

  ValueChanged<bool> onDecided;

  ViewportOffset get offset => _offset;
  ViewportOffset _offset;
  set offset(ViewportOffset value) {
    if (value == _offset) return;
    if (attached) _offset.removeListener(_hasScrolled);
    _offset = value;
    if (attached) _offset.addListener(_hasScrolled);
    markNeedsLayout();
  }

  /// Whether the last layout scrolls the page.
  bool get scrolls => _scrolls;
  bool _scrolls = false;

  void _hasScrolled() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! ParentData) child.parentData = ParentData();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _offset.addListener(_hasScrolled);
  }

  @override
  void detach() {
    _offset.removeListener(_hasScrolled);
    super.detach();
  }

  @override
  bool get isRepaintBoundary => true;

  double get _maxScrollExtent =>
      !_scrolls || child == null ? 0 : math.max(0, child!.size.height - size.height);

  @override
  double computeMinIntrinsicWidth(double height) => child?.getMinIntrinsicWidth(height) ?? 0;
  @override
  double computeMaxIntrinsicWidth(double height) => child?.getMaxIntrinsicWidth(height) ?? 0;
  @override
  double computeMinIntrinsicHeight(double width) => child?.getMinIntrinsicHeight(width) ?? 0;
  @override
  double computeMaxIntrinsicHeight(double width) => child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    if (child == null) return constraints.smallest;
    if (!constraints.hasBoundedHeight) return child!.getDryLayout(constraints);
    return constraints.biggest;
  }

  BoxConstraints _growing(BoxConstraints constraints) => BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
        // At least the screen, as a document body is: a page that centres its
        // content still centres it.
        minHeight: constraints.maxHeight,
      );

  @override
  void performLayout() {
    final BoxConstraints constraints = this.constraints;
    final RenderBox? page = child;
    final bool wasScrolling = _scrolls;
    if (page == null) {
      size = constraints.smallest;
      _scrolls = false;
    } else if (!constraints.hasBoundedHeight) {
      // Already inside something that scrolls (a preview drawn at full
      // height): the shell has nothing to add.
      page.layout(constraints, parentUsesSize: true);
      size = constraints.constrain(page.size);
      _scrolls = false;
    } else {
      DVPageFit fit = dvPageFitOf(page, constraints);
      if (fit == DVPageFit.grows) {
        page.layout(_growing(constraints), parentUsesSize: true);
        _scrolls = true;
      } else {
        // Exactly what the page was given before the shell scrolled.
        page.layout(constraints, parentUsesSize: true);
        _scrolls = false;
        if (fit == DVPageFit.unknown) {
          // A LayoutBuilder has built now; settle it in this same layout.
          fit = dvPageFitOf(page, constraints);
          if (fit == DVPageFit.grows) {
            page.layout(_growing(constraints), parentUsesSize: true);
            _scrolls = true;
          }
        }
      }
      size = _scrolls ? constraints.biggest : constraints.constrain(page.size);
    }

    if (offset.hasPixels) {
      if (offset.pixels > _maxScrollExtent) {
        offset.correctBy(_maxScrollExtent - offset.pixels);
      } else if (offset.pixels < 0) {
        offset.correctBy(-offset.pixels);
      }
    }
    offset.applyViewportDimension(size.height);
    offset.applyContentDimensions(0, _maxScrollExtent);
    if (wasScrolling != _scrolls) markNeedsSemanticsUpdate();
    // A page that fits is not a scroll container: no scrollbar, no node.
    onDecided(_scrolls && _maxScrollExtent > 0);
  }

  Offset get _paintOffset => _paintOffsetFor(offset.pixels);

  Offset _paintOffsetFor(double position) => Offset(0, _scrolls ? -position : 0);

  bool get _clips => _scrolls && child != null && child!.size.height > size.height;

  final LayerHandle<ClipRectLayer> _clipLayer = LayerHandle<ClipRectLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    final RenderBox? page = child;
    if (page == null) return;
    final Offset paintOffset = _paintOffset;
    void paintPage(PaintingContext context, Offset offset) =>
        context.paintChild(page, offset + paintOffset);
    if (_clips) {
      _clipLayer.layer = context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        paintPage,
        oldLayer: _clipLayer.layer,
      );
    } else {
      _clipLayer.layer = null;
      paintPage(context, offset);
    }
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    super.dispose();
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final Offset paintOffset = _paintOffset;
    transform.translateByDouble(paintOffset.dx, paintOffset.dy, 0, 1);
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject? child) =>
      child != null && _clips ? Offset.zero & size : null;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final RenderBox? page = child;
    if (page == null) return false;
    return result.addWithPaintOffset(
      offset: _paintOffset,
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) =>
          page.hitTest(result, position: transformed),
    );
  }

  @override
  RevealedOffset getOffsetToReveal(RenderObject target, double alignment, {Rect? rect, Axis? axis}) {
    rect ??= target.paintBounds;
    if (target is! RenderBox || child == null || !_scrolls) {
      return RevealedOffset(offset: offset.pixels, rect: rect);
    }
    final Matrix4 transform = target.getTransformTo(child);
    final Rect bounds = MatrixUtils.transformRect(transform, rect);
    final double targetOffset = bounds.top - (size.height - bounds.height) * alignment;
    return RevealedOffset(offset: targetOffset, rect: bounds.shift(_paintOffsetFor(targetOffset)));
  }

  @override
  void showOnScreen({
    RenderObject? descendant,
    Rect? rect,
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
  }) {
    if (!_scrolls || !offset.allowImplicitScrolling) {
      return super.showOnScreen(descendant: descendant, rect: rect, duration: duration, curve: curve);
    }
    final Rect? newRect = RenderViewportBase.showInViewport(
      descendant: descendant,
      viewport: this,
      offset: offset,
      rect: rect,
      duration: duration,
      curve: curve,
    );
    super.showOnScreen(rect: newRect, duration: duration, curve: curve);
  }

  @override
  Rect? describeSemanticsClip(RenderObject? child) {
    if (!_scrolls) return null;
    final double remaining = _maxScrollExtent - offset.pixels;
    return Rect.fromLTRB(
      semanticBounds.left,
      semanticBounds.top - offset.pixels,
      semanticBounds.right,
      semanticBounds.bottom + remaining,
    );
  }
}


/// Whether scrolling on this screen is a finger's: Android and iOS, a browser
/// whose main pointer is touch (an iPad's Safari reports macOS), or a screen
/// as narrow as a phone. The page's scrollbar is left out there and kept on
/// desktop.
/// Narrower than this, a desktop window is laid out as a phone and gets no
/// page scrollbar. 782 logical pixels, where sigmadev.digital already drew
/// that line by hand (its columns stack below it), so no existing app changes:
/// a desktop window from 782 wide keeps its scrollbar.
const double dvPageNarrowWidth = 782;

bool dvPageScrollsByTouch(BuildContext context) {
  final TargetPlatform platform = Theme.of(context).platform;
  if (platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.fuchsia) {
    return true;
  }
  if (dvPrimaryPointerIsTouch()) return true;
  final double width = MediaQuery.maybeSizeOf(context)?.width ?? double.infinity;
  return width < dvPageNarrowWidth;
}

/// Whether the browser's main pointer is a finger. Tests replace it.
bool Function() dvPrimaryPointerIsTouch = history.dvPrimaryPointerIsTouch;

/// A layout's header and footer, with the framework scrolling the page
/// between them: what `DartvelLayout.header` and `DartvelLayout.footer`
/// build. The header stays put at the top; the page and then the footer
/// scroll beneath it, and on a page shorter than the screen the footer sits
/// at the bottom of the screen.
class DVLayoutSlots extends StatelessWidget {
  const DVLayoutSlots({super.key, this.header, this.footer, required this.body});

  final Widget? header;
  final Widget? footer;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final Widget scrolled = DVPageViewport(
      child: footer == null ? body : _DVPageAndFooter(page: body, footer: footer!),
    );
    final Widget? top = header;
    if (top == null) return scrolled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[top, Expanded(child: scrolled)],
    );
  }
}

class _DVPageAndFooter extends MultiChildRenderObjectWidget {
  _DVPageAndFooter({required Widget page, required Widget footer}) : super(children: <Widget>[page, footer]);

  @override
  RenderDVPageAndFooter createRenderObject(BuildContext context) => RenderDVPageAndFooter();
}

class _DVPageAndFooterData extends ContainerBoxParentData<RenderBox> {}

/// The page and, after it, the footer. Given unbounded height (the page
/// scrolls) the page takes what it needs, and at least the screen less the
/// footer, so a short page still puts the footer at the bottom. Given a
/// bounded height (the page scrolls itself or fills the screen) the page gets
/// the screen less the footer.
class RenderDVPageAndFooter extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _DVPageAndFooterData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _DVPageAndFooterData> {
  RenderBox? get page => firstChild;
  RenderBox? get footer => lastChild == firstChild ? null : lastChild;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _DVPageAndFooterData) child.parentData = _DVPageAndFooterData();
  }

  @override
  void performLayout() {
    final BoxConstraints constraints = this.constraints;
    final RenderBox? body = page;
    final RenderBox? end = footer;
    final BoxConstraints across = BoxConstraints(minWidth: constraints.maxWidth, maxWidth: constraints.maxWidth);
    double footerHeight = 0;
    if (end != null) {
      end.layout(across, parentUsesSize: true);
      footerHeight = end.size.height;
    }
    double pageHeight = 0;
    if (body != null) {
      if (constraints.hasBoundedHeight) {
        final double height = math.max(0, constraints.maxHeight - footerHeight);
        body.layout(across.copyWith(minHeight: height, maxHeight: height), parentUsesSize: true);
      } else {
        body.layout(across.copyWith(minHeight: math.max(0, constraints.minHeight - footerHeight)), parentUsesSize: true);
      }
      pageHeight = body.size.height;
      (body.parentData! as _DVPageAndFooterData).offset = Offset.zero;
    }
    if (end != null) (end.parentData! as _DVPageAndFooterData).offset = Offset(0, pageHeight);
    size = constraints.constrain(Size(constraints.maxWidth, pageHeight + footerHeight));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
