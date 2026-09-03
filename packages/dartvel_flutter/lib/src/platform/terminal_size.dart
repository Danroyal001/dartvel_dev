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

/// [dvDisplayAvailable], for a given environment and OS name.
bool dvDisplayAvailableIn(Map<String, String> environment, {required String os}) {
  if (os != 'linux') return true;
  return (environment['DISPLAY'] ?? '').isNotEmpty || (environment['WAYLAND_DISPLAY'] ?? '').isNotEmpty;
}

/// The terminal runner beside the GUI binary: the same name with `-cli`,
/// keeping a Windows `.exe`. What `dartvel build <desktop>-cli` produces.
String dvTerminalRunnerPathFor(String executable) {
  final RegExpMatch? exe = RegExp(r'\.exe$', caseSensitive: false).firstMatch(executable);
  if (exe != null) return '${executable.substring(0, exe.start)}-cli${executable.substring(exe.start)}';
  return '$executable-cli';
}
