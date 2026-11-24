/// Tab and Shift+Tab through what a lazy list has not built yet.
///
/// Every scrollable DVBox list builds only the rows near the screen, and a
/// long DVBox list in a page that scrolls holds a place for its later rows
/// (DVNearScreen). A row that is not built has no focus node, so Flutter's
/// traversal cannot go to it. On Tori and Learnacer (Dartvel 3.47.7) a layout
/// that is one scrollable list of header, page and footer left the footer
/// links out of the Tab order: Tab from the last control built went back to
/// the top of the page, or out of it. A long catalogue lost its later rows the
/// same way, Tab jumping from the last row built to the footer after it.
///
/// The page shell answers Tab and Shift+Tab with [DVLazyNextFocusAction] and
/// [DVLazyPreviousFocusAction]. Before the focus leaves a scrollable, or
/// passes rows that are only placeholders, they build what lies in the way:
/// the placeholders between the focus and the next control are built, and a
/// list with no control left built in that direction is scrolled on a screen
/// at a time until one is, or until it ends. Then Flutter's own traversal
/// moves the focus, in its own order, and scrolls the control into view as it
/// always does. Where nothing is waiting to be built nothing differs.
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../lists/near_screen.dart';

/// Tab: see the library comment.
class DVLazyNextFocusAction extends Action<NextFocusIntent> {
  @override
  bool invoke(NextFocusIntent intent) => DVLazyTraversal.move(forward: true);

  @override
  KeyEventResult toKeyEventResult(NextFocusIntent intent, bool invokeResult) =>
      invokeResult ? KeyEventResult.handled : KeyEventResult.skipRemainingHandlers;
}

/// Shift+Tab: see the library comment.
class DVLazyPreviousFocusAction extends Action<PreviousFocusIntent> {
  @override
  bool invoke(PreviousFocusIntent intent) => DVLazyTraversal.move(forward: false);

  @override
  KeyEventResult toKeyEventResult(PreviousFocusIntent intent, bool invokeResult) =>
      invokeResult ? KeyEventResult.handled : KeyEventResult.skipRemainingHandlers;
}

abstract final class DVLazyTraversal {
  /// How many screens a walk may scroll through before it gives up and lets
  /// Flutter's traversal decide: a list that keeps growing as it is scrolled
  /// (an endless feed) has no end to reach.
  static const int maxSteps = 400;

  static bool _walking = false;

  /// Moves the focus one control on, building what is in the way first.
  ///
  /// True when the key was dealt with: the focus moved, or a walk is under
  /// way that will move it once the frames it needs are drawn. False when
  /// Flutter's traversal reached the edge and the browser is to have the key.
  static bool move({required bool forward}) {
    final FocusNode? current = FocusManager.instance.primaryFocus;
    if (current == null) return false;
    // A press while a walk is still scrolling: the walk answers for both.
    if (_walking) return true;
    if (_stepFor(current, forward) == null) return _traverse(current, forward);
    _walking = true;
    unawaited(_walk(current, forward).whenComplete(() => _walking = false));
    return true;
  }

  static bool _traverse(FocusNode node, bool forward) =>
      forward ? node.nextFocus() : node.previousFocus();

  static Future<void> _walk(FocusNode current, bool forward) async {
    // Where the focus was, in each scrollable's own content, so the walk
    // still knows what "after" means once the row it was in is let go.
    final List<_Anchor> anchors = _anchorsOf(current);
    for (int step = 0; step < maxSteps; step++) {
      final _Step? next = current.context != null && current.context!.mounted
          ? _stepFor(current, forward)
          : _stepFromAnchors(anchors, current.nearestScope, forward);
      if (next == null) break;
      next.run();
      SchedulerBinding.instance.scheduleFrame();
      await SchedulerBinding.instance.endOfFrame;
    }
    if (current.context != null && current.context!.mounted && current.hasPrimaryFocus) {
      _traverse(current, forward);
      return;
    }
    // The row the focus was in has been let go: go to the nearest control
    // past where it was.
    final FocusNode? target = _nearestPast(anchors, current.nearestScope, forward);
    if (target == null) return;
    target.requestFocus();
    final BuildContext? context = target.context;
    if (context != null) {
      unawaited(Scrollable.ensureVisible(
        context,
        alignmentPolicy: forward
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      ));
    }
  }

