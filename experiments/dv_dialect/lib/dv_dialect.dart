/// The `.dv` dialect: standard Dart with semicolons optional at line ends.
///
/// Track I of `docs/proposals/2026-10-29-dart-flutter-rust-stack.md`. Both
/// directions run the same decision, [_wouldInsert], at every line break, so
/// [toDialect] only removes a semicolon [toDart] would put back. The text a
/// round trip produces is therefore the original, byte for byte, unless
/// insertion wants a semicolon where standard Dart has none -- and that is
/// exactly what running both over a corpus measures.
///
/// Tokens come from the analyzer's own scanner, so what counts as a string, a
/// comment or an operator is standard Dart's decision, not this file's.
library;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/line_info.dart';

/// Standard Dart to the dialect: every statement-ending semicolon that
/// insertion would restore is removed. Throws [FormatException] when
/// [dartSource] does not parse, because only standard Dart has a meaning to
/// preserve.
String toDialect(String dartSource) {
  final parsed = parseString(content: dartSource, throwIfDiagnostics: false);
  if (parsed.errors.isNotEmpty) {
    final error = parsed.errors.first;
    final line = parsed.lineInfo.getLocation(error.offset).lineNumber;
    throw FormatException('not standard Dart, line $line: ${error.message}');
  }

  final removals = <int>[];
  _walk(
    parsed.unit.beginToken,
    parsed.lineInfo,
    onSemicolon: (semicolon, before, after, scan) {
      if (!scan.lineBreakBetween(semicolon, after)) return;
      if (_wouldInsert(before, after, scan)) removals.add(semicolon.offset);
    },
  );

  final out = StringBuffer();
  var from = 0;
  for (final offset in removals) {
    out.write(dartSource.substring(from, offset));
    from = offset + 1;
  }
  out.write(dartSource.substring(from));
  return out.toString();
}

/// A line of the dialect that converts but deserves a second look.
final class DialectWarning {
  const DialectWarning(this.line, this.message);
  final int line;
  final String message;

  @override
  String toString() => 'line $line: $message';
}

final class DialectResult {
  const DialectResult(this.source, this.warnings);
  final String source;
  final List<DialectWarning> warnings;
}

/// The dialect to standard Dart: a semicolon is inserted at every line break
/// [_wouldInsert] accepts.
DialectResult toDart(String dialectSource) {
  final parsed = parseString(content: dialectSource, throwIfDiagnostics: false);
  final insertions = <int>[];
  final warnings = <DialectWarning>[];

  _walk(
    parsed.unit.beginToken,
    parsed.lineInfo,
    onBoundary: (before, after, scan) {
      if (before.type == TokenType.SEMICOLON) return;
      if (!scan.lineBreakBetween(before, after)) return;
      if (!_wouldInsert(before, after, scan)) return;
      insertions.add(before.end);
      if (after.type == TokenType.OPEN_PAREN ||
          after.type == TokenType.OPEN_SQUARE_BRACKET) {
        warnings.add(
          DialectWarning(
            scan.line(after),
            'a line starting with "${after.lexeme}" begins a new statement; '
            'join it to the line above if it continues that one',
          ),
        );
      }
    },
  );

  final out = StringBuffer();
  var from = 0;
  for (final offset in insertions) {
    out
      ..write(dialectSource.substring(from, offset))
      ..write(';');
    from = offset;
  }
  out.write(dialectSource.substring(from));
  return DialectResult(out.toString(), warnings);
}

// ---------------------------------------------------------------------------
// The scan: what each bracket opened, kept on a stack.

enum _Kind {
  /// Statements or declarations: a function or class body, a block.
  statements,

  /// A closure body: statements inside, and its `}` can end a statement.
  closure,

  /// A map or set literal, a switch expression or a pattern: no statements.
  collection,

  /// An enum's value list, until its `;`.
  enumValues,
  paren,

  /// The `(` after `if`, `for`, `while`, `switch` or `catch`.
  header,

  /// The arguments of an annotation.
  annotation,
  bracket,
  interpolation,
}

final class _Frame {
  _Frame(this.kind, this.before);
  _Kind kind;

  /// The token before the opener.
  final Token? before;
}

final class _Scan {
  _Scan(this.lineInfo);

  final LineInfo lineInfo;
  final stack = <_Frame>[];

  /// What a closing token closed, and what stood before its opener.
  final closed = <Token, _Frame>{};

  int line(Token token) => lineInfo.getLocation(token.offset).lineNumber;

  bool lineBreakBetween(Token before, Token after) =>
      after.type == TokenType.EOF ||
      lineInfo.getLocation(after.offset).lineNumber >
          lineInfo.getLocation(before.end).lineNumber;

  bool get insertable =>
      stack.isEmpty ||
      stack.last.kind == _Kind.statements ||
      stack.last.kind == _Kind.closure;
}

