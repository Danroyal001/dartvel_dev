/// The arguments of an annotation, with nested parentheses counted.
///
/// Every parser of `@DVPage(...)` here was written as `@DVPage\(([^)]*)\)`,
/// and that was right for as long as no argument was a call. `@DVPage(
/// sitemap: DVPageSitemap(priority: 0.8))` is a call, and a character class
/// that excludes `)` stops inside it.
///
/// Both consequences are silent:
///
///   * page discovery requires `Widget name(` after the annotation, finds the
///     annotation's own trailing `)` there instead, and does not match -- so
///     the page is not discovered and its route is not in the generated
///     router. Nothing fails; the route is simply gone.
///   * a `policy:` written after the nested argument falls outside the
///     captured text, so a page that declared a guard is generated open.
///
/// The second is the same failure `dvPagePolicyFromSource` was written to
/// fix, reintroduced by adding an unrelated argument. Counting parentheses is
/// the only thing that stops it happening again for the next argument that
/// happens to be a call.
library;

/// The argument text of `@[name](...)` in [source], or null when it is not
/// there or is not closed.
///
/// Parentheses inside string literals do not count -- `title: 'Pricing
/// (beta)'` is one argument -- and neither do those inside comments.
String? dvAnnotationArgs(String source, String name) {
  final int open = _annotationOpenParen(source, name);
  if (open < 0) return null;
  final int close = _matchingParen(source, open);
  if (close < 0) return null;
  return source.substring(open + 1, close);
}

/// [source] with the arguments of every `@[name](...)` blanked to spaces.
///
/// For the regular expressions that only want to step over the annotation to
/// reach the declaration under it. `@DVPage(          )` matches `[^)]*`
/// again, and the copy is only ever matched against -- the arguments
/// themselves are read from the original by [dvAnnotationArgs].
///
/// Spaces rather than a shorter `@DVPage()`, because the caller uses the
/// match's offsets to find the page function's body in the *original*
/// source. A copy that is the same length everywhere keeps every offset
/// valid; newlines are kept for the same reason a stack trace should still
/// point at the right line.
String dvMaskAnnotationArgs(String source, String name) {
  final StringBuffer out = StringBuffer();
  int at = 0;
  while (true) {
    final int open = _annotationOpenParen(source, name, from: at);
    if (open < 0) break;
    final int close = _matchingParen(source, open);
    if (close < 0) break;
    out.write(source.substring(at, open + 1));
    for (int i = open + 1; i < close; i++) {
      out.write(source.codeUnitAt(i) == 0x0a ? '\n' : ' ');
    }
    out.write(')');
    at = close + 1;
  }
  out.write(source.substring(at));
  return out.toString();
}

/// The top-level arguments of [args], split on the commas that are not inside
/// a nested call, a collection literal or a string.
///
/// `sitemap: DVPageSitemap(priority: 0.8, changeFrequency: ...)` is one
/// argument; splitting it on every comma makes it two, the second of which
/// parses as an argument called `changeFrequency`.
List<String> dvSplitArgs(String args) {
  final List<String> parts = <String>[];
  int depth = 0;
  int start = 0;
  for (int i = 0; i < args.length; i++) {
    final int c = args.codeUnitAt(i);
    if (_isQuote(c)) {
      i = _endOfString(args, i);
      if (i < 0) return _trimmedNonEmpty(parts, args, start, args.length);
      continue;
    }
    if (c == _slash) {
      final int skipped = _endOfComment(args, i);
      if (skipped > i) {
        i = skipped;
        continue;
      }
    }
    if (c == _openParen || c == _openBracket || c == _openBrace) depth++;
    if (c == _closeParen || c == _closeBracket || c == _closeBrace) depth--;
    if (c == _comma && depth == 0) {
      parts.add(args.substring(start, i));
      start = i + 1;
    }
  }
  return _trimmedNonEmpty(parts, args, start, args.length);
}

List<String> _trimmedNonEmpty(
  List<String> parts,
  String args,
  int start,
  int end,
) {
  parts.add(args.substring(start, end));
  return parts
      .map((String part) => part.trim())
      .where((String part) => part.isNotEmpty)
      .toList(growable: false);
}

/// The index of the `(` that opens `@[name](`, or -1.
///
/// `@DVPageSitemap(` is not `@DVPage(`: the character after the name has to
/// be the parenthesis, or a longer annotation whose name starts with this one
/// would be read as this one.
int _annotationOpenParen(String source, String name, {int from = 0}) {
  final String needle = '@$name';
  int at = source.indexOf(needle, from);
  while (at >= 0) {
    int i = at + needle.length;
    while (i < source.length && _isSpace(source.codeUnitAt(i))) {
      i++;
    }
    if (i < source.length && source.codeUnitAt(i) == _openParen) return i;
    at = source.indexOf(needle, at + 1);
  }
  return -1;
}

/// The index of the `)` closing the `(` at [open], or -1 when it is unclosed.
int _matchingParen(String source, int open) {
  int depth = 0;
  for (int i = open; i < source.length; i++) {
    final int c = source.codeUnitAt(i);
    if (_isQuote(c)) {
      i = _endOfString(source, i);
      if (i < 0) return -1;
      continue;
    }
    if (c == _slash) {
      final int skipped = _endOfComment(source, i);
      if (skipped > i) {
        i = skipped;
        continue;
      }
    }
    if (c == _openParen) depth++;
    if (c == _closeParen) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// The index of the closing quote of the string starting at [start], or -1.
///
/// Handles the escape, so `'it\'s'` is one string, and the triple-quoted
/// forms, which a page's `title:` will not use but a doc comment above it
/// might sit inside.
int _endOfString(String source, int start) {
  final int quote = source.codeUnitAt(start);
  final bool triple = start + 2 < source.length &&
      source.codeUnitAt(start + 1) == quote &&
      source.codeUnitAt(start + 2) == quote;
  final int width = triple ? 3 : 1;
  int i = start + width;
  while (i < source.length) {
    final int c = source.codeUnitAt(i);
    if (c == _backslash) {
      i += 2;
      continue;
    }
    if (c == quote) {
      if (!triple) return i;
      if (i + 2 < source.length &&
          source.codeUnitAt(i + 1) == quote &&
          source.codeUnitAt(i + 2) == quote) {
        return i + 2;
      }
    }
    i++;
  }
  return -1;
}

/// The index of the last character of the comment starting at [start], or
/// [start] when nothing starts there.
int _endOfComment(String source, int start) {
  if (start + 1 >= source.length) return start;
  final int next = source.codeUnitAt(start + 1);
  if (next == _slash) {
    final int end = source.indexOf('\n', start);
    return end < 0 ? source.length - 1 : end;
  }
  if (next == _star) {
    final int end = source.indexOf('*/', start + 2);
    return end < 0 ? source.length - 1 : end + 1;
  }
  return start;
}

bool _isQuote(int c) => c == _singleQuote || c == _doubleQuote;

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d;

const int _openParen = 0x28;
const int _closeParen = 0x29;
const int _openBracket = 0x5b;
const int _closeBracket = 0x5d;
const int _openBrace = 0x7b;
const int _closeBrace = 0x7d;
const int _comma = 0x2c;
const int _singleQuote = 0x27;
const int _doubleQuote = 0x22;
const int _backslash = 0x5c;
const int _slash = 0x2f;
const int _star = 0x2a;
