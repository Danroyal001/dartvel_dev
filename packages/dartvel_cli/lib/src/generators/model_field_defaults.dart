
/// Keep model-local enum declarations in the generated library too. Importing
/// the input would pull its client barrel (and Flutter) into server models.
Iterable<String> dvModelEnumDeclarations(String source) sync* {
  final mask = dvModelCodeMask(source);
  for (final match in RegExp(
    r'\benum\s+[A-Za-z_$][\w$]*\b[^{}]*\{',
  ).allMatches(mask)) {
    final open = match.end - 1;
    yield source.substring(match.start, _close(mask, open, '{', '}') + 1);
  }
}

/// Reads fields from a desugared model, preserving both field initializers
/// and optional initializing-formal defaults. Strings and comments are masked
/// for discovery only; expressions are copied from the original source.
List<Map<String, String>> dvModelFields(String source, String className) {
  final mask = dvModelCodeMask(source);
  final declaration = RegExp('\\bclass\\s+${RegExp.escape(className)}\\b')
      .firstMatch(mask);
  if (declaration == null) return [];
  final open = mask.indexOf('{', declaration.end);
  final close = _close(mask, open, '{', '}');
  final body = source.substring(open + 1, close);
  final bodyMask = mask.substring(open + 1, close);
  final fields = <Map<String, String>>[];
  final fieldPattern = RegExp(
    r'\bfinal\s+([^;={}]+?)\s+([A-Za-z_$][\w$]*)\s*(=|;)',
  );
  // Only class members: a final local in a method is not a model field.
  for (final match in fieldPattern.allMatches(bodyMask)) {
    var depth = 0;
    for (var i = 0; i < match.start; i++) {
      if (bodyMask[i] == '{') depth++;
      if (bodyMask[i] == '}') depth--;
    }
    if (depth != 0) continue;
    final field = <String, String>{
      'type': match.group(1)!.trim(),
      'name': match.group(2)!,
    };
    if (match.group(3) == '=') {
      final end = bodyMask.indexOf(';', match.end);
      if (end >= 0) {
        field['default'] = dvStripComments(body.substring(match.end, end));
      }
    }
    fields.add(field);
  }
  final constructor = RegExp('\\b${RegExp.escape(className)}\\s*\\(')
      .firstMatch(bodyMask);
  if (constructor != null) {
    final argsOpen = bodyMask.indexOf('(', constructor.start);
    final argsClose = _close(bodyMask, argsOpen, '(', ')');
    final args = body.substring(argsOpen + 1, argsClose);
    for (final parameter in dvModelConstructorParameters(args)) {
      final formal = RegExp(r'\bthis\.([A-Za-z_$][\w$]*)\s*=')
          .firstMatch(dvModelCodeMask(parameter));
      if (formal == null) continue;
      for (final field in fields) {
        if (field['name'] == formal.group(1)) {
          field['default'] = dvStripComments(parameter.substring(formal.end));
        }
      }
    }
  }
  return fields;
}

int _close(String mask, int open, String left, String right) {
  var depth = 0;
  for (var i = open; i < mask.length; i++) {
    if (mask[i] == left) depth++;
    if (mask[i] == right && --depth == 0) return i;
  }
  throw StateError('Unclosed model declaration');
}

/// Mask literal contents and comments without changing any source offsets.
String dvModelCodeMask(String source) {
  final out = source.split('');
  void blank(int start, int end) {
    for (var j = start; j < end; j++) {
      if (out[j] != '\n') out[j] = ' ';
    }
  }

  for (var i = 0; i < source.length; i++) {
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      final stop = end < 0 ? source.length : end;
      blank(i, stop);
      i = stop - 1;
    } else if (source.startsWith('/*', i)) {
      var depth = 1;
      var end = i + 2;
      while (end < source.length && depth > 0) {
        if (source.startsWith('/*', end)) {
          depth++;
          end += 2;
        } else if (source.startsWith('*/', end)) {
          depth--;
          end += 2;
        } else {
          end++;
        }
      }
      blank(i, end);
      i = end - 1;
    } else if (source[i] == "'" || source[i] == '"') {
      final raw = i > 0 && source[i - 1] == 'r';
      final quote = source[i];
      final delimiter = source.startsWith(quote * 3, i) ? quote * 3 : quote;
      var end = i + delimiter.length;
      while (end < source.length) {
        if (!raw && source[end] == '\\') {
          end += 2;
          continue;
        }
        if (source.startsWith(delimiter, end)) {
          end += delimiter.length;
          break;
        }
        end++;
      }
      blank(i, end > source.length ? source.length : end);
      i = end - 1;
    }
  }
  return out.join();
}

/// SQL defaults are constants only. Executable expressions remain reader
/// fallbacks; evaluating one during generation would change its meaning.
String? dvModelDefaultSql(Map<String, String> field, {bool encrypted = false}) {
  if (encrypted) return null; // Never put plaintext in an encrypted column.
  final value = field['default']?.trim();
  if (value == null) return null;
  if (value == 'null') return 'NULL';
  if (value == 'true') return '1';
  if (value == 'false') return '0';
  if (RegExp(r'^-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$').hasMatch(value)) {
    return value;
  }
  final decoded = _literalString(value);
  return decoded == null ? null : "'${decoded.replaceAll("'", "''")}'";
}

