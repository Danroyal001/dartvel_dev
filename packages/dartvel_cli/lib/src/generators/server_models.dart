/// The generated data models, for a process with no Flutter in it.
///
/// `models.g.dart` is one library holding each model's data surface --
/// fields, JSON, `save`, `find`, `all`, `search`, `semanticSearch` -- beside
/// its widgets: `Form`, `Table`, `Card`, `Page`, `Admin`. It imports Flutter
/// for the widgets, and a backend is compiled with `dart compile exe`, which
/// has no Flutter. So a backend function could not name `Product.all()`, and
/// the example's catalogue wrote the model's table, key and columns out a
/// second time to read the rows by hand.
///
/// This writes `models_server.g.dart`: the same library with every member
/// and declaration that needs Flutter taken out, and nothing else changed.
/// Derived from the client library rather than generated beside it, so the
/// two cannot disagree about a model's fields, its table or how it saves:
/// there is one generator, and this removes from its output. What is removed
/// is decided by what a declaration's signature names -- a widget, a build
/// context, a signal -- and then by what names anything removed, until
/// nothing that is left refers to something that is gone.
library;

/// Types only a Flutter process has. A declaration whose signature names one
/// is a widget or builds one.
const Set<String> _flutterOnly = <String>{
  'Widget',
  'BuildContext',
  'DVSignal',
  'Color',
  'StatelessWidget',
  'StatefulWidget',
};

/// Names that appear in a statement rather than a signature: the signed-in
/// person on a device. A server has a request's caller instead, and a
/// statement asking for the device's is removed rather than answered with
/// nobody, which would be a weaker check wearing the same code.
const Set<String> _flutterOnlyInBodies = <String>{'DVAuth'};

/// The Flutter-free library, from the client one.
String dvServerModelsSource(String client) {
  final String withoutImports = client
      .split('\n')
      .where((String line) =>
          !line.startsWith("import 'package:flutter/") &&
          !line.startsWith("import 'package:dartvel_flutter/"))
      .join('\n');

  List<_Item> items = _split(withoutImports, 0, withoutImports.length);
  final Set<String> removed = <String>{};

  // Signatures first, then whatever names what was removed, to a fixpoint.
  bool changed = true;
  while (changed) {
    changed = false;
    final List<_Item> kept = <_Item>[];
    for (final _Item item in items) {
      if (_mentionsAny(item.header, _flutterOnly) ||
          _mentionsAny(item.code, removed)) {
        final String? name = item.name;
        if (name != null) removed.add(name);
        changed = true;
        continue;
      }
      kept.add(item);
    }
    items = kept;
    // Inside the classes and extensions that remain.
    for (int i = 0; i < items.length; i++) {
      final _Item item = items[i];
      if (item.body == null) continue;
      final _Item stripped = _stripMembers(item, removed);
      if (stripped.text != item.text) {
        items[i] = stripped;
        changed = true;
      }
    }
  }

  final StringBuffer out = StringBuffer();
  for (final _Item item in items) {
    out.write(item.isFunctionWithBlock ? _stripStatements(item) : item.text);
  }
  return out.toString();
}

/// A declaration and the comments and annotations above it.
class _Item {
  _Item(this.text, this.codeStart, this.header, this.body);

  final String text;

  /// Where the declaration itself starts in [text], past its comments.
  final int codeStart;

  /// The declaration up to its body or initializer, without comments.
  final String header;

  /// The text between the braces of a class, mixin or extension, or null.
  final ({int start, int end})? body;

  String get code => _uncommented(text);

  bool get isFunctionWithBlock =>
      body == null &&
      !header.contains('=') &&
      text.trimRight().endsWith('}') &&
      header.contains('(');

  /// The declared name: the class, extension or function, or the variable.
  String? get name {
    final RegExpMatch? type = RegExp(
            r'\b(?:class|mixin|extension|enum|typedef)\s+(?:const\s+)?([A-Za-z_$][\w$]*)')
        .firstMatch(header);
    if (type != null) return type.group(1);
    final RegExpMatch? member =
        RegExp(r'([A-Za-z_$][\w$]*)\s*(?:<[^>]*>)?\s*(?:\(|=|;|$)')
            .firstMatch(header.trim());
    return member?.group(1);
  }
}

bool _mentionsAny(String code, Set<String> names) {
  if (names.isEmpty) return false;
  for (final RegExpMatch m in RegExp(r'[A-Za-z_$][\w$]*').allMatches(code)) {
    if (names.contains(m.group(0))) return true;
  }
  return false;
}

/// [item] with the members of its body that need Flutter removed.
_Item _stripMembers(_Item item, Set<String> removed) {
  final ({int start, int end}) body = item.body!;
  final List<_Item> members = _split(item.text, body.start, body.end);
  final StringBuffer kept = StringBuffer();
  for (final _Item member in members) {
    if (_mentionsAny(member.header, _flutterOnly) ||
        _mentionsAny(member.code, removed)) {
      continue;
    }
    kept.write(member.text);
  }
  final String text = item.text.substring(0, body.start) +
      kept.toString() +
      item.text.substring(body.end);
  return _Item(text, item.codeStart, item.header,
      (start: body.start, end: body.start + kept.length));
}

