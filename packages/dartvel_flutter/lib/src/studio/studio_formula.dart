/// The formula bar's language.
///
/// A spreadsheet puts a cell's value and the expression that makes it in one
/// line anyone can edit. Here the cell is one field of the selected element
/// -- its text, one of its style properties, its layout, or its action --
/// and a formula is a value of that field's kind:
///
///     "Welcome back"          text, quoted or bare
///     12 * 2 + 4              a number, with + - * / and brackets
///     #111827  rgb(17,24,39)  a colour
///     semibold                one of a choice's options
///     TRUE  FALSE             a flag
///     Navigate("/pricing")    an action; None clears it
///
/// A leading `=` is allowed, as in a spreadsheet, and changes nothing.
///
/// Nothing here touches a document: a formula is parsed into the value the
/// field would hold, or refused with the reason and the column, and the bar
/// applies an accepted value through the editor's own setProperty, so the
/// change is one undoable edit, broadcast to collaborators and exported the
/// same way as a change made in the inspector. There is one source of truth.
library;

import 'page_document.dart';

/// One field of an element the formula bar can edit.
class DVFormulaField {
  const DVFormulaField(this.name, this.kind, {this.choices = const <String>[]});

  final String name;

  /// What a value of this field is. [DVFormulaKind.action] is the element's
  /// action rather than a property.
  final DVFormulaKind kind;

  /// The accepted words, for a choice.
  final List<String> choices;
}

enum DVFormulaKind { text, number, colour, choice, flag, action }

/// What a formula may name besides literals: the application's routes, its
/// data models and their fields, and its backend functions.
class DVFormulaVocabulary {
  const DVFormulaVocabulary({
    this.routes = const <String>[],
    this.models = const <String, List<String>>{},
    this.functions = const <String>[],
  });

  final List<String> routes;
  final Map<String, List<String>> models;
  final List<String> functions;
}

/// What a formula means: the value, or why it has none.
class DVFormulaResult {
  const DVFormulaResult.value(this.value)
      : error = null,
        column = null;
  const DVFormulaResult.error(this.error, this.column) : value = null;

  final Object? value;
  final String? error;

  /// Where in the formula the problem is, from zero.
  final int? column;

  bool get ok => error == null;
}

enum DVFormulaTokenKind {
  string,
  number,
  colour,
  function,
  keyword,
  identifier,
  operator,
  punctuation,
  unknown,
}

/// One run of a formula, for highlighting.
class DVFormulaToken {
  const DVFormulaToken(this.kind, this.start, this.end);
  final DVFormulaTokenKind kind;
  final int start;
  final int end;
}

/// A completion the bar offers: what it inserts in place of the word being
/// typed, and what it is.
class DVFormulaSuggestion {
  const DVFormulaSuggestion(this.insert, this.detail);
  final String insert;
  final String detail;
}

const List<String> _functions = <String>['Navigate', 'rgb'];
const List<String> _keywords = <String>['TRUE', 'FALSE', 'None'];

/// The fields of [node], its content first: what a person selecting an
/// element most often came to change.
List<DVFormulaField> dvFormulaFields(DVPageNode node) {
  final List<DVFormulaField> fields = <DVFormulaField>[
    if (node.type == 'text' || node.type == 'button')
      const DVFormulaField('text', DVFormulaKind.text),
    if (node.type == 'image') ...<DVFormulaField>[
      const DVFormulaField('src', DVFormulaKind.text),
      const DVFormulaField('alt', DVFormulaKind.text),
    ],
    if (node.type == 'box')
      for (final DVStudioLayoutProperty p in dvStudioLayoutProperties)
        if (p.appliesTo(node.layout)) _field(p.name, p.kind, p.choices),
    for (final DVStudioProperty p in dvStudioProperties)
      if (p.companionOf == null) _field(p.name, p.kind, p.choices),
    const DVFormulaField('action', DVFormulaKind.action),
  ];
  final Set<String> seen = <String>{};
  return <DVFormulaField>[
    for (final DVFormulaField f in fields)
      if (seen.add(f.name)) f,
  ];
}

