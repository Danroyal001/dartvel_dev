/// Everything hoverable has a tooltip, read from the source.
///
/// At run time a debug build refuses a nameless icon control with the file and
/// line that drew it. A release build compiles that away, so the same rule is
/// read lexically here and run by `dartvel build` (which fails) and
/// `dartvel doctor` (which reports). The lexer blanks comments and strings, so
/// a word in a comment or a string is never mistaken for a control or a name.
///
/// What it judges, conservatively -- it only reports what it can be sure of,
/// and leaves the rest to the run-time check:
///
/// * `IconButton`, `FloatingActionButton` and `PopupMenuButton` must pass
///   `tooltip:` themselves.
/// * A `DVModifier` chain with `.onTap(` / `.onPressed(` on an owner that
///   shows an icon and no text must carry `.tooltip(` or `.semanticLabel(`.
///   An owner with text takes its name from the text.
/// * An `InkWell` / `GestureDetector` with `onTap` and only an icon must sit
///   directly in a `Tooltip` or `Semantics`.
library dartvel_cli.analysis.tooltip_lint;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'dart_source_lexer.dart';

/// One control that has no tooltip.
class DVTooltipFinding {
  const DVTooltipFinding({
    required this.path,
    required this.line,
    required this.control,
    required this.fix,
  });

  final String path;
  final int line;
  final String control;
  final String fix;

  @override
  String toString() => '$path:$line  $control has no tooltip. $fix';
}

/// A call that draws words: `Text(`, `DVText(`, or any helper named for text
/// (`caption(`, `body(`, `label(`, `title(`...). A control that shows words
/// is named by them.
final RegExp _showsWords = RegExp(
  r'(?<![\w])\w*(Text|text|Label|label|caption|body|title|overline|heading)\w*\s*\(',
);

const String _rawFix = "Add tooltip: 'What it does' -- it is also the "
    'screen-reader name.';
const String _gestureFix = "Wrap it in Tooltip(message: 'What it does', child: ...) "
    'and name it with Semantics(label: ...) (or use DVIconButton).';
const String _modifierFix = "Add .tooltip('What it does') to its DVModifier "
    '(or use DVIconButton(label: ...)); it is also the screen-reader name.';

/// Findings in one source file.
List<DVTooltipFinding> dvFindUntooltippedControls({
  required String path,
  required String source,
}) {
  final DVDartSourceView view = dvDartSourceView(source);
  final String text = view.masked;
  final List<DVTooltipFinding> findings = <DVTooltipFinding>[];

  int lineOf(int offset) {
    var line = 1;
    for (var i = 0; i < offset && i < source.length; i++) {
      if (source.codeUnitAt(i) == 10) line++;
    }
    return line;
  }

  void add(int offset, String control, String fix) => findings.add(
        DVTooltipFinding(
          path: path,
          line: lineOf(offset),
          control: control,
          fix: fix,
        ),
      );

  // --- raw Flutter controls that take a tooltip: argument
  final RegExp raw = RegExp(
    r'(?<![\w.])(IconButton(?:\.(?:filled|filledTonal|outlined))?|FloatingActionButton(?:\.small|\.large)?|PopupMenuButton)\s*(?:<[^<>()]*>)?\(',
  );
  for (final RegExpMatch match in raw.allMatches(text)) {
    final int open = match.end - 1;
    final int close = _matching(text, open);
    if (close < 0) continue;
    final String args = _topLevel(text.substring(open + 1, close));
    if (!RegExp(r'(?<![\w])tooltip\s*:').hasMatch(args)) {
      add(match.start, match.group(1)!, _rawFix);
    }
  }

  // --- a DVModifier chain that makes something pressable
  final RegExp tap = RegExp(r'\.(onTap|onPressed)\s*\(');
  final Set<int> judgedChains = <int>{};
  for (final RegExpMatch match in tap.allMatches(text)) {
    final int head = _chainStart(text, match.start);
    if (head < 0 || !judgedChains.add(head)) continue;
    if (!text.startsWith('DVModifier', head)) continue; // cannot be judged
    final int end = _chainEnd(text, match.start);
    final String chain = text.substring(head, end);
    if (RegExp(r'\.(tooltip|semanticLabel)\s*\(').hasMatch(chain)) continue;

    // The call this modifier is an argument of.
    final int owner = _enclosingOpen(text, head);
    if (owner < 0) continue;
    final String callee = _calleeBefore(text, owner);
    final int ownerClose = _matching(text, owner);
    if (ownerClose < 0) continue;
    var argumentsText = text.substring(owner + 1, ownerClose);
    var ownerName = callee;
    if (callee == 'modifier' || callee == 'styleModifier') {
      // DVText('x').modifier(DVModifier()...): judge the thing it is called on.
      final int receiverEnd = _skipBack(text, owner - callee.length - 1);
      final int receiverOpen = text.lastIndexOf('(', receiverEnd);
      final int fromOpen = receiverEnd >= 0 && text[receiverEnd] == ')'
          ? _matchingBack(text, receiverEnd)
          : receiverOpen;
      if (fromOpen < 0) continue;
      ownerName = _calleeBefore(text, fromOpen);
      argumentsText = text.substring(fromOpen + 1, receiverEnd);
    }
    if (ownerName == 'DVText') continue;
    if (!ownerName.startsWith('DVBox')) continue; // cannot be judged
    final bool hasText = _showsWords.hasMatch(argumentsText);
    final bool hasIcon = RegExp(r'(?<![\w])Icon\s*\(|(?<![\w])Icons\.|IconData')
        .hasMatch(argumentsText);
    if (hasIcon && !hasText) {
      add(match.start, 'A control made with .${match.group(1)}()', _modifierFix);
    }
  }

  // --- raw gestures around an icon
  final RegExp gesture = RegExp(r'(?<![\w.])(InkWell|GestureDetector)\s*\(');
  for (final RegExpMatch match in gesture.allMatches(text)) {
    final int open = match.end - 1;
    final int close = _matching(text, open);
    if (close < 0) continue;
    final String inner = text.substring(open + 1, close);
    if (!RegExp(r'(?<![\w])onTap\s*:').hasMatch(_topLevel(inner))) continue;
    final bool hasText = _showsWords.hasMatch(inner);
    final bool hasIcon =
        RegExp(r'(?<![\w])Icon\s*\(|(?<![\w])Icons\.').hasMatch(inner);
    if (!hasIcon || hasText) continue;
    // Named by an ancestor a few levels up: a Material and a Semantics
    // between the gesture and its Tooltip is still a named control.
    var named = false;
    var at = match.start;
    for (var level = 0; level < 6 && !named; level++) {
      final int enclosing = _enclosingOpen(text, at);
      if (enclosing < 0) break;
      named = RegExp(r'(^|\.)(Tooltip|Semantics|tooltip)$')
          .hasMatch(_calleeBefore(text, enclosing));
      at = enclosing;
    }
    if (named) continue;
    add(match.start, match.group(1)!, _gestureFix);
  }

  findings.sort((DVTooltipFinding a, DVTooltipFinding b) => a.line.compareTo(b.line));
  return findings;
}

