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

// The raw scanner. The parser's token stream will not do: on dialect input,
// which is missing its semicolons, error recovery rewrites the stream, and
// the corpus run over packages/ found it dropping real tokens.
// ignore: implementation_imports
import 'package:_fe_analyzer_shared/src/scanner/scanner.dart' as scanner;
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/line_info.dart';

Token _scan(String source) => scanner
    .scanString(
      source,
      configuration: const scanner.ScannerConfiguration(
        enableTripleShift: true,
        enableAugmentations: false,
      ),
    )
    .tokens;

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
    _scan(dartSource),
    LineInfo.fromContent(dartSource),
    onSemicolon: (semicolon, before, after, scan) {
      if (!scan.lineBreakBetween(semicolon, after)) return;
      // Insertion puts a semicolon right after the token it ends, so one
      // with anything in between would come back in another place: a
      // comment, or the line break of a `;` the formatter left alone on the
      // line under a cascade (`..writeln(...)` then `;` in `dartvel_cli`'s
      // `postman_import.dart`).
      if (semicolon.offset != before.end) return;
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
  final insertions = <int>[];
  final warnings = <DialectWarning>[];

  _walk(
    _scan(dialectSource),
    LineInfo.fromContent(dialectSource),
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

  /// The parameters of a function type: `void Function(int a)`.
  functionType,
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

  /// The stack depth of the class body whose constructor's initializer list
  /// is being read, from its `:` to the `{` of the constructor's body (or a
  /// `=>`), or null outside one. Not ended by `;`: the dialect may have
  /// dropped it, and both directions must see the same state.
  int? initializers;

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
      final kind = _braceKind(before, scan);
      if (kind == _Kind.statements && scan.initializers == scan.stack.length) {
        scan.initializers = null;
      }
      scan.stack.add(_Frame(kind, before));
    case TokenType.CLOSE_PAREN ||
        TokenType.CLOSE_SQUARE_BRACKET ||
        TokenType.CLOSE_CURLY_BRACKET:
      if (scan.stack.isNotEmpty) scan.closed[token] = scan.stack.removeLast();
      final depth = scan.initializers;
      if (depth != null && scan.stack.length < depth) scan.initializers = null;
    case TokenType.COLON:
      if (_startsInitializers(token, scan)) {
        scan.initializers = scan.stack.length;
      }
    case TokenType.FUNCTION:
      if (scan.initializers == scan.stack.length) scan.initializers = null;
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
  if (before.lexeme == 'Function') return _Kind.functionType;
  if (_isAnnotationName(before)) return _Kind.annotation;
  // `@Native<Void Function()>(...)`: an annotation with type arguments.
  if (before.lexeme == '>' || before.lexeme == '>>') {
    final opener = _matchingAngle(before);
    final name = opener?.previous;
    if (name != null && _isAnnotationName(name)) return _Kind.annotation;
    // `T Function<T>(int a)`: a generic function type, whose `)` ends a
    // type, not a call. ffigen writes the lookup field that way, wrapped
    // before its name (`dartvel_shelf`'s generated `bindings.dart`).
    if (name != null && name.lexeme == 'Function') return _Kind.functionType;
  }
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
  // `sync* {` and `async* {` open a generator's body. The `*` is not a
  // multiplication, so it must not reach the expression-position check.
  final generatorStar =
      lexeme == '*' &&
      (before.previous?.lexeme == 'sync' || before.previous?.lexeme == 'async');
  // `case 1: {` and `default: {` open a block in a switch statement.
  if (lexeme == ':' && _endsCaseLabel(before)) return _Kind.statements;
  // `outer: {` opens a labeled block.
  if (lexeme == ':' && _endsStatementLabel(before, scan)) {
    return _Kind.statements;
  }
  // `extension on String? {`: a nullable type ending a declaration header.
  if (lexeme == '?' && _inDeclarationHeader(before)) return _Kind.statements;
  if (!generatorStar &&
      !_isPostfixBang(before) &&
      _expressionPosition.contains(lexeme)) {
    return _Kind.collection;
  }

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
  // `operator ==(Object other) {` declares a method; the `==` is its name.
  if (before?.previous?.lexeme == 'operator') return _Kind.statements;
  // `: x = (a + 1) {` and `: y = b ?? (a - 1) {`: the constructor's body.
  // An initializer cannot be an unparenthesized closure, so in an
  // initializer list this `{` is never a closure's.
  if (scan.initializers == scan.stack.length) return _Kind.statements;
  if (before == null ||
      _closurePosition.contains(before.lexeme) ||
      before.type == TokenType.OPEN_CURLY_BRACKET) {
    return _Kind.closure;
  }
  return _Kind.statements;
}

bool _inExpression(Token keyword) {
  final before = keyword.previous;
  if (before == null) return false;
  if (before.lexeme == ':' && _endsCaseLabel(before)) return false;
  if (_isPostfixBang(before)) return false;
  return _expressionPosition.contains(before.lexeme);
}

/// Whether [token] is a postfix `!`, the null check in `x!` or `f()!`,
/// rather than the prefix negation [_expressionPosition] lists. Only the
/// prefix one leaves an operand to come: `: y = x! {` opens a constructor
/// body and `a!` then `switch (b) {` on the next line starts a switch
/// statement (`_fe_analyzer_shared`'s `token.next!` before a `switch`), where
/// reading the `!` as a negation took both braces for literals.
bool _isPostfixBang(Token token) {
  if (token.lexeme != '!') return false;
  final operand = token.previous;
  if (operand == null) return false;
  if (operand.isIdentifier) {
    return operand.lexeme != 'await' && operand.lexeme != 'yield';
  }
  return operand.type == TokenType.CLOSE_PAREN ||
      operand.type == TokenType.CLOSE_SQUARE_BRACKET ||
      (operand.isKeyword && const {'this', 'super'}.contains(operand.lexeme));
}

/// Whether [colon] starts a constructor's initializer list: directly in a
/// class body, after the `)` of a parameter list whose name (`A`, `A.named`,
/// `new`) starts a member. Motivated by `: x = (((o + 1) << 8) | t) {` in
/// `_fe_analyzer_shared`'s `token.dart` and `: e = s ?? (c ? a : b) {` in
/// Flutter's `two_dimensional_viewport.dart`, whose bodies were taken for
/// closures. What stands before the name tells a declaration from a call in
/// a conditional, `c ? f() : g`, or a pattern, `case A():`.
bool _startsInitializers(Token colon, _Scan scan) {
  if (scan.stack.isEmpty || scan.stack.last.kind != _Kind.statements) {
    return false;
  }
  final closeParen = colon.previous;
  if (closeParen == null || closeParen.type != TokenType.CLOSE_PAREN) {
    return false;
  }
  if (scan.closed[closeParen]?.kind != _Kind.paren) return false;
  if (_endsCaseLabel(colon)) return false;
  bool isName(Token? token) =>
      token != null && (token.isIdentifier || token.lexeme == 'new');
  var name = scan.closed[closeParen]!.before;
  if (!isName(name)) return false;
  while (name!.previous?.type == TokenType.PERIOD &&
      isName(name.previous!.previous)) {
    name = name.previous!.previous;
  }
  var start = name.previous;
  if (start != null &&
      start.isKeyword &&
      (start.lexeme == 'const' || start.lexeme == 'external')) {
    start = start.previous;
  }
  return start == null || _endsMember(start);
}

/// Whether [token] can be the last token of a class member, or the `{` that
/// opens the body before the first: what may stand before a constructor's
/// name, with the dialect's semicolons gone.
bool _endsMember(Token token) {
  final type = token.type;
  if (type == TokenType.SEMICOLON ||
      type == TokenType.OPEN_CURLY_BRACKET ||
      type == TokenType.CLOSE_CURLY_BRACKET ||
      type == TokenType.CLOSE_PAREN ||
      type == TokenType.CLOSE_SQUARE_BRACKET ||
      _literalTypes.contains(type.name)) {
    return true;
  }
  return token.isIdentifier &&
      token.lexeme != 'await' &&
      token.lexeme != 'yield';
}

/// Tokens after which `(...) {` is a closure. Narrower than
/// [_expressionPosition]: a closure is never an operand of `*` or `+`, so
/// `x * (a / b) {` is a grouped expression ending before a body.
const _closurePosition = {
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
  'return',
  'yield',
  'await',
  '{',
  '&&',
  '||',
  '??=',
};

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
  // A declaration's type alone on its line, its name on the next.
  if (after.isIdentifier && _isBareTypeLine(before, scan)) return false;
  // The formatter wraps a long returned expression onto the next line, so a
  // bare `return` ends a statement only where the block ends.
  if (before.isKeyword &&
      before.lexeme == 'return' &&
      after.type != TokenType.CLOSE_CURLY_BRACKET) {
    return false;
  }
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
  // A class header wrapped after `extends`, `with` or `implements`.
  if (_headerKeywords.contains(token.lexeme) && token.isKeyword) return false;
  // `show` and `hide` wrapped onto their own line start a name list.
  if ((token.lexeme == 'show' || token.lexeme == 'hide') &&
      _inDirective(token)) {
    return false;
  }
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
  // A `;` alone on the next line already ends the statement: the formatter
  // leaves one there after a trailing comment (`'...' // E0-FF` then `;` in
  // the SDK's `utf.dart`) or under a cascade, and inserting another before
  // it would end the statement twice.
  if (after.type == TokenType.SEMICOLON) return true;
  // Adjacent string literals are one string: 'a' 'b'.
  if (before.type == TokenType.STRING && after.type == TokenType.STRING) {
    return true;
  }
  // A conditional import's `if (dart.library.io) 'b.dart'` continues it.
  if (after.lexeme == 'if' && _inDirective(before)) return true;
  return _continuations.contains(after.lexeme);
}

