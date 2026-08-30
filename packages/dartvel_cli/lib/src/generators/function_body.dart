/// Reading a Dart function body off source text, and lowering it into the
/// generated widget that will run it.
library dartvel_cli.generators.function_body;

/// A function's body, however it was written.
class DVFunctionBody {
  const DVFunctionBody({this.expression, this.statements, this.modifier});

  /// The text after `=>`, without its semicolon.
  final String? expression;

  /// The statements inside `{ }`, without the braces.
  final String? statements;

  /// `async`, `async*`, `sync*`, or null.
  ///
  /// Carried because dropping it changes what the function returns: an
  /// `async` body without the keyword returns the value rather than a Future,
  /// and the generated file stops compiling for a reason that points at the
  /// wrong place.
  final String? modifier;

  bool get isBlock => statements != null;
}

/// Read the body that follows a parameter list ending at [closeParen].
///
/// Returns null when there is no body -- an abstract or external declaration
/// -- which is different from a body this cannot read.
DVFunctionBody? dvFunctionBodyAfter(String source, int closeParen) {
  int at = _skipWhitespaceAndComments(source, closeParen + 1);

  // async, async*, sync* sit between the parameters and the body.
  String? modifier;
  for (final String candidate in <String>['async*', 'sync*', 'async']) {
    if (source.startsWith(candidate, at)) {
      modifier = candidate;
      at = _skipWhitespaceAndComments(source, at + candidate.length);
      break;
    }
  }

  if (at + 1 < source.length && source[at] == '=' && source[at + 1] == '>') {
    final int end = _statementEnd(source, at + 2);
    if (end == -1) return null;
    return DVFunctionBody(
      expression: source.substring(at + 2, end).trim(),
      modifier: modifier,
    );
  }

  if (at < source.length && source[at] == '{') {
    final int end = _matchingBrace(source, at);
    if (end == -1) return null;
    return DVFunctionBody(
      statements: source.substring(at + 1, end),
      modifier: modifier,
    );
  }

  return null;
}

/// What the generated widget's build method should contain.
String dvLoweredBody(DVFunctionBody body) {
  if (body.isBlock) return body.statements!;
  return '  return ${body.expression};';
}

/// The end of a block, counting nesting and ignoring braces that are not
/// braces.
///
/// A closing brace inside a string literal, a comment, or an interpolation is
/// not the end of the block. Scanning for the next `}` truncates the body at
/// the first map literal, and the generated file then fails to parse at a
/// place that has nothing to do with the mistake.
int _matchingBrace(String source, int open) {
  int depth = 0;
  int at = open;
  while (at < source.length) {
    final String c = source[at];

    if (c == '/' && at + 1 < source.length) {
      if (source[at + 1] == '/') {
        final int newline = source.indexOf('\n', at);
        at = newline == -1 ? source.length : newline;
        continue;
      }
      if (source[at + 1] == '*') {
        final int close = source.indexOf('*/', at + 2);
        at = close == -1 ? source.length : close + 2;
        continue;
      }
    }

    if (c == "'" || c == '"') {
      at = _stringEnd(source, at);
      continue;
    }

    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return at;
    }
    at++;
  }
  return -1;
}

/// Past the end of a string literal starting at [start].
///
/// Handles raw strings, triple quotes, escapes, and `${...}` interpolation --
/// which can itself contain braces and strings, so it recurses.
int _stringEnd(String source, int start) {
  final String quote = source[start];
  final bool raw = start > 0 && source[start - 1] == 'r';
  final bool triple = source.startsWith(quote * 3, start);
  final String terminator = triple ? quote * 3 : quote;

  int at = start + terminator.length;
  while (at < source.length) {
    if (!raw && source[at] == r'\') {
      at += 2;
      continue;
    }
    if (!raw && source[at] == r'$' && at + 1 < source.length &&
        source[at + 1] == '{') {
      final int close = _matchingBrace(source, at + 1);
      at = close == -1 ? source.length : close + 1;
      continue;
    }
    if (source.startsWith(terminator, at)) return at + terminator.length;
    at++;
  }
  return source.length;
}

/// The semicolon ending an expression body, ignoring ones inside brackets,
/// strings and comments.
int _statementEnd(String source, int start) {
  int depth = 0;
  int at = start;
  while (at < source.length) {
    final String c = source[at];

    if (c == '/' && at + 1 < source.length) {
      if (source[at + 1] == '/') {
        final int newline = source.indexOf('\n', at);
        at = newline == -1 ? source.length : newline;
        continue;
      }
      if (source[at + 1] == '*') {
        final int close = source.indexOf('*/', at + 2);
        at = close == -1 ? source.length : close + 2;
        continue;
      }
    }

    if (c == "'" || c == '"') {
      at = _stringEnd(source, at);
      continue;
    }

    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (c == ';' && depth <= 0) return at;
    at++;
  }
  return -1;
}

int _skipWhitespaceAndComments(String source, int start) {
  int at = start;
  while (at < source.length) {
    final String c = source[at];
    if (c.trim().isEmpty) {
      at++;
      continue;
    }
    if (c == '/' && at + 1 < source.length && source[at + 1] == '/') {
      final int newline = source.indexOf('\n', at);
      at = newline == -1 ? source.length : newline;
      continue;
    }
    if (c == '/' && at + 1 < source.length && source[at + 1] == '*') {
      final int close = source.indexOf('*/', at + 2);
      at = close == -1 ? source.length : close + 2;
      continue;
    }
    break;
  }
  return at;
}
