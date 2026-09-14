/// Dart's comments and string literals, known exactly, for the analyses that
/// read source lexically.
///
/// Module trust reads a module's capabilities with this and the secrets check
/// reads which secrets a project uses with it. Both are security checks where
/// seeing less than the compiler sees is the failure, and they used to lex
/// separately: the secrets check stripped `//` and `/*` without knowing where
/// a string began, so a URL earlier on a line erased the read after it. One
/// lexer means one set of edge cases, fixed once.
library;

/// A Dart source with its comments blanked ([code]), and with its comments and
/// string literals blanked ([masked]).
///
/// Both are the source's length, with every newline kept, so an offset found
/// in one is the same place in the other and in the original.
class DVDartSourceView {
  const DVDartSourceView(this.code, this.masked);

  final String code;
  final String masked;
}

const int _newline = 10;
const int _return = 13;
const int _space = 32;
const int _slash = 47;
const int _star = 42;
const int _backslash = 92;
const int _dollar = 36;
const int _lbrace = 123;
const int _rbrace = 125;
const int _single = 39;
const int _double = 34;

/// Splits [source] into what the analysis may read as code.
DVDartSourceView dvDartSourceView(String source) {
  final int n = source.length;
  final List<int> code = List<int>.of(source.codeUnits);
  final List<int> masked = List<int>.of(source.codeUnits);

  void blank(List<int> target, int from, int to) {
    for (var i = from; i < to && i < n; i++) {
      if (target[i] != _newline && target[i] != _return) target[i] = _space;
    }
  }

  var i = 0;
  while (i < n) {
    final int c = source.codeUnitAt(i);
    if (c == _slash && i + 1 < n) {
      final int next = source.codeUnitAt(i + 1);
      if (next == _slash) {
        final int end = _lineEnd(source, i);
        blank(code, i, end);
        blank(masked, i, end);
        i = end;
        continue;
      }
      if (next == _star) {
        final int end = _blockCommentEnd(source, i);
        blank(code, i, end);
        blank(masked, i, end);
        i = end;
        continue;
      }
    }
    final _StringStart? start = _stringStartAt(source, i);
    if (start != null) {
      final int end = _stringEnd(source, start);
      blank(masked, i, end);
      i = end;
      continue;
    }
    i++;
  }
  return DVDartSourceView(
    String.fromCharCodes(code),
    String.fromCharCodes(masked),
  );
}

/// The 1-based line of [offset] in [source].
int dvDartLineOf(String source, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < source.length; i++) {
    if (source.codeUnitAt(i) == _newline) line++;
  }
  return line;
}

/// A call reading a secret by name, up to and including its `(`.
///
/// Match it against [DVDartSourceView.masked], so a call spelled inside a
/// string or a comment is not one, and read the name with
/// [dvDartStringLiteralAt] from [DVDartSourceView.code].
final RegExp dvSecretReadCall = RegExp(
  r'(?:\bDV\s*\.\s*Secrets|\bDVSecrets\s*\(\s*\))\s*\.\s*(?:get|maybeGet|getOr|has)\s*\(',
);

class _StringStart {
  const _StringStart(this.at, this.quote, this.raw, this.triple);

  /// Where the literal begins, prefix included.
  final int at;

  /// Index of the first quote character.
  final int quote;
  final bool raw;
  final bool triple;

  int get contentStart => quote + (triple ? 3 : 1);
}

bool _identifierUnit(int u) =>
    (u >= 48 && u <= 57) ||
    (u >= 65 && u <= 90) ||
    (u >= 97 && u <= 122) ||
    u == 95 ||
    u == _dollar;

_StringStart? _stringStartAt(String s, int i) {
  final int n = s.length;
  int quote = i;
  var raw = false;
  final int c = s.codeUnitAt(i);
  if ((c == 114 || c == 82) &&
      i + 1 < n &&
      (s.codeUnitAt(i + 1) == _single || s.codeUnitAt(i + 1) == _double) &&
      (i == 0 || !_identifierUnit(s.codeUnitAt(i - 1)))) {
    raw = true;
    quote = i + 1;
  } else if (c != _single && c != _double) {
    return null;
  }
  final int q = s.codeUnitAt(quote);
  final bool triple =
      quote + 2 < n &&
      s.codeUnitAt(quote + 1) == q &&
      s.codeUnitAt(quote + 2) == q;
  return _StringStart(i, quote, raw, triple);
}

