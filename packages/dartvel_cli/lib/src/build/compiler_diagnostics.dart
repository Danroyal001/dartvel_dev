/// The compiler's own errors, read out of a Flutter build log.
///
/// A wasm web build runs Flutter verbose and keeps the log in a file, showing
/// only progress lines. When the app does not compile, the reason is a few
/// lines in that log -- `lib/x.dart:12:5: Error: Undefined name 'y'.` and the
/// source line it points at -- followed by a long stack trace of the Flutter
/// tool's own. A failed build used to print the log's tail, which is the
/// stack trace, so "ProcessException ... exit code 254" was all anyone saw.
library;

/// A line as the compiler wrote it, without the `[ +12 ms]` stamp a verbose
/// Flutter log puts in front of each line it prints.
String dvWithoutLogStamp(String line) =>
    line.replaceFirst(RegExp(r'^\[\s*\+?\d+\s*ms\]\s?'), '');

/// dart2wasm and the front end: `file.dart:12:5: Error: message`.
final RegExp _sameLine = RegExp(r'^\S+\.dart:\d+:\d+: Error: ');

/// dart2js: `file.dart:12:5:` with the message on the next line.
final RegExp _ownLine = RegExp(r'^\S+\.dart:\d+:\d+:\s*$');

/// Whether [line] (stamp removed) starts a compiler error.
bool dvIsCompilerError(String line) => _sameLine.hasMatch(line);

/// Every compiler error in [log], each with the source lines the compiler
/// printed under it, at most [limit] errors.
///
/// Errors only: a warning does not fail a build, and a build that failed has
/// enough to read already.
List<String> dvCompilerErrors(String log, {int limit = 20}) {
  final List<String> lines = <String>[
    for (final String raw in log.split('\n')) raw.replaceAll('\r', ''),
  ];
  final List<String> out = <String>[];
  final Set<String> seen = <String>{};
  int found = 0;
  for (int i = 0; i < lines.length && found < limit; i++) {
    final String line = dvWithoutLogStamp(lines[i]);
    String? header;
    int next = i + 1;
    if (_sameLine.hasMatch(line)) {
      header = line;
    } else if (_ownLine.hasMatch(line) &&
        i + 1 < lines.length &&
        lines[i + 1].trimLeft().startsWith('Error: ')) {
      header = '$line ${lines[i + 1].trim()}';
      next = i + 2;
    }
    if (header == null) continue;
    // The same error once: Flutter repeats the compiler's output in the
    // exception it throws.
    if (!seen.add(header)) continue;
    found++;
    out.add(header);
    // The source line and its caret: unstamped lines straight after, until
    // the next error or the next thing the tool says.
    for (int j = next; j < lines.length && j < next + 4; j++) {
      final String context = lines[j];
      if (context.trim().isEmpty ||
          context.startsWith('[') ||
          _sameLine.hasMatch(context) ||
          _ownLine.hasMatch(context) ||
          RegExp(r'^\s*#\d+\s').hasMatch(context) ||
          context.startsWith('Target ')) {
        break;
      }
      out.add(context);
    }
  }
  return out;
}
