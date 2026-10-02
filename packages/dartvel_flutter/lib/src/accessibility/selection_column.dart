/// One column of a page, selected as a column.
///
/// A selection area asks what it can select, in reading order, where a drag
/// begins, and stops at the first thing that says the pointer is above it.
/// Beside a sidebar of separate texts -- a navigation rail, a list of records
/// -- the content column is one tall scrolling region, and Flutter puts a tall
/// region after the short texts to its left. A drag across a line of content
/// was offered to the sidebar first, reached a sidebar item lower down, and
/// stopped there: nothing was selected, and Ctrl+C copied an empty string.
/// Studio's rail and list panes are that layout, and so is any application
/// with a sidebar.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Makes everything beneath it one column for text selection.
///
/// A drag level with the column but beside it passes the column by as a
/// single block -- after it when the pointer is to its right, before it when
/// to its left -- the way one paragraph answers a pointer beside it, so the
/// column next to it is reached. Text inside stays selectable as before, and
/// a drag from the column into the content beside it selects to the column's
/// end and then on. With no selection area above, it draws its child and
/// nothing else.
class DVSelectionColumn extends StatefulWidget {
  const DVSelectionColumn({super.key, required this.child});

  final Widget child;

  @override
  State<DVSelectionColumn> createState() => _DVSelectionColumnState();
}

class _DVSelectionColumnState extends State<DVSelectionColumn> {
  final _DVColumnSelectionDelegate _delegate = _DVColumnSelectionDelegate();

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SelectionContainer(delegate: _delegate, child: widget.child);
}

class _DVColumnSelectionDelegate extends StaticSelectionContainerDelegate {
  @override
  SelectionResult handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent event) {
    final Rect? column = _columnRect();
    if (column != null) {
      final Offset pointer = event.globalPosition;
      final bool level =
          pointer.dy >= column.top && pointer.dy <= column.bottom;
      if (level && pointer.dx > column.right) {
        // Past the whole column: as if the pointer were after its last line.
        return super.handleSelectionEdgeUpdate(
            _movedTo(event, column.bottomRight + const Offset(1, 1)));
      }
      if (level && pointer.dx < column.left) {
        // Before the whole column: as if the pointer were before its first.
        return super.handleSelectionEdgeUpdate(
            _movedTo(event, column.topLeft - const Offset(1, 1)));
      }
    }
    return super.handleSelectionEdgeUpdate(event);
  }

  /// Where this column's text is on screen: every child's boxes together.
  Rect? _columnRect() {
    Rect? column;
    for (final Selectable selectable in selectables) {
      if (!selectable.size.isFinite || selectable.boundingBoxes.isEmpty) {
        continue;
      }
      final Matrix4 toScreen = selectable.getTransformTo(null);
      for (final Rect box in selectable.boundingBoxes) {
        final Rect onScreen = MatrixUtils.transformRect(toScreen, box);
        column = column == null ? onScreen : column.expandToInclude(onScreen);
      }
    }
    return column;
  }

  static SelectionEdgeUpdateEvent _movedTo(
          SelectionEdgeUpdateEvent event, Offset position) =>
      event.type == SelectionEventType.startEdgeUpdate
          ? SelectionEdgeUpdateEvent.forStart(
              globalPosition: position, granularity: event.granularity)
          : SelectionEdgeUpdateEvent.forEnd(
              globalPosition: position, granularity: event.granularity);
}
