/// Rewrites references to symbols left behind in a source file so a lowered
/// body can run in the generated library.
///
/// A lowered body is moved out of the file it was written in, so any top-level
/// name it used is no longer in scope; each has to be reached through the
/// source file's import prefix. The rewrite is textual, which is why this walks
/// the source rather than running a regular expression over it: a name inside a
/// string literal is not a reference, and a name in a `$name` interpolation
/// stops being one the moment it becomes `alias.name`, because Dart ends the
/// simple form at the identifier and treats the rest as literal text.
String dvQualifySourceSymbols(
  String source,
  String alias,
  Set<String> symbols,
) {
  if (symbols.isEmpty || alias.isEmpty) return source;
  return _qualify(source, alias, symbols);
}

String _qualify(String source, String alias, Set<String> symbols) {
  final StringBuffer out = StringBuffer();
  int at = 0;
  int plainStart = 0;

  void flushPlain(int end) {
    if (end > plainStart) {
      out.write(_qualifyCode(source.substring(plainStart, end), alias, symbols));
    }
  }

  while (at < source.length) {
    final String char = source[at];

    // Comments carry names that are not references.
    if (char == '/' && at + 1 < source.length) {
      final String next = source[at + 1];
      if (next == '/') {
        flushPlain(at);
        int end = source.indexOf('\n', at);
        if (end == -1) end = source.length;
        out.write(source.substring(at, end));
        at = end;
        plainStart = at;
        continue;
      }
      if (next == '*') {
        flushPlain(at);
        int end = source.indexOf('*/', at + 2);
        end = end == -1 ? source.length : end + 2;
        out.write(source.substring(at, end));
        at = end;
        plainStart = at;
        continue;
      }
    }

    if (char == "'" || char == '"') {
      flushPlain(at);
      final bool raw = at > 0 &&
          source[at - 1] == 'r' &&
          (at == 1 || !_isIdentifierPart(source[at - 2]));
      // The `r` was emitted as plain code already; only the quotes onward are
      // the literal.
      final int end = _stringEnd(source, at);
      final String literal = source.substring(at, end);
      out.write(
        raw ? literal : _qualifyStringLiteral(literal, alias, symbols),
      );
      at = end;
      plainStart = at;
      continue;
    }

    at += 1;
  }

  flushPlain(source.length);
  return out.toString();
}

/// Qualifies a span that contains no strings or comments.
String _qualifyCode(String code, String alias, Set<String> symbols) {
  String qualified = code;
  final List<String> ordered = symbols.toList()
    ..sort((String a, String b) => b.length - a.length);
  for (final String symbol in ordered) {
    qualified = qualified.replaceAllMapped(
      RegExp('(?<![A-Za-z0-9_.\$])${RegExp.escape(symbol)}(?![A-Za-z0-9_])'),
      (_) => '$alias.$symbol',
    );
  }
  return qualified;
}

/// Qualifies only the interpolations inside a string literal, leaving the
/// literal text as written.
String _qualifyStringLiteral(
  String literal,
  String alias,
  Set<String> symbols,
) {
  final StringBuffer out = StringBuffer();
  int at = 0;
  while (at < literal.length) {
    final String char = literal[at];
    if (char == r'\' && at + 1 < literal.length) {
      out.write(literal.substring(at, at + 2));
      at += 2;
      continue;
    }
    if (char == r'$' && at + 1 < literal.length) {
      if (literal[at + 1] == '{') {
        final int close = _interpolationEnd(literal, at + 1);
        final String inner = literal.substring(at + 2, close - 1);
        out.write('\${${_qualify(inner, alias, symbols)}}');
        at = close;
        continue;
      }
      final int nameEnd = _identifierEnd(literal, at + 1);
      if (nameEnd > at + 1) {
        final String name = literal.substring(at + 1, nameEnd);
        if (symbols.contains(name)) {
          // Braces are required: `$alias.name` would end the interpolation at
          // `alias` and leave `.name` as literal text.
          out.write('\${$alias.$name}');
        } else {
          out.write(literal.substring(at, nameEnd));
        }
        at = nameEnd;
        continue;
      }
    }
    out.write(char);
    at += 1;
  }
  return out.toString();
}

/// The index just past the closing quote of the literal starting at [start].
int _stringEnd(String source, int start) {
  final String quote = source[start];
  final bool triple = source.startsWith(quote * 3, start);
  final int delimiter = triple ? 3 : 1;
  int at = start + delimiter;
  while (at < source.length) {
    final String char = source[at];
    if (char == r'\') {
      at += 2;
      continue;
    }
    if (char == r'$' && at + 1 < source.length && source[at + 1] == '{') {
      at = _interpolationEnd(source, at + 1);
      continue;
    }
    if (triple) {
      if (source.startsWith(quote * 3, at)) return at + 3;
    } else {
      if (char == quote) return at + 1;
      if (char == '\n') return at;
    }
    at += 1;
  }
  return source.length;
}

/// The index just past the `}` closing an interpolation whose `{` is at [open].
int _interpolationEnd(String source, int open) {
  int depth = 0;
  int at = open;
  while (at < source.length) {
    final String char = source[at];
    if (char == "'" || char == '"') {
      at = _stringEnd(source, at);
      continue;
    }
    if (char == '{') depth += 1;
    if (char == '}') {
      depth -= 1;
      if (depth == 0) return at + 1;
    }
    at += 1;
  }
  return source.length;
}

int _identifierEnd(String source, int start) {
  int at = start;
  if (at < source.length && !_isIdentifierStart(source[at])) return start;
  while (at < source.length && _isIdentifierPart(source[at])) {
    at += 1;
  }
  return at;
}

bool _isIdentifierStart(String char) =>
    RegExp('[A-Za-z_]').hasMatch(char);

bool _isIdentifierPart(String char) =>
    RegExp('[A-Za-z0-9_]').hasMatch(char);