/// A top-level function with the statements that need Flutter removed.
String _stripStatements(_Item item) {
  final String text = item.text;
  final int open = _firstAtDepthZero(text, item.codeStart, '{');
  if (open < 0) return text;
  final int close = text.lastIndexOf('}');
  final List<String> statements = <String>[];
  int start = open + 1;
  _scan(text, open + 1, close, (int i, int depth, String c) {
    if (depth == 0 && (c == ';' || c == '}')) {
      // A block statement ends at its brace; a simple one at its semicolon.
      final int end = i + 1;
      if (c == '}' && _nextNonSpace(text, end) == ';') return;
      statements.add(text.substring(start, end));
      start = end;
    }
  });
  final String rest = text.substring(start, close);
  final StringBuffer out = StringBuffer(text.substring(0, open + 1));
  for (final String statement in statements) {
    if (_mentionsAny(_uncommented(statement), _flutterOnlyInBodies)) continue;
    out.write(statement);
  }
  out
    ..write(rest)
    ..write(text.substring(close));
  return out.toString();
}

String? _nextNonSpace(String text, int from) {
  for (int i = from; i < text.length; i++) {
    if (text[i].trim().isNotEmpty) return text[i];
  }
  return null;
}

/// The declarations between [from] and [to], each with the comments before
/// it. Whitespace after the last one is kept as an item with no name.
List<_Item> _split(String source, int from, int to) {
  final List<_Item> items = <_Item>[];
  int start = from;
  int? codeStart;
  int? braceAt;
  bool assigned = false;
  _scan(source, from, to, (int i, int depth, String c) {
    if (depth == 0 && codeStart == null && c.trim().isNotEmpty) {
      codeStart = i;
    }
    if (depth == 0 && c == '=' && braceAt == null) assigned = true;
    if (depth == 1 && c == '{' && braceAt == null) braceAt = i;
    final bool ends = depth == 0 &&
        (c == ';' ||
            (c == '}' && !assigned && _nextNonSpace(source, i + 1) != ';'));
    if (!ends) return;
    final int end = i + 1;
    final String text = source.substring(start, end);
    final int relativeCode = (codeStart ?? start) - start;
    final String header = _uncommented(text.substring(
        relativeCode,
        braceAt != null
            ? braceAt! - start
            : _headerEnd(text, relativeCode)));
    final bool isType = RegExp(r'\b(?:class|mixin|extension)\b').hasMatch(header);
    items.add(_Item(
      text,
      relativeCode,
      header,
      isType && braceAt != null
          ? (start: braceAt! - start + 1, end: text.lastIndexOf('}'))
          : null,
    ));
    start = end;
    codeStart = null;
    braceAt = null;
    assigned = false;
  });
  if (start < to) {
    items.add(_Item(source.substring(start, to), 0, '', null));
  }
  return items;
}

int _headerEnd(String text, int from) {
  final int arrow = text.indexOf('=>', from);
  final int assign = text.indexOf('=', from);
  final List<int> ends = <int>[
    if (arrow >= 0) arrow,
    if (assign >= 0) assign,
    text.length,
  ];
  return ends.reduce((int a, int b) => a < b ? a : b);
}

int _firstAtDepthZero(String text, int from, String char) {
  int found = -1;
  _scan(text, from, text.length, (int i, int depth, String c) {
    if (found < 0 && c == char && depth == 1) found = i;
  });
  return found;
}

/// Calls [visit] for every code character between [from] and [to] -- not
/// inside a string or a comment -- with the bracket depth after it.
void _scan(String s, int from, int to,
    void Function(int index, int depth, String char) visit) {
  int depth = 0;
  int i = from;
  while (i < to) {
    final String c = s[i];
    // Comments.
    if (c == '/' && i + 1 < to && s[i + 1] == '/') {
      final int nl = s.indexOf('\n', i);
      i = nl < 0 ? to : nl;
      continue;
    }
    if (c == '/' && i + 1 < to && s[i + 1] == '*') {
      final int end = s.indexOf('*/', i + 2);
      i = end < 0 ? to : end + 2;
      continue;
    }
    // Strings, raw or not, single or triple quoted. Interpolations with
    // braces are skipped with them, which is safe for generated code: an
    // interpolation never holds an unbalanced quote.
    if (c == "'" || c == '"') {
      final bool raw = i > 0 && s[i - 1] == 'r';
      final bool triple = i + 2 < to && s[i + 1] == c && s[i + 2] == c;
      final String quote = triple ? c * 3 : c;
      int j = i + quote.length;
      while (j < to) {
        if (!raw && s[j] == '\\') {
          j += 2;
          continue;
        }
        if (s.startsWith(quote, j)) break;
        if (!raw && s[j] == r'$' && j + 1 < to && s[j + 1] == '{') {
          int inner = 1;
          j += 2;
          while (j < to && inner > 0) {
            if (s[j] == '{') inner++;
            if (s[j] == '}') inner--;
            j++;
          }
          continue;
        }
        j++;
      }
      i = j + quote.length;
      continue;
    }
    if (c == '{' || c == '(' || c == '[') depth++;
    if (c == '}' || c == ')' || c == ']') depth--;
    visit(i, depth, c);
    i++;
  }
}

String _uncommented(String text) => text
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
    .replaceAll(RegExp(r'//[^\n]*'), ' ');
