/// Columns and rows of a terminal.
class DVTerminalSize {
  final int columns;
  final int rows;

  const DVTerminalSize({required this.columns, required this.rows});

  @override
  bool operator ==(Object other) =>
      other is DVTerminalSize && other.columns == columns && other.rows == rows;

  @override
  int get hashCode => Object.hash(columns, rows);

  @override
  String toString() => '${columns}x$rows';
}