typedef _Boundary = void Function(Token before, Token after, _Scan scan);
typedef _Semicolon = void Function(
  Token semicolon,
  Token before,
  Token after,
  _Scan scan,
);

/// Walks the real tokens in order, keeping the bracket stack, and reports
/// every pair of neighbours. Synthetic tokens from parser recovery are
/// skipped: the dialect's missing semicolons make the parser invent some.
void _walk(
  Token first,
  LineInfo lineInfo, {
  _Boundary? onBoundary,
  _Semicolon? onSemicolon,
}) {
  final scan = _Scan(lineInfo);
  Token? previous;
  for (var token = _real(first); ; token = _real(token.next!)) {
    if (previous != null) {
      final next = _real(token.next!);
      if (token.type == TokenType.SEMICOLON && onSemicolon != null) {
        onSemicolon(token, previous, next, scan);
      }
      onBoundary?.call(previous, token, scan);
    }
    if (token.type == TokenType.EOF) break;
    _apply(token, previous, scan);
    previous = token;
  }
}

Token _real(Token token) {
  var current = token;
  while (current.isSynthetic && current.type != TokenType.EOF) {
    current = current.next!;
  }
  return current;
}

void _apply(Token token, Token? before, _Scan scan) {
  switch (token.type) {
    case TokenType.OPEN_PAREN:
      scan.stack.add(_Frame(_parenKind(before), before));
    case TokenType.OPEN_SQUARE_BRACKET:
      scan.stack.add(_Frame(_Kind.bracket, before));
    case TokenType.STRING_INTERPOLATION_EXPRESSION:
      scan.stack.add(_Frame(_Kind.interpolation, before));
    case TokenType.OPEN_CURLY_BRACKET:
      scan.stack.add(_Frame(_braceKind(before, scan), before));
    case TokenType.CLOSE_PAREN ||
        TokenType.CLOSE_SQUARE_BRACKET ||
        TokenType.CLOSE_CURLY_BRACKET:
      if (scan.stack.isNotEmpty) scan.closed[token] = scan.stack.removeLast();
    case TokenType.SEMICOLON:
      if (scan.stack.isNotEmpty && scan.stack.last.kind == _Kind.enumValues) {
        scan.stack.last.kind = _Kind.statements;
      }
    default:
  }
}

_Kind _parenKind(Token? before) {
  if (before == null) return _Kind.paren;
  if (const {'if', 'for', 'while', 'switch', 'catch'}.contains(before.lexeme) &&
      before.isKeyword) {
    return _Kind.header;
  }
  if (_isAnnotationName(before)) return _Kind.annotation;
  return _Kind.paren;
}

/// Tokens after which a `{` opens a map or set literal, and after which a
/// closure or switch is in expression position.
const _expressionPosition = {
  '=',
  '(',
  ',',
  '[',
  ':',
  '=>',
  '?',
  '??',
  '...',
  '...?',
  '&&',
  '||',
  '!',
  '+',
  '-',
  '*',
  '/',
  '~/',
  '%',
  '==',
  '!=',
  '<',
  '<=',
  '>=',
  '|',
  '&',
  '^',
  '+=',
  '-=',
  '*=',
  '/=',
  '??=',
  'return',
  'yield',
  'const',
  'in',
  'case',
  'await',
  'throw',
};

_Kind _braceKind(Token? before, _Scan scan) {
  if (before == null) return _Kind.statements;
  final enclosing = scan.stack.isEmpty ? null : scan.stack.last.kind;
  final lexeme = before.lexeme;

  if (before.type == TokenType.OPEN_CURLY_BRACKET) {
    return enclosing == _Kind.collection ? _Kind.collection : _Kind.statements;
  }
  if (_expressionPosition.contains(lexeme)) return _Kind.collection;

  if (before.type == TokenType.CLOSE_PAREN) return _afterParen(before, scan);
  if (lexeme == 'async' || lexeme == 'sync' || lexeme == '*') {
    var marker = before.previous;
    while (marker != null &&
        (marker.lexeme == '*' ||
            marker.lexeme == 'async' ||
            marker.lexeme == 'sync')) {
      marker = marker.previous;
    }
    if (marker != null && marker.type == TokenType.CLOSE_PAREN) {
      return _afterParen(marker, scan);
    }
    return _Kind.statements;
  }
  if (lexeme == '>' || lexeme == '>>' || lexeme == '>>>') {
    final opener = _matchingAngle(before);
    if (opener == null || !(opener.previous?.isIdentifier ?? false)) {
      return _Kind.collection;
    }
  }
  if (before.isIdentifier || lexeme == '>' || lexeme == '>>') {
    return _declaresEnum(before) ? _Kind.enumValues : _Kind.statements;
  }
  return _Kind.statements;
}

