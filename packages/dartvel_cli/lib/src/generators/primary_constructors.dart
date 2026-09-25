/// Generation inputs written with primary constructors, read as the class
/// bodies the generator's patterns understand.
///
/// Dart 3.13 declares a class's fields in its header:
///
///     @DVModel()
///     class const _Order({required final String id, final int total = 0});
///
/// The generator reads source text, and every pattern it has -- a model's
/// fields, a sensitive or searchable annotation, a const constructor, a job's
/// payload, a policy's class -- looks for `class _Name {` followed by
/// `final Type name;` and `const _Name(...)`. A model written the new way had
/// none of those, so it generated a public class with no fields, a job with
/// no payload and no policy at all, on a build that succeeded.
///
/// Rather than teach each of a dozen patterns a second grammar, the source is
/// rewritten once, before any of them run, into the equivalent class written
/// the old way:
///
///     class _Order { final String id; final int total;
///       const _Order({required this.id, this.total = 0}); }
///
/// The rewrite is for reading only -- nothing it produces is compiled or
/// copied into generated code -- and it keeps every newline: a field lands
/// on the line its parameter was on, and everything after the class is on
/// the line it was on, so a `file:line` a generator reports still points at
/// the declaration. Classes without a primary constructor, extension types,
/// and anything inside a comment or a string are left exactly as they were.
library;

/// [source] with every primary constructor rewritten as fields and an
/// ordinary constructor.
String dvDesugarPrimaryConstructors(String source) {
  if (!source.contains('class')) return source;
  final List<bool> code = _codeMask(source);
  final StringBuffer out = StringBuffer();
  int copied = 0;
  final RegExp classKeyword = RegExp(r'\bclass\b');
  for (final RegExpMatch m in classKeyword.allMatches(source)) {
    if (m.start < copied || !code[m.start]) continue;
    final _Rewrite? rewrite = _rewriteAt(source, code, m.start);
    if (rewrite == null) continue;
    out
      ..write(source.substring(copied, m.start))
      ..write(rewrite.text);
    copied = rewrite.end;
  }
  if (copied == 0) return source;
  out.write(source.substring(copied));
  return out.toString();
}

class _Rewrite {
  const _Rewrite(this.text, this.end);
  final String text;
  final int end;
}

class _Parameter {
  _Parameter(this.text, this.section);

  /// The parameter as written, without its separating comma.
  final String text;

  /// `''` for a required positional parameter, `'{'` for a named one and
  /// `'['` for an optional positional one.
  final String section;
}

final RegExp _identifier = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

_Rewrite? _rewriteAt(String s, List<bool> code, int at) {
  int i = at + 'class'.length;
  i = _skipSpace(s, i);
  bool isConst = false;
  final Match? constWord = RegExp(r'const\b').matchAsPrefix(s, i);
  if (constWord != null) {
    isConst = true;
    i = _skipSpace(s, constWord.end);
  }
  final Match? name = _identifier.matchAsPrefix(s, i);
  if (name == null) return null;
  final String className = name.group(0)!;
  i = name.end;
  String typeParameters = '';
  final int afterName = _skipSpace(s, i);
  if (afterName < s.length && s[afterName] == '<') {
    final int close = _matching(s, code, afterName, '<', '>');
    if (close < 0) return null;
    typeParameters = s.substring(afterName, close + 1);
    i = close + 1;
  }
  i = _skipSpace(s, i);
  String constructorName = '';
  if (i < s.length && s[i] == '.') {
    final Match? named = _identifier.matchAsPrefix(s, _skipSpace(s, i + 1));
    if (named == null) return null;
    constructorName = '.${named.group(0)}';
    i = _skipSpace(s, named.end);
  }
  if (i >= s.length || s[i] != '(') return null;
  final int open = i;
  final int close = _matching(s, code, open, '(', ')');
  if (close < 0) return null;

  // extends / with / implements, up to the body.
  int j = close + 1;
  while (j < s.length && !(code[j] && (s[j] == '{' || s[j] == ';'))) {
    j++;
  }
  if (j >= s.length) return null;
  final String rest = s.substring(close + 1, j).trim();
  final bool emptyBody = s[j] == ';';
  final int bodyEnd = emptyBody ? j + 1 : _matching(s, code, j, '{', '}') + 1;
  if (bodyEnd <= 0) return null;

  final List<_Parameter> parameters = _parameters(
    s.substring(open + 1, close),
    code.sublist(open + 1, close),
  );
  final StringBuffer header = StringBuffer('class $className$typeParameters');
  if (rest.isNotEmpty) header.write(' $rest');
  header.write(' {');

  final StringBuffer fields = StringBuffer();
  final List<String> positional = <String>[];
  final List<String> optional = <String>[];
  final List<String> named = <String>[];
  for (final _Parameter p in parameters) {
    // Whitespace and comments before the parameter -- its doc comment --
    // stay in front of the field, on the lines they were on.
    final Match lead = _leadingTrivia.matchAsPrefix(p.text)!;
    final String argument = _declare(
      p.text.substring(lead.end).trim(),
      fields,
      lead.group(0)!,
    );
    (p.section == '{'
            ? named
            : p.section == '['
            ? optional
            : positional)
        .add(argument);
  }
  final List<String> list = <String>[
    ...positional,
    if (optional.isNotEmpty) '[${optional.join(', ')}]',
    if (named.isNotEmpty) '{${named.join(', ')}}',
  ];
  final String constructor =
      ' ${isConst ? 'const ' : ''}$className'
              '$constructorName(${list.join(', ')});'
          .replaceAll('\n', ' ');

  final String original = s.substring(at, emptyBody ? bodyEnd : j + 1);
  final String synthesized = '$header$fields$constructor';
  final int missing =
      '\n'.allMatches(original).length - '\n'.allMatches(synthesized).length;
  final String padding = missing > 0 ? '\n' * missing : '';
  final String body = emptyBody ? '}' : s.substring(j + 1, bodyEnd);
  return _Rewrite('$synthesized$padding$body', bodyEnd);
}