/// The index just past the literal that [start] opens.
int _stringEnd(String s, _StringStart start) {
  final int n = s.length;
  final int q = s.codeUnitAt(start.quote);
  var j = start.contentStart;
  while (j < n) {
    final int u = s.codeUnitAt(j);
    if (!start.raw && u == _backslash) {
      j += 2;
      continue;
    }
    if (!start.raw &&
        u == _dollar &&
        j + 1 < n &&
        s.codeUnitAt(j + 1) == _lbrace) {
      j = _interpolationEnd(s, j + 2);
      continue;
    }
    if (start.triple) {
      if (u == q &&
          j + 2 < n &&
          s.codeUnitAt(j + 1) == q &&
          s.codeUnitAt(j + 2) == q) {
        return j + 3;
      }
    } else {
      if (u == q) return j + 1;
      if (u == _newline) return j;
    }
    j++;
  }
  return n;
}

/// The index just past the `}` closing an interpolation whose body starts at
/// [j], with the strings and comments inside it skipped.
int _interpolationEnd(String s, int j) {
  final int n = s.length;
  var depth = 1;
  while (j < n) {
    final int u = s.codeUnitAt(j);
    if (u == _slash && j + 1 < n && s.codeUnitAt(j + 1) == _slash) {
      j = _lineEnd(s, j);
      continue;
    }
    if (u == _slash && j + 1 < n && s.codeUnitAt(j + 1) == _star) {
      j = _blockCommentEnd(s, j);
      continue;
    }
    final _StringStart? nested = _stringStartAt(s, j);
    if (nested != null) {
      j = _stringEnd(s, nested);
      continue;
    }
    if (u == _lbrace) depth++;
    if (u == _rbrace) {
      depth--;
      if (depth == 0) return j + 1;
    }
    j++;
  }
  return n;
}

int _lineEnd(String s, int i) {
  final int end = s.indexOf('\n', i);
  return end < 0 ? s.length : end;
}

/// Block comments nest in Dart.
int _blockCommentEnd(String s, int i) {
  final int n = s.length;
  var depth = 0;
  var j = i;
  while (j < n) {
    if (j + 1 < n &&
        s.codeUnitAt(j) == _slash &&
        s.codeUnitAt(j + 1) == _star) {
      depth++;
      j += 2;
      continue;
    }
    if (j + 1 < n &&
        s.codeUnitAt(j) == _star &&
        s.codeUnitAt(j + 1) == _slash) {
      depth--;
      j += 2;
      if (depth == 0) return j;
      continue;
    }
    j++;
  }
  return n;
}

/// The value of the string literal starting at or after [offset] in [code],
/// when it is one plain literal.
///
/// Null when the argument is not a literal, or is a literal the build cannot
/// read the value of: interpolated, escaped, or joined to another string by
/// adjacency or `+`. `'https://api.stripe.com' '.evil.example'` is one string
/// to the compiler, and reading the first half as the host would grant a
/// domain the code never calls.
String? dvDartStringLiteralAt(String code, int offset) {
  var i = offset;
  while (i < code.length && _isSpace(code.codeUnitAt(i))) {
    i++;
  }
  if (i >= code.length) return null;
  final _StringStart? start = _stringStartAt(code, i);
  if (start == null) return null;
  final int end = _stringEnd(code, start);
  final int closeLength = start.triple ? 3 : 1;
  if (end - closeLength < start.contentStart) return null;
  final String content = code.substring(start.contentStart, end - closeLength);
  if (!start.raw && (content.contains(r'$') || content.contains(r'\'))) {
    return null;
  }
  if (content.contains('\n')) return null;
  var after = end;
  while (after < code.length && _isSpace(code.codeUnitAt(after))) {
    after++;
  }
  if (after < code.length) {
    final int next = code.codeUnitAt(after);
    if (next == 43 || _stringStartAt(code, after) != null) return null;
  }
  return content;
}

bool _isSpace(int u) => u == _space || u == _newline || u == _return || u == 9;
