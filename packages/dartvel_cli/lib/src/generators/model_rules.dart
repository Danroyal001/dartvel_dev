/// The rules a `@DVModel` declares beyond its fields' types: what each
/// value has to meet (`@DVModel.validate`), which fields no two records share
/// (`@DVModel.uniqueField`), the indexes it asks for and who may use its
/// data (`@DVModel(indexes: ..., access: ...)`).
///
/// Read into the model's Studio spec, which is the one description Studio,
/// its data API and a model designed in Studio all check writes against. A
/// model Studio writes out to source is written with these annotations, and
/// reading them back here is what makes it the same model after the build.
library;

import 'annotation_args.dart';

/// The rules of each field in [content], the model's desugared source, by
/// field name. A field with no rule is absent.
Map<String, Map<String, Object?>> dvModelFieldRules(String content) {
  final Map<String, Map<String, Object?>> rules =
      <String, Map<String, Object?>>{};
  void read(String annotation, void Function(String args, Map<String, Object?> into) apply) {
    int from = 0;
    while (true) {
      final int at = content.indexOf('@$annotation', from);
      if (at < 0) break;
      from = at + annotation.length + 1;
      int open = at + annotation.length + 1;
      while (open < content.length && content[open].trim().isEmpty) {
        open++;
      }
      if (open >= content.length || content[open] != '(') continue;
      final int close = _closing(content.substring(open + 1)) + open + 1;
      if (close >= content.length) continue;
      final String args = content.substring(open + 1, close);
      final int end = close + 1;
      final RegExpMatch? field = RegExp(
        r'^\s*(?:@[A-Za-z0-9_.]+\s*(?:\([^)]*\))?\s*)*(?:required\s+)?final\s+(.+?)\s+([A-Za-z0-9_]+)\s*[;,})=]',
        dotAll: true,
      ).firstMatch(content.substring(end));
      if (field == null) continue;
      apply(args, rules.putIfAbsent(field.group(2)!, () => <String, Object?>{}));
    }
  }

  read('DVModel.uniqueField', (String _, Map<String, Object?> into) {
    into['unique'] = true;
  });
  read('DVModel.validate', (String args, Map<String, Object?> into) {
    for (final String part in dvSplitArgs(args)) {
      final int colon = part.indexOf(':');
      if (colon < 0) continue;
      final String name = part.substring(0, colon).trim();
      final String value = part.substring(colon + 1).trim();
      switch (name) {
        case 'min':
        case 'max':
          final num? number = num.tryParse(value);
          if (number != null) into[name] = number;
        case 'minLength':
        case 'maxLength':
          final int? whole = int.tryParse(value);
          if (whole != null) into[name] = whole;
        case 'pattern':
          final String? text = dvDartStringLiteral(value);
          if (text != null) into['pattern'] = text;
      }
    }
  });
  return rules;
}

/// The indexes `@DVModel(indexes: <DVIndex>[...])` declares, from the
/// annotation's arguments.
List<({List<String> fields, bool unique})> dvModelIndexes(String modelArgs) {
  final List<({List<String> fields, bool unique})> indexes =
      <({List<String> fields, bool unique})>[];
  for (final RegExpMatch m in RegExp(
    r'DVIndex\s*\(\s*(?:const\s*)?(?:<String>\s*)?\[([^\]]*)\]\s*(?:,\s*unique\s*:\s*(true|false)\s*)?,?\s*\)',
  ).allMatches(modelArgs)) {
    final List<String> fields = <String>[
      for (final String part in dvSplitArgs(m.group(1)!))
        if (dvDartStringLiteral(part.trim()) case final String name) name,
    ];
    if (fields.isEmpty) continue;
    indexes.add((fields: fields, unique: m.group(2) == 'true'));
  }
  return indexes;
}

/// Who may do what, from `@DVModel(access: DVModelAccess(...))`, by action,
/// or null when the model declares no access.
Map<String, String>? dvModelAccess(String modelArgs) {
  final RegExpMatch? declared =
      RegExp(r'\baccess\s*:\s*(?:const\s+)?DVModelAccess\s*\(').firstMatch(modelArgs);
  if (declared == null) return null;
  final String rest = modelArgs.substring(declared.end);
  final Map<String, String> access = <String, String>{
    'view': 'team',
    'create': 'team',
    'update': 'team',
    'delete': 'team',
  };
  for (final RegExpMatch m in RegExp(
    r'\b(view|create|update|delete)\s*:\s*DVAccess\.(anyone|signedIn|team|nobody)\b',
  ).allMatches(rest.substring(0, _closing(rest)))) {
    access[m.group(1)!] = m.group(2)!;
  }
  return access;
}

/// Where the call whose arguments [rest] starts inside closes, with the
/// parentheses inside string literals not counted.
int _closing(String rest) {
  int depth = 0;
  for (int i = 0; i < rest.length; i++) {
    final String c = rest[i];
    if (c == "'" || c == '"') {
      final bool raw = i > 0 && rest[i - 1] == 'r';
      int j = i + 1;
      while (j < rest.length && rest[j] != c) {
        if (!raw && rest[j] == r'\') j++;
        j++;
      }
      i = j;
      continue;
    }
    if (c == '(') depth++;
    if (c == ')') {
      if (depth == 0) return i;
      depth--;
    }
  }
  return rest.length;
}

/// The value of the Dart string literal [source]: single or double quoted,
/// raw or not. Null for anything else.
String? dvDartStringLiteral(String source) {
  String text = source.trim();
  bool raw = false;
  if (text.startsWith('r')) {
    raw = true;
    text = text.substring(1);
  }
  if (text.length < 2) return null;
  final String quote = text[0];
  if ((quote != "'" && quote != '"') || !text.endsWith(quote)) return null;
  final String body = text.substring(1, text.length - 1);
  if (raw) return body;
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < body.length; i++) {
    final String c = body[i];
    if (c != r'\' || i == body.length - 1) {
      out.write(c);
      continue;
    }
    final String next = body[++i];
    out.write(switch (next) {
      'n' => '\n',
      't' => '\t',
      'r' => '\r',
      _ => next,
    });
  }
  return out.toString();
}

/// [rules] as the named arguments of a `DVStudioFieldSpec`, each preceded by
/// a comma.
String dvStudioFieldRulesSource(Map<String, Object?>? rules) {
  if (rules == null || rules.isEmpty) return '';
  String quote(String value) =>
      "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\n', r'\n')}'";
  return <String>[
    if (rules['unique'] == true) ', unique: true',
    for (final String key in const <String>['min', 'max', 'minLength', 'maxLength'])
      if (rules[key] != null) ', $key: ${rules[key]}',
    if (rules['pattern'] case final String pattern) ', pattern: ${quote(pattern)}',
  ].join();
}