/// Writes the field [parameter] declares into [fields], after the newlines
/// that preceded it, and returns the parameter the constructor takes in its
/// place. A parameter that declares nothing -- `super.key`, `this.x`, a plain
/// `int x` -- is returned as written.
String _declare(String parameter, StringBuffer fields, String leading) {
  int i = 0;
  // Annotations, each with its arguments.
  while (i < parameter.length && parameter[i] == '@') {
    final Match? name = RegExp(r'@[A-Za-z_$][\w$.]*')
        .matchAsPrefix(parameter, i);
    if (name == null) break;
    i = _skipSpace(parameter, name.end);
    if (i < parameter.length && parameter[i] == '(') {
      final int close = _matching(parameter, _codeMask(parameter), i, '(', ')');
      if (close < 0) break;
      i = _skipSpace(parameter, close + 1);
    }
  }
  final String annotations = parameter.substring(0, i).trim();
  String rest = parameter.substring(i);

  final Match? modifiers = RegExp(
    r'((?:required|covariant)\s+)*(final|var)\b\s*',
  ).matchAsPrefix(rest);
  if (modifiers == null) return parameter.trim();
  final bool required = RegExp(r'\brequired\b').hasMatch(modifiers.group(0)!);
  final bool isFinal = modifiers.group(2) == 'final';
  rest = rest.substring(modifiers.end);

  String? defaultValue;
  final int equals = _topLevelEquals(rest);
  if (equals >= 0) {
    defaultValue = rest.substring(equals + 1).trim();
    rest = rest.substring(0, equals);
  }
  rest = rest.trimRight();
  final Match? nameMatch = RegExp(r'([A-Za-z_$][A-Za-z0-9_$]*)$')
      .firstMatch(rest);
  if (nameMatch == null) return parameter;
  final String name = nameMatch.group(1)!;
  String type = rest.substring(0, nameMatch.start).trim();
  if (type.isEmpty) type = 'dynamic';

  fields
    ..write(leading.contains('\n') ? leading : ' ')
    ..write(annotations.isEmpty ? '' : '$annotations ')
    ..write(isFinal ? 'final ' : '')
    ..write('$type $name;');
  return '${required ? 'required ' : ''}this.$name'
      '${defaultValue == null ? '' : ' = $defaultValue'}';
}

/// Whitespace, line comments and block comments, doc comments included.
final RegExp _leadingTrivia = RegExp(r'(?:\s|//[^\n]*|/\*[\s\S]*?\*/)*');