const _directiveKeywords = {'import', 'export', 'part'};

/// Whether [token] is inside an `import`, `export` or `part` directive,
/// read back to the directive's keyword. In the dialect the
/// directives above have no semicolons either, so the nearest keyword is
/// this directive's own.
bool _inDirective(Token token) {
  for (Token? current = token; current != null; current = current.previous) {
    if (current.type == TokenType.SEMICOLON ||
        current.type == TokenType.OPEN_CURLY_BRACKET ||
        current.type == TokenType.CLOSE_CURLY_BRACKET ||
        current.lexeme == '=') {
      return false;
    }
    if (_startsDirective(current)) return true;
    if (current.previous == current) break;
  }
  return false;
}

/// Whether [token] is the keyword of a directive: `import`, `export` or
/// `part` followed by its URI, or `part of`. The words are built-in
/// identifiers, so a getter or a variable can carry one of these names:
/// `final x = element.library` and then `int? y` and an `if` on the next
/// lines (the analyzer's `driver.dart`) read back to `library` and took the
/// `if` for a conditional import's. A `library` directive never holds the
/// `show`, `hide` or `if` the callers ask about, so it is not counted.
bool _startsDirective(Token token) {
  if (!token.isKeyword || !_directiveKeywords.contains(token.lexeme)) {
    return false;
  }
  final next = token.next;
  if (next == null) return false;
  return next.type == TokenType.STRING ||
      (token.lexeme == 'part' && next.lexeme == 'of');
}