String? _literalString(String expression) {
  final raw = expression.startsWith('r');
  final text = raw ? expression.substring(1) : expression;
  if (text.length < 2 || (text[0] != "'" && text[0] != '"')) return null;
  final delimiter = text.startsWith(text[0] * 3) ? text[0] * 3 : text[0];
  if (!text.endsWith(delimiter) || text.length < delimiter.length * 2) {
    return null;
  }
  final body = text.substring(delimiter.length, text.length - delimiter.length);
  if (raw) return body;
  final out = StringBuffer();
  const escapes = {
    'n': '\n',
    'r': '\r',
    't': '\t',
    'b': '\b',
    'f': '\f',
    'v': '\v',
  };
  for (var i = 0; i < body.length; i++) {
    final c = body[i];
    if (c == r'$') {
      return null; // Interpolation is an expression, not a literal.
    }
    if (c == '\\') {
      if (++i >= body.length) return null;
      final escape = body[i];
      if (escape == 'x' || escape == 'u') {
        final braces =
            escape == 'u' && i + 1 < body.length && body[i + 1] == '{';
        final start = i + (braces ? 2 : 1);
        final end = braces
            ? body.indexOf('}', start)
            : start + (escape == 'x' ? 2 : 4);
        if (end < start || end > body.length) return null;
        final code = int.tryParse(body.substring(start, end), radix: 16);
        if (code == null || code > 0x10ffff) return null;
        out.writeCharCode(code);
        i = braces ? end : end - 1;
      } else {
        out.write(escapes[escape] ?? escape);
      }
    } else {
      // An unescaped delimiter in the body means multiple expressions.
      if (delimiter.length == 1 && c == delimiter) return null;
      out.write(c);
    }
  }
  return out.toString();
}

/// Splits constructor parameters across positional, named (`{...}`) and
/// optional (`[...]`) sections, ignoring commas inside strings, comments,
/// or nested collections.
List<String> dvModelConstructorParameters(String args) {
  final mask = dvModelCodeMask(args);
  final params = <String>[];
  var start = 0;
  var depth = 0;
  var inNamedOrOptional = false;

  for (var i = 0; i < args.length; i++) {
    final c = mask[i];
    if (c == ' ') continue;

    if (!inNamedOrOptional && depth == 0 && (c == '{' || c == '[')) {
      inNamedOrOptional = true;
      depth = 1;
      start = i + 1;
      continue;
    }
    if (inNamedOrOptional && depth == 1 && (c == '}' || c == ']')) {
      final param = args.substring(start, i).trim();
      if (param.isNotEmpty) params.add(param);
      inNamedOrOptional = false;
      depth = 0;
      start = i + 1;
      continue;
    }
    if (c == '(' || c == '[' || c == '{' || c == '<') {
      depth++;
    } else if (c == ')' ||
        c == ']' ||
        c == '}' ||
        (c == '>' && (i == 0 || mask[i - 1] != '='))) {
      depth--;
    } else if (c == ',') {
      final targetDepth = inNamedOrOptional ? 1 : 0;
      if (depth == targetDepth) {
        final param = args.substring(start, i).trim();
        if (param.isNotEmpty) params.add(param);
        start = i + 1;
      }
    }
  }
  if (start < args.length) {
    final param = args.substring(start).trim();
    if (param.isNotEmpty) params.add(param);
  }
  return params;
}

/// Strips single-line and multi-line comments from an expression while
/// preserving strings and raw string literals.
String dvStripComments(String source) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      if (end < 0) break;
      i = end + 1;
      buffer.write(' ');
      continue;
    }
    if (source.startsWith('/*', i)) {
      var depth = 1;
      var end = i + 2;
      while (end < source.length && depth > 0) {
        if (source.startsWith('/*', end)) {
          depth++;
          end += 2;
        } else if (source.startsWith('*/', end)) {
          depth--;
          end += 2;
        } else {
          end++;
        }
      }
      i = end;
      buffer.write(' ');
      continue;
    }
    final c = source[i];
    final isRaw = (c == 'r' || c == 'R') &&
        i + 1 < source.length &&
        (source[i + 1] == "'" || source[i + 1] == '"') &&
        (i == 0 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(source[i - 1]));
    if (isRaw || c == "'" || c == '"') {
      if (isRaw) {
        buffer.write(source[i]);
        i++;
      }
      final quote = source[i];
      final delimiter =
          source.startsWith(quote * 3, i) ? quote * 3 : quote;
      buffer.write(delimiter);
      var end = i + delimiter.length;
      while (end < source.length) {
        if (!isRaw && source[end] == '\\') {
          buffer.write(source[end]);
          if (end + 1 < source.length) {
            buffer.write(source[end + 1]);
          }
          end += 2;
          continue;
        }
        if (source.startsWith(delimiter, end)) {
          buffer.write(delimiter);
          end += delimiter.length;
          break;
        }
        buffer.write(source[end]);
        end++;
      }
      i = end;
      continue;
    }
    buffer.write(c);
    i++;
  }
  return buffer.toString().trim();
}