  /// What has to happen before the focus can move on from [current], or null
  /// when nothing is in the way.
  static _Step? _stepFor(FocusNode current, bool forward) {
    final BuildContext? context = current.context;
    if (context == null || !context.mounted) return null;
    final RenderObject? render = context.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize) return null;
    for (ScrollableState? list = Scrollable.maybeOf(context);
        list != null;
        list = Scrollable.maybeOf(list.context)) {
      final _Frame? frame = _Frame.ofState(list);
      if (frame == null) continue;
      final _Step? step = _stepIn(frame, frame.extentOf(render), current, current.nearestScope, forward);
      if (step != null) return step;
    }
    return null;
  }

  static _Step? _stepFromAnchors(List<_Anchor> anchors, FocusScopeNode? scope, bool forward) {
    for (final _Anchor anchor in anchors) {
      if (!anchor.list.mounted) continue;
      final _Frame? frame = _Frame.of(anchor.list);
      if (frame == null) continue;
      final _Step? step = _stepIn(frame, anchor.extent, null, scope, forward);
      if (step != null) return step;
    }
    return null;
  }

  static _Step? _stepIn(_Frame frame, _Extent at, FocusNode? current, FocusScopeNode? scope, bool forward) {
    // The nearest control already built on that side of the focus, in this
    // scrollable.
    double? nearest;
    for (final FocusNode node in scope?.traversalDescendants ?? const <FocusNode>[]) {
      if (identical(node, current)) continue;
      final _Extent? extent = frame.extentOfNode(node);
      if (extent == null || !extent.isPast(at, forward)) continue;
      if (nearest == null || (forward ? extent.start < nearest : extent.start > nearest)) {
        nearest = extent.start;
      }
    }
    // Placeholders between the focus and that control hold rows that come
    // first: build them all, then look again.
    final List<DVUnbuiltRow> waiting = <DVUnbuiltRow>[];
    for (final DVUnbuiltRow row in dvUnbuiltRows) {
      final BuildContext context = row.context;
      if (!context.mounted || !frame.contains(context)) continue;
      final RenderObject? box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final _Extent extent = frame.extentOf(box);
      if (!extent.isPast(at, forward)) continue;
      if (nearest != null && (forward ? extent.start >= nearest : extent.start <= nearest)) continue;
      waiting.add(row);
    }
    if (waiting.isNotEmpty) {
      return _Step(() {
        for (final DVUnbuiltRow row in waiting) {
          row.buildNow();
        }
      });
    }
    if (nearest != null) return null;
    // Nothing built on that side: scroll on, so the list builds what is
    // there. The focus may move out of view meanwhile; the traversal at the
    // end scrolls to wherever it lands.
    final ScrollPosition position = frame.list.position;
    if (!position.hasContentDimensions || !position.hasViewportDimension) return null;
    final bool more = forward
        ? position.pixels < position.maxScrollExtent - 0.5
        : position.pixels > position.minScrollExtent + 0.5;
    if (!more) return null;
    final double by = position.viewportDimension * 0.8;
    return _Step(() => position.jumpTo((position.pixels + (forward ? by : -by))
        .clamp(position.minScrollExtent, position.maxScrollExtent)));
  }

  static List<_Anchor> _anchorsOf(FocusNode current) {
    final BuildContext? context = current.context;
    final RenderObject? render = context?.findRenderObject();
    if (context == null || render is! RenderBox || !render.hasSize) return const <_Anchor>[];
    return <_Anchor>[
      for (ScrollableState? list = Scrollable.maybeOf(context);
          list != null;
          list = Scrollable.maybeOf(list.context))
        if (_Frame.ofState(list) case final _Frame frame) _Anchor(list.context, frame.extentOf(render)),
    ];
  }

  static FocusNode? _nearestPast(List<_Anchor> anchors, FocusScopeNode? scope, bool forward) {
    for (final _Anchor anchor in anchors) {
      if (!anchor.list.mounted) continue;
      final _Frame? frame = _Frame.of(anchor.list);
      if (frame == null) continue;
      FocusNode? best;
      _Extent? bestExtent;
      for (final FocusNode node in scope?.traversalDescendants ?? const <FocusNode>[]) {
        final _Extent? extent = frame.extentOfNode(node);
        if (extent == null || !extent.isPast(anchor.extent, forward)) continue;
        if (bestExtent == null || extent.isPast(bestExtent, !forward)) {
          best = node;
          bestExtent = extent;
        }
      }
      if (best != null) return best;
    }
    return null;
  }
}

class _Step {
  const _Step(this.run);
  final VoidCallback run;
}

class _Anchor {
  const _Anchor(this.list, this.extent);

  /// The scrollable's element; its state is read again each time, as the
  /// list may have been rebuilt.
  final BuildContext list;
  final _Extent extent;
}

/// Where something is along a scrollable's axis, in the scrollable's own
/// content (so it does not change as the list scrolls), and across it.
class _Extent {
  const _Extent(this.start, this.end, this.across);

  final double start;
  final double end;
  final double across;

  /// Whether this comes after [other] in reading order along the axis
  /// ([forward]), or before it.
  bool isPast(_Extent other, bool forward) {
    const double slack = 1;
    final bool sameLine = start < other.end - slack && end > other.start + slack;
    if (sameLine) return forward ? across > other.across + slack : across < other.across - slack;
    return forward ? start >= other.end - slack : end <= other.start + slack;
  }
}

/// A scrollable going down or right, and how to place things in its content.
class _Frame {
  _Frame._(this.list, this.viewport, this.vertical);

  final ScrollableState list;
  final RenderBox viewport;
  final bool vertical;

  static _Frame? of(BuildContext listContext) {
    final ScrollableState? list = listContext is StatefulElement && listContext.state is ScrollableState
        ? listContext.state as ScrollableState
        : null;
    return list == null ? null : ofState(list);
  }

  static _Frame? ofState(ScrollableState list) {
    final AxisDirection direction = list.axisDirection;
    // Lists laid out from the bottom or the right (a chat) read the other
    // way; Flutter's own traversal is left to them.
    if (direction != AxisDirection.down && direction != AxisDirection.right) return null;
    final RenderObject? viewport = list.context.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) return null;
    if (!list.position.hasPixels) return null;
    return _Frame._(list, viewport, direction == AxisDirection.down);
  }

  bool contains(BuildContext context) {
    for (ScrollableState? scrollable = Scrollable.maybeOf(context);
        scrollable != null;
        scrollable = Scrollable.maybeOf(scrollable.context)) {
      if (identical(scrollable, list)) return true;
    }
    return false;
  }

  _Extent extentOf(RenderBox box) {
    final Rect rect = MatrixUtils.transformRect(box.getTransformTo(viewport), Offset.zero & box.size);
    final double pixels = list.position.pixels;
    return vertical
        ? _Extent(rect.top + pixels, rect.bottom + pixels, rect.left)
        : _Extent(rect.left + pixels, rect.right + pixels, rect.top);
  }

  _Extent? extentOfNode(FocusNode node) {
    final BuildContext? context = node.context;
    if (context == null || !context.mounted || !contains(context)) return null;
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return extentOf(box);
  }
}