DVFormulaField _field(String name, DVStudioPropertyKind kind, List<String> choices) =>
    DVFormulaField(
      name,
      switch (kind) {
        DVStudioPropertyKind.number => DVFormulaKind.number,
        DVStudioPropertyKind.colour => DVFormulaKind.colour,
        DVStudioPropertyKind.choice => DVFormulaKind.choice,
        DVStudioPropertyKind.flag => DVFormulaKind.flag,
        DVStudioPropertyKind.text => DVFormulaKind.text,
      },
      choices: choices,
    );

/// [field] of [node], written as the formula that makes it. Empty when the
/// element does not set it.
String dvFormulaOf(DVPageNode node, DVFormulaField field) {
  if (field.kind == DVFormulaKind.action) {
    final Map<String, Object?>? action = node.action;
    if (action == null) return 'None';
    if (action['type'] == 'navigate') return 'Navigate(${_quote('${action['to']}')})';
    return 'None';
  }
  final Object? value = node.properties[field.name];
  if (value == null) return '';
  return switch (field.kind) {
    DVFormulaKind.text => _quote('$value'),
    DVFormulaKind.number =>
      value is num && value == value.roundToDouble() ? '${value.toInt()}' : '$value',
    DVFormulaKind.flag => value == true ? 'TRUE' : 'FALSE',
    _ => '$value',
  };
}

String _quote(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

/// What [formula] means for [field].
DVFormulaResult dvParseFormula(
    String formula, DVFormulaField field, DVFormulaVocabulary vocabulary) {
  String text = formula;
  int offset = 0;
  final RegExpMatch? eq = RegExp(r'^\s*=').firstMatch(text);
  if (eq != null) {
    offset = eq.end;
    text = text.substring(eq.end);
  }
  final String trimmed = text.trim();
  final int lead = text.length - text.trimLeft().length;
  offset += lead;
  switch (field.kind) {
    case DVFormulaKind.text:
      if (trimmed.startsWith('"')) {
        final (String? s, int end, String? err) = _string(trimmed, 0);
        if (err != null) return DVFormulaResult.error(err, offset + end);
        if (end != trimmed.length) {
          return DVFormulaResult.error(
              'Nothing can follow the closing quote.', offset + end);
        }
        return DVFormulaResult.value(s);
      }
      return DVFormulaResult.value(trimmed);
    case DVFormulaKind.number:
      final _Arithmetic a = _Arithmetic(trimmed);
      final (num? v, String? err, int at) = a.parse();
      if (err != null) return DVFormulaResult.error(err, offset + at);
      return DVFormulaResult.value(v! == v.roundToDouble() ? v.toInt() : v);
    case DVFormulaKind.colour:
      final RegExpMatch? rgb = RegExp(
              r'^rgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$',
              caseSensitive: false)
          .firstMatch(trimmed);
      if (rgb != null) {
        final List<int> c = <int>[
          for (int i = 1; i <= 3; i++) int.parse(rgb.group(i)!),
        ];
        if (c.any((int v) => v > 255)) {
          return DVFormulaResult.error('Each of rgb\'s parts is 0 to 255.', offset);
        }
        return DVFormulaResult.value(
            '#${c.map((int v) => v.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}');
      }
      if (RegExp(r'^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$').hasMatch(trimmed)) {
        return DVFormulaResult.value(trimmed.toUpperCase());
      }
      return DVFormulaResult.error(
          'A colour is #RRGGBB, #AARRGGBB or rgb(r, g, b).', offset);
    case DVFormulaKind.choice:
      if (field.choices.contains(trimmed)) return DVFormulaResult.value(trimmed);
      return DVFormulaResult.error(
          '$trimmed is not one of ${field.choices.join(', ')}.', offset);
    case DVFormulaKind.flag:
      final String upper = trimmed.toUpperCase();
      if (upper == 'TRUE') return const DVFormulaResult.value(true);
      if (upper == 'FALSE') return const DVFormulaResult.value(false);
      return DVFormulaResult.error('A flag is TRUE or FALSE.', offset);
    case DVFormulaKind.action:
      if (trimmed == 'None' || trimmed.isEmpty) {
        return const DVFormulaResult.value(null);
      }
      final RegExpMatch? nav = RegExp(r'^Navigate\s*\(\s*').firstMatch(trimmed);
      if (nav == null) {
        return DVFormulaResult.error(
            'An action is Navigate("/route") or None.', offset);
      }
      final (String? to, int end, String? err) = _string(trimmed, nav.end);
      if (err != null) return DVFormulaResult.error(err, offset + end);
      final String rest = trimmed.substring(end).trim();
      if (rest != ')') {
        return DVFormulaResult.error('Navigate takes one route and a ")".', offset + end);
      }
      if (vocabulary.routes.isNotEmpty && !vocabulary.routes.contains(to)) {
        return DVFormulaResult.error(
            'No page answers at $to. Pages: ${vocabulary.routes.join(', ')}.',
            offset + nav.end);
      }
      return DVFormulaResult.value(<String, Object?>{'type': 'navigate', 'to': to});
  }
}

/// A quoted string starting at [start]: its value, where it ended, or why
/// it did not.
(String?, int, String?) _string(String s, int start) {
  if (start >= s.length || s[start] != '"') {
    return (null, start, 'A string starts with ".');
  }
  final StringBuffer out = StringBuffer();
  int i = start + 1;
  while (i < s.length) {
    final String c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      out.write(s[i + 1]);
      i += 2;
      continue;
    }
    if (c == '"') return (out.toString(), i + 1, null);
    out.write(c);
    i++;
  }
  return (null, s.length, 'The string is not closed with ".');
}