const _headerKeywords = {'extends', 'with', 'implements', 'on'};

/// Whether [colon] ends a `case ...:` or `default:` label, read back over
/// the pattern with its brackets skipped, so `case Point(x: 0, y: 0):` is a
/// label while `{'a': {` and `x ? a : {` are not.
bool _endsCaseLabel(Token colon) {
  var depth = 0;
  for (Token? token = colon.previous; token != null; token = token.previous) {
    final type = token.type;
    if (type == TokenType.CLOSE_PAREN ||
        type == TokenType.CLOSE_SQUARE_BRACKET ||
        type == TokenType.CLOSE_CURLY_BRACKET) {
      depth++;
    } else if (type == TokenType.OPEN_PAREN ||
        type == TokenType.OPEN_SQUARE_BRACKET ||
        type == TokenType.OPEN_CURLY_BRACKET) {
      if (depth == 0) return false;
      depth--;
    } else if (depth == 0) {
      if (token.isKeyword &&
          (token.lexeme == 'case' || token.lexeme == 'default')) {
        return true;
      }
      if (type == TokenType.SEMICOLON ||
          type == TokenType.COMMA ||
          token.lexeme == '?' ||
          token.lexeme == '=>') {
        return false;
      }
    }
    if (token.previous == token || type == TokenType.EOF) break;
  }
  return false;
}