/// The index of a default value's `=`, or -1.
int _topLevelEquals(String text) {
  final List<bool> code = _codeMask(text);
  int depth = 0;
  for (int i = 0; i < text.length; i++) {
    if (!code[i]) continue;
    final String c = text[i];
    if ('([{<'.contains(c)) depth++;
    if (')]}'.contains(c) || (c == '>' && (i == 0 || text[i - 1] != '='))) {
      depth--;
    }
    if (c == '=' && depth == 0) {
      final String next = i + 1 < text.length ? text[i + 1] : '';
      final String previous = i > 0 ? text[i - 1] : '';
      if (next != '=' && next != '>' && !'!<>='.contains(previous)) return i;
    }
  }
  return -1;
}

/// The parameter list [text], split at its top-level commas, with the
/// section each parameter belongs to.
List<_Parameter> _parameters(String text, List<bool> code) {
  final List<_Parameter> out = <_Parameter>[];
  String section = '';
  int depth = 0;
  int start = 0;
  void take(int end) {
    final String part = text.substring(start, end);
    if (part.trim().isNotEmpty) out.add(_Parameter(part, section));
  }

  for (int i = 0; i < text.length; i++) {
    if (!code[i]) continue;
    final String c = text[i];
    if (depth == 0 &&
        (c == '{' || c == '[') &&
        text.substring(start, i).trim().isEmpty) {
      section = c;
      start = i + 1;
      continue;
    }
    if (depth == 0 && section.isNotEmpty && (c == '}' || c == ']')) {
      take(i);
      start = i + 1;
      continue;
    }
    if ('([{<'.contains(c)) depth++;
    if (')]}'.contains(c) || (c == '>' && (i == 0 || text[i - 1] != '='))) {
      depth--;
    }
    if (c == ',' && depth == 0) {
      take(i);
      start = i + 1;
    }
  }
  take(text.length);
  return out;
}

int _skipSpace(String s, int i) {
  while (i < s.length && ' \t\r\n'.contains(s[i])) {
    i++;
  }
  return i;
}

/// The index of the [closeChar] that closes the [openChar] at [open], counting
/// only code, or -1.
int _matching(
  String s,
  List<bool> code,
  int open,
  String openChar,
  String closeChar,
) {
  int depth = 0;
  for (int i = open; i < s.length; i++) {
    if (!code[i]) continue;
    if (s[i] == openChar) depth++;
    if (s[i] == closeChar && !(closeChar == '>' && i > 0 && s[i - 1] == '=')) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// For each character of [s], whether it is code rather than part of a
/// comment or a string literal. Interpolated code inside a string counts as
/// string: nothing this file looks for is written inside one.
List<bool> _codeMask(String s) {
  final List<bool> mask = List<bool>.filled(s.length, true);
  int i = 0;
  void blank(int from, int to) {
    for (int k = from; k < to && k < s.length; k++) {
      mask[k] = false;
    }
  }

  while (i < s.length) {
    if (s.startsWith('//', i)) {
      final int end = s.indexOf('\n', i);
      final int stop = end < 0 ? s.length : end;
      blank(i, stop);
      i = stop;
      continue;
    }
    if (s.startsWith('/*', i)) {
      int nest = 0;
      final int from = i;
      while (i < s.length) {
        if (s.startsWith('/*', i)) {
          nest++;
          i += 2;
        } else if (s.startsWith('*/', i)) {
          nest--;
          i += 2;
          if (nest == 0) break;
        } else {
          i++;
        }
      }
      blank(from, i);
      continue;
    }
    final String c = s[i];
    final bool raw =
        (c == 'r' || c == 'R') &&
        i + 1 < s.length &&
        (s[i + 1] == "'" || s[i + 1] == '"') &&
        (i == 0 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(s[i - 1]));
    if (raw || c == "'" || c == '"') {
      final int from = i;
      final int q = raw ? i + 1 : i;
      final String quote = s[q];
      final bool triple = s.startsWith(quote * 3, q);
      final String close = triple ? quote * 3 : quote;
      i = q + close.length;
      while (i < s.length) {
        if (s.startsWith(close, i)) {
          i += close.length;
          break;
        }
        if (!triple && s[i] == '\n') break;
        if (!raw && s[i] == r'\') {
          i += 2;
          continue;
        }
        i++;
      }
      blank(from, i);
      continue;
    }
    i++;
  }
  return mask;
}