/// + - * / and brackets over numbers, by recursive descent.
class _Arithmetic {
  _Arithmetic(this.s);
  final String s;
  int i = 0;

  (num?, String?, int) parse() {
    try {
      _skip();
      final num v = _sum();
      _skip();
      if (i < s.length) return (null, 'Unexpected "${s[i]}".', i);
      return (v, null, 0);
    } on _Fail catch (f) {
      return (null, f.message, f.at);
    }
  }

  void _skip() {
    while (i < s.length && s[i] == ' ') {
      i++;
    }
  }

  num _sum() {
    num v = _product();
    while (true) {
      _skip();
      if (i < s.length && (s[i] == '+' || s[i] == '-')) {
        final String op = s[i++];
        final num r = _product();
        v = op == '+' ? v + r : v - r;
      } else {
        return v;
      }
    }
  }

  num _product() {
    num v = _factor();
    while (true) {
      _skip();
      if (i < s.length && (s[i] == '*' || s[i] == '/')) {
        final String op = s[i++];
        final int at = i;
        final num r = _factor();
        if (op == '/' && r == 0) throw _Fail('Division by zero.', at);
        v = op == '*' ? v * r : v / r;
      } else {
        return v;
      }
    }
  }

  num _factor() {
    _skip();
    if (i >= s.length) throw _Fail('A number is missing.', i);
    if (s[i] == '-') {
      i++;
      return -_factor();
    }
    if (s[i] == '(') {
      i++;
      final num v = _sum();
      _skip();
      if (i >= s.length || s[i] != ')') throw _Fail('Expected ")".', i);
      i++;
      return v;
    }
    final Match? m = RegExp(r'\d+(\.\d+)?').matchAsPrefix(s, i);
    if (m == null) throw _Fail('Expected a number.', i);
    i = m.end;
    return num.parse(m.group(0)!);
  }
}

class _Fail implements Exception {
  _Fail(this.message, this.at);
  final String message;
  final int at;
}

