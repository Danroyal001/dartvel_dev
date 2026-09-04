/// A table a keyboard and a screen reader can actually use.
///
/// `User.Table()` generated `DVBox.builder(...).grid(columns: 2)` -- a grid of
/// cards wearing the name Table. No header, no rows, no column, nothing to
/// arrow between, and nothing a screen reader could announce as tabular, while
/// the spec promises sorting, keyboard navigation, column management and
/// accessibility from it.
///
/// Most of what makes this a table rather than a grid is invisible in the
/// rendered pixels: what a screen reader is told, and where focus goes.
library dartvel_flutter.table;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One column: its heading, how to read a cell out of a row, and optionally
/// how to sort by it.
class DVTableColumn<T> {
  const DVTableColumn({
    required this.label,
    required this.value,
    this.compare,
    this.width,
  });

  final String label;

  /// The cell text for a row.
  final String Function(T row) value;

  /// Sorting is opt-in per column.
  ///
  /// A header that looks sortable and does nothing is worse than one that does
  /// not offer it, so the control only appears where this is supplied.
  final int Function(T a, T b)? compare;

  final double? width;

  bool get sortable => compare != null;
}

/// Which cell the keyboard is on.
class DVTableFocusPosition {
  const DVTableFocusPosition(this.row, this.column);
  final int row;
  final int column;
}

/// A header cell, as its own type so a test can find one.
class DVTableHeaderCell extends StatelessWidget {
  const DVTableHeaderCell({
    super.key,
    required this.label,
    required this.sortable,
    required this.sortDirection,
    required this.onTap,
    this.width,
  });

  final String label;
  final bool sortable;

  /// Null when this column is not the sort column.
  final bool? sortDirection;

  final VoidCallback? onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // Announced, not just drawn. Without it a sighted reader sees an arrow and
    // a screen reader user has no idea the data was reordered under them.
    final String announcement = sortDirection == null
        ? label
        : '$label, sorted ${sortDirection! ? 'ascending' : 'descending'}';

    final Widget content = Semantics(
      header: true,
      label: announcement,
      button: sortable,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Flexible, because a header cell is Expanded: on a phone every
            // column gets an equal and small share of the width, and a label
            // longer than its share used to overflow -- the yellow-and-black
            // stripe, on the framework's own table. Ellipsis rather than
            // wrapping, so the header stays one line tall whatever it says.
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelLarge,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
            // Outside the Flexible on purpose: the arrow is 14 pixels and it
            // is the only thing saying which way the data is sorted, so it is
            // the label that gives way, never the direction.
            if (sortDirection != null)
              Icon(
                sortDirection! ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
              ),
          ],
        ),
      ),
    );

    final Widget cell = sortable
        ? InkWell(onTap: onTap, child: content)
        : content;

    return width == null ? Expanded(child: cell) : SizedBox(width: width, child: cell);
  }
}

/// A table over [rows].
class DVTable<T> extends StatefulWidget {
  const DVTable(
    this.rows, {
    super.key,
    required this.columns,
    this.emptyLabel = 'No rows',
  });

  final List<T> rows;
  final List<DVTableColumn<T>> columns;

  /// Shown instead of an empty rectangle, which is indistinguishable from a
  /// table that failed to load -- for a sighted reader and a screen reader
  /// alike.
  final String emptyLabel;

  @override
  State<DVTable<T>> createState() => DVTableState<T>();
}

class DVTableState<T> extends State<DVTable<T>> {
  int? _sortColumn;
  bool _ascending = true;

  /// Where the keyboard is. Null until a cell is focused, so a table nobody
  /// has touched does not steal arrow keys from the page.
  int? focusedRow;
  int? focusedColumn;

  final FocusNode _keyboard = FocusNode(debugLabel: 'DVTable');

  @override
  void dispose() {
    _keyboard.dispose();
    super.dispose();
  }

  List<T> get _sorted {
    final int? column = _sortColumn;
    if (column == null) return widget.rows;
    final int Function(T, T)? compare = widget.columns[column].compare;
    if (compare == null) return widget.rows;

    final List<T> copy = List<T>.of(widget.rows);
    copy.sort(_ascending ? compare : (T a, T b) => compare(b, a));
    return copy;
  }

  void _toggleSort(int column) {
    if (!widget.columns[column].sortable) return;
    setState(() {
      if (_sortColumn == column) {
        _ascending = !_ascending;
      } else {
        _sortColumn = column;
        _ascending = true;
      }
      // Focus is deliberately not cleared. Reordering the rows under someone
      // reading one and dumping them back at the top is how a keyboard user
      // loses their place entirely.
    });
  }

  void _focus(int row, int column) {
    setState(() {
      // Clamped rather than wrapped: at the last column, right should stay put
      // rather than jumping to the next row.
      focusedRow = row.clamp(0, widget.rows.length - 1);
      focusedColumn = column.clamp(0, widget.columns.length - 1);
    });
    _keyboard.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final int? row = focusedRow;
    final int? column = focusedColumn;
    if (row == null || column == null) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        _focus(row, column + 1);
      case LogicalKeyboardKey.arrowLeft:
        _focus(row, column - 1);
      case LogicalKeyboardKey.arrowDown:
        _focus(row + 1, column);
      case LogicalKeyboardKey.arrowUp:
        _focus(row - 1, column);
      case LogicalKeyboardKey.home:
        _focus(row, 0);
      case LogicalKeyboardKey.end:
        _focus(row, widget.columns.length - 1);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final List<T> rows = _sorted;
    final ThemeData theme = Theme.of(context);

    return Focus(
      focusNode: _keyboard,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Row(
              children: <Widget>[
                for (int c = 0; c < widget.columns.length; c += 1)
                  DVTableHeaderCell(
                    label: widget.columns[c].label,
                    sortable: widget.columns[c].sortable,
                    sortDirection: _sortColumn == c ? _ascending : null,
                    width: widget.columns[c].width,
                    onTap: () => _toggleSort(c),
                  ),
              ],
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Semantics(
                label: widget.emptyLabel,
                child: Text(widget.emptyLabel),
              ),
            )
          else
            for (int r = 0; r < rows.length; r += 1)
              Row(
                children: <Widget>[
                  for (int c = 0; c < widget.columns.length; c += 1)
                    _cell(rows[r], r, c, rows.length),
                ],
              ),
        ],
      ),
    );
  }

  Widget _cell(T row, int r, int c, int total) {
    final DVTableColumn<T> column = widget.columns[c];
    final String text = column.value(row);
    final bool focused = focusedRow == r && focusedColumn == c;

    // "Grace" alone tells a screen reader user nothing. Which column, and
    // which row of how many, is the whole content of a table cell.
    final Widget cell = Semantics(
      label: '${column.label}, $text, row ${r + 1} of $total',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => _focus(r, c),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: focused
              ? BoxDecoration(
                  border: Border.all(color: Theme.of(context).focusColor),
                )
              : null,
          child: Text(text),
        ),
      ),
    );

    return column.width == null
        ? Expanded(child: cell)
        : SizedBox(width: column.width, child: cell);
  }
}