/// Whether [colon] ends a statement label, `outer:`, among statements: an
/// identifier that starts its statement, then the colon. `break outer;`
/// leaves a labeled block, which the SDK's `json.dart` (`checkAscii:`),
/// `uri.dart` and `convert_patch.dart` use; their `{` was taken for a set
/// literal after `:`. The conditional `c ? a : {}` has an operator before
/// `a`, and a named argument or a map entry is not among statements.
bool _endsStatementLabel(Token colon, _Scan scan) {
  if (!scan.insertable) return false;
  final label = colon.previous;
  if (label == null || !label.isIdentifier) return false;
  final before = label.previous;
  if (before == null || before.type == TokenType.EOF) return true;
  if (before.type == TokenType.SEMICOLON ||
      before.type == TokenType.OPEN_CURLY_BRACKET ||
      before.type == TokenType.CLOSE_CURLY_BRACKET) {
    return true;
  }
  return scan.lineBreakBetween(before, label) && _canEnd(before, scan);
}

const _declarationModifiers = {
  'late',
  'final',
  'const',
  'static',
  'external',
  'covariant',
  'abstract',
};

/// Whether the line ending in [last] holds nothing but a declaration's type:
/// modifiers, then one type (`int`, `List<int>?`, `ui.Size`, a record type),
/// and no name. The formatter wraps a long declaration that way, so the name
/// on the next line belongs to it. A type alone on a line is never a useful
/// statement, so the dialect reads `foo` followed by a name on the next line
/// as a declaration.
bool _isBareTypeLine(Token last, _Scan scan) {
  var line = scan.line(last);
  Token? token = last;
  bool onLine(Token? t) =>
      t != null &&
      t.type != TokenType.EOF &&
      t.offset >= 0 &&
      scan.line(t) == line;

  if (token.lexeme == '?') token = token.previous;
  if (token == null) return false;
  var record = false;
  if (token.lexeme == '>' || token.lexeme == '>>') {
    final opener = _matchingAngle(token);
    if (opener == null) return false;
    token = opener.previous;
  } else if (token.type == TokenType.CLOSE_PAREN) {
    // A record type, possibly over several lines; what stands before it on
    // its first line must be modifiers or nothing.
    var depth = 0;
    for (Token? t = token; t != null; t = t.previous) {
      if (t.type == TokenType.CLOSE_PAREN) depth++;
      if (t.type == TokenType.OPEN_PAREN && --depth == 0) {
        token = t.previous;
        line = scan.line(t);
        record = true;
        break;
      }
      if (t.type == TokenType.EOF || t.previous == t) return false;
    }
    if (!record) return false;
  }
  if (!record) {
    if (token == null || !token.isIdentifier) return false;
    token = token.previous;
    while (token != null && token.type == TokenType.PERIOD) {
      token = token.previous;
      if (token == null || !token.isIdentifier) return false;
      token = token.previous;
    }
  }
  while (onLine(token)) {
    if (!token!.isKeyword || !_declarationModifiers.contains(token.lexeme)) {
      return false;
    }
    token = token.previous;
  }
  return true;
}

const _headerStarts = {'extension', 'class', 'mixin', 'enum'};

/// Whether [token] is in the header of an extension, class, mixin or enum
/// declaration, read back to the keyword that starts it.
bool _inDeclarationHeader(Token token) {
  for (Token? current = token; current != null; current = current.previous) {
    final type = current.type;
    if (type == TokenType.SEMICOLON ||
        type == TokenType.OPEN_CURLY_BRACKET ||
        type == TokenType.CLOSE_CURLY_BRACKET ||
        type == TokenType.EOF ||
        current.lexeme == '=') {
      return false;
    }
    if (current.isKeyword && _headerStarts.contains(current.lexeme)) {
      return true;
    }
    if (current.previous == current) break;
  }
  return false;
}