/// [formula] split into runs, for highlighting.
List<DVFormulaToken> dvFormulaTokens(String formula) {
  final List<DVFormulaToken> out = <DVFormulaToken>[];
  int i = 0;
  while (i < formula.length) {
    final String c = formula[i];
    if (c == ' ') {
      i++;
      continue;
    }
    if (c == '"') {
      final (String? _, int end, String? _) = _string(formula, i);
      out.add(DVFormulaToken(DVFormulaTokenKind.string, i, end));
      i = end;
      continue;
    }
    final Match? colour = RegExp(r'#[0-9A-Fa-f]{3,8}').matchAsPrefix(formula, i);
    if (colour != null) {
      out.add(DVFormulaToken(DVFormulaTokenKind.colour, i, colour.end));
      i = colour.end;
      continue;
    }
    final Match? number = RegExp(r'\d+(\.\d+)?').matchAsPrefix(formula, i);
    if (number != null) {
      out.add(DVFormulaToken(DVFormulaTokenKind.number, i, number.end));
      i = number.end;
      continue;
    }
    final Match? word = RegExp(r'[A-Za-z_][\w.]*').matchAsPrefix(formula, i);
    if (word != null) {
      final String w = word.group(0)!;
      final bool call = formula.substring(word.end).trimLeft().startsWith('(');
      out.add(DVFormulaToken(
        call || _functions.contains(w)
            ? DVFormulaTokenKind.function
            : _keywords.contains(w)
                ? DVFormulaTokenKind.keyword
                : DVFormulaTokenKind.identifier,
        i,
        word.end,
      ));
      i = word.end;
      continue;
    }
    out.add(DVFormulaToken(
      '+-*/='.contains(c)
          ? DVFormulaTokenKind.operator
          : '(),'.contains(c)
              ? DVFormulaTokenKind.punctuation
              : DVFormulaTokenKind.unknown,
      i,
      i + 1,
    ));
    i++;
  }
  return out;
}

/// What the bar offers while [formula] is typed, with the caret at [caret].
List<DVFormulaSuggestion> dvFormulaSuggestions(
  String formula,
  int caret,
  DVFormulaField field,
  DVFormulaVocabulary vocabulary,
) {
  final String before = formula.substring(0, caret.clamp(0, formula.length));
  // Inside Navigate("...: the routes.
  final RegExpMatch? route =
      RegExp(r'Navigate\s*\(\s*"([^"]*)$').firstMatch(before);
  if (route != null) {
    final String typed = route.group(1)!;
    return <DVFormulaSuggestion>[
      for (final String r in vocabulary.routes)
        if (r.startsWith(typed) && r != typed) DVFormulaSuggestion(r, 'page'),
    ];
  }
  // A model's field after Model.
  final RegExpMatch? member = RegExp(r'([A-Z]\w*)\.(\w*)$').firstMatch(before);
  if (member != null) {
    final List<String> fields = vocabulary.models[member.group(1)] ?? const <String>[];
    return <DVFormulaSuggestion>[
      for (final String f in fields)
        if (f.startsWith(member.group(2)!)) DVFormulaSuggestion(f, '${member.group(1)} field'),
    ];
  }
  final String word = RegExp(r'[A-Za-z_]\w*$').firstMatch(before)?.group(0) ?? '';
  final List<DVFormulaSuggestion> out = <DVFormulaSuggestion>[
    if (field.kind == DVFormulaKind.choice)
      for (final String c in field.choices) DVFormulaSuggestion(c, 'option'),
    if (field.kind == DVFormulaKind.flag) ...const <DVFormulaSuggestion>[
      DVFormulaSuggestion('TRUE', 'flag'),
      DVFormulaSuggestion('FALSE', 'flag'),
    ],
    if (field.kind == DVFormulaKind.action) ...const <DVFormulaSuggestion>[
      DVFormulaSuggestion('Navigate', 'action'),
      DVFormulaSuggestion('None', 'no action'),
    ],
    if (field.kind == DVFormulaKind.colour)
      const DVFormulaSuggestion('rgb', 'function'),
    for (final String m in vocabulary.models.keys) DVFormulaSuggestion(m, 'data model'),
    for (final String f in vocabulary.functions) DVFormulaSuggestion(f, 'function'),
  ];
  if (word.isEmpty) return out;
  final String lower = word.toLowerCase();
  return <DVFormulaSuggestion>[
    for (final DVFormulaSuggestion s in out)
      if (s.insert.toLowerCase().startsWith(lower) && s.insert != word) s,
  ];
}