/// Every Dart file under a project's `lib/`, except generated code.
List<DVTooltipFinding> dvScanProjectForTooltips(String root) {
  final Directory lib = Directory(p.join(root, 'lib'));
  if (!lib.existsSync()) return const <DVTooltipFinding>[];
  final List<DVTooltipFinding> findings = <DVTooltipFinding>[];
  final List<File> files = lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .where((File f) => !RegExp(r'\.(g|freezed|dv|generated)\.dart$').hasMatch(f.path))
      .where((File f) => !f.path.contains('${p.separator}generated${p.separator}'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
  for (final File file in files) {
    findings.addAll(dvFindUntooltippedControls(
      path: p.relative(file.path, from: root),
      source: file.readAsStringSync(),
    ));
  }
  return findings;
}

// ---- lexical helpers over source whose strings and comments are blanked

int _matching(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    final String c = text[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

int _matchingBack(String text, int close) {
  var depth = 0;
  for (var i = close; i >= 0; i--) {
    final String c = text[i];
    if (c == ')' || c == ']' || c == '}') depth++;
    if (c == '(' || c == '[' || c == '{') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// [args] with everything inside nested brackets blanked, so a named argument
/// is found only at the level of the call being judged.
String _topLevel(String args) {
  final StringBuffer out = StringBuffer();
  var depth = 0;
  for (var i = 0; i < args.length; i++) {
    final String c = args[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
      out.write(c);
      continue;
    }
    if (c == ')' || c == ']' || c == '}') {
      depth--;
      out.write(c);
      continue;
    }
    out.write(depth == 0 ? c : ' ');
  }
  return out.toString();
}

int _skipBack(String text, int from) {
  var i = from;
  while (i >= 0 && text[i].trim().isEmpty) {
    i--;
  }
  return i;
}

final RegExp _identifierChar = RegExp(r'[\w$]');

/// The index where the member chain ending at [dot] begins (`DVModifier` in
/// `DVModifier().padding(8).onTap(x)`), or -1.
int _chainStart(String text, int dot) {
  var i = dot;
  while (true) {
    i = _skipBack(text, i - 1);
    if (i < 0) return -1;
    if (text[i] == ')') {
      final int open = _matchingBack(text, i);
      if (open < 0) return -1;
      i = open;
      i = _skipBack(text, i - 1) + 1;
    } else {
      i++;
    }
    // i is one past the end of an identifier; walk back over it.
    var start = i;
    while (start > 0 && _identifierChar.hasMatch(text[start - 1])) {
      start--;
    }
    if (start == i) return -1;
    final int before = _skipBack(text, start - 1);
    if (before >= 0 && text[before] == '.') {
      i = before;
      continue;
    }
    // `const DVModifier()` -> the head is the identifier.
    return start;
  }
}

int _chainEnd(String text, int from) {
  var i = from;
  while (true) {
    final Match? next =
        RegExp(r'\s*\.\s*[\w$]+\s*\(').matchAsPrefix(text, i);
    if (next == null) return i;
    final int close = _matching(text, next.end - 1);
    if (close < 0) return text.length;
    i = close + 1;
  }
}

/// The index of the `(` that encloses [offset], or -1.
int _enclosingOpen(String text, int offset) {
  var depth = 0;
  for (var i = offset - 1; i >= 0; i--) {
    final String c = text[i];
    if (c == ')' || c == ']' || c == '}') depth++;
    if (c == '(' || c == '[' || c == '{') {
      if (depth == 0) return c == '(' ? i : _enclosingOpen(text, i);
      depth--;
    }
  }
  return -1;
}

/// The name before the `(` at [open]: `DVBox.row` for `DVBox.row(`.
String _calleeBefore(String text, int open) {
  var end = _skipBack(text, open - 1);
  // Generic arguments: DVBox<T>(
  if (end >= 0 && text[end] == '>') {
    final int lt = text.lastIndexOf('<', end);
    if (lt >= 0) end = _skipBack(text, lt - 1);
  }
  var start = end + 1;
  while (start > 0 && RegExp(r'[\w$.]').hasMatch(text[start - 1])) {
    start--;
  }
  return text.substring(start, end + 1);
}