/// A `{` after `)`: a body after a control-flow header or a declaration, or
/// a closure body in expression position.
_Kind _afterParen(Token closeParen, _Scan scan) {
  final frame = scan.closed[closeParen];
  if (frame == null) return _Kind.statements;
  final before = frame.before;
  if (frame.kind == _Kind.header) {
    if (before != null && before.lexeme == 'switch' && _inExpression(before)) {
      return _Kind.collection;
    }
    return _Kind.statements;
  }
  if (before == null ||
      _expressionPosition.contains(before.lexeme) ||
      before.type == TokenType.OPEN_CURLY_BRACKET) {
    return _Kind.closure;
  }
  return _Kind.statements;
}

bool _inExpression(Token keyword) {
  final before = keyword.previous;
  return before != null && _expressionPosition.contains(before.lexeme);
}

/// The `<` matching a closing `>`, `>>` or `>>>`, scanning back.
Token? _matchingAngle(Token close) {
  var depth = 0;
  for (Token? token = close; token != null; token = token.previous) {
    switch (token.lexeme) {
      case '>':
        depth += 1;
      case '>>':
        depth += 2;
      case '>>>':
        depth += 3;
      case '<':
        depth -= 1;
        if (depth == 0) return token;
      case ';' || '{' || '}':
        return null;
    }
    if (token.previous == token) break;
  }
  return null;
}

/// Whether the declaration a `{` belongs to starts with `enum`.
bool _declaresEnum(Token before) {
  for (Token? token = before; token != null; token = token.previous) {
    if (token.type == TokenType.SEMICOLON ||
        token.type == TokenType.OPEN_CURLY_BRACKET ||
        token.type == TokenType.CLOSE_CURLY_BRACKET ||
        token.type == TokenType.EOF) {
      return false;
    }
    if (token.lexeme == 'enum' && token.isKeyword) return true;
    if (token.previous == token) break;
  }
  return false;
}

/// `@name` or `@prefix.name`, read back from its last identifier.
bool _isAnnotationName(Token token) {
  if (!token.isIdentifier) return false;
  Token? current = token.previous;
  while (current != null) {
    if (current.type == TokenType.AT) return true;
    if (current.type == TokenType.PERIOD) {
      current = current.previous;
      if (current == null || !current.isIdentifier) return false;
      current = current.previous;
      continue;
    }
    return false;
  }
  return false;
}

// ---------------------------------------------------------------------------
// The rule.

/// Whether a semicolon belongs at the line break between [before] and
/// [after]: Go's rule, adapted to Dart.
bool _wouldInsert(Token before, Token after, _Scan scan) {
  if (!scan.insertable) return false;
  if (!_canEnd(before, scan)) return false;
  if (after.type == TokenType.EOF) return true;
  return !_continues(before, after);
}

const _literalTypes = {
  'INT',
  'DOUBLE',
  'HEXADECIMAL',
  'INT_WITH_SEPARATORS',
  'DOUBLE_WITH_SEPARATORS',
  'HEXADECIMAL_WITH_SEPARATORS',
  'STRING',
};

const _endingKeywords = {
  'this',
  'super',
  'null',
  'true',
  'false',
  'return',
  'break',
  'continue',
  'rethrow',
};

/// Whether a line ending in [token] can end a statement.
bool _canEnd(Token token, _Scan scan) {
  switch (token.type) {
    case TokenType.CLOSE_PAREN:
      return scan.closed[token]?.kind == _Kind.paren;
    case TokenType.CLOSE_SQUARE_BRACKET || TokenType.INDEX:
      return true;
    case TokenType.CLOSE_CURLY_BRACKET:
      final kind = scan.closed[token]?.kind;
      return kind == _Kind.closure || kind == _Kind.collection;
    case TokenType.PLUS_PLUS || TokenType.MINUS_MINUS || TokenType.BANG:
      return true;
    default:
  }
  if (_literalTypes.contains(token.type.name)) return true;
  if (token.isKeyword && _endingKeywords.contains(token.lexeme)) return true;
  if (token.isIdentifier) return !_isAnnotationName(token);
  return false;
}

/// Tokens that can only continue the expression on the line above.
const _continuations = {
  '.',
  '..',
  '?.',
  '?..',
  '?',
  ':',
  ')',
  ']',
  '=>',
  ',',
  '{',
  '+',
  '-',
  '*',
  '/',
  '~/',
  '%',
  '==',
  '!=',
  '<',
  '>',
  '<=',
  '>=',
  '&&',
  '||',
  '??',
  '&',
  '|',
  '^',
  '<<',
  '>>',
  '>>>',
  '=',
  '+=',
  '-=',
  '*=',
  '/=',
  '~/=',
  '%=',
  '&=',
  '|=',
  '^=',
  '<<=',
  '>>=',
  '>>>=',
  '??=',
  'is',
  'as',
  'extends',
  'with',
  'implements',
  'on',
  'show',
  'hide',
  'when',
};

bool _continues(Token before, Token after) {
  // Adjacent string literals are one string: 'a' 'b'.
  if (before.type == TokenType.STRING && after.type == TokenType.STRING) {
    return true;
  }
  return _continuations.contains(after.lexeme);
}
