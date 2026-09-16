// The site's copy stays out of the patterns that make it read as filler.
//
// The owner's verdict on the previous copy was that it "still sounds like
// slop", and the patterns behind that verdict are mechanical enough to check:
// em dashes, the two-beat antithesis ("X, not Y", "Not X, but Y", "Less X.
// More Y."), stock openers, button labels with no outcome, and the handful of
// adjectives that say nothing. A rewrite fixes them once. This keeps them
// fixed, because the next paragraph written in a hurry reaches for exactly
// these shapes.
//
// It reads the source rather than rendering pages: every string the site
// shows is a literal in lib/pages or lib/components, and a literal is checked
// whether or not a test happens to scroll to it. Comments are skipped, since
// a comment is not copy.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One string the site can render, and where it starts.
class Literal {
  const Literal(this.file, this.line, this.text);
  final String file;
  final int line;
  final String text;
}

/// A pattern the copy must not contain, and what to call it in a failure.
class Banned {
  const Banned(this.name, this.pattern);
  final String name;
  final RegExp pattern;
}

final List<Banned> banned = <Banned>[
  Banned('em dash', RegExp('\u2014')),
  Banned('en dash used as a dash', RegExp('\\s\u2013\\s')),
  Banned('double hyphen used as a dash', RegExp(r'\s--\s')),
  Banned('"X, not Y"', RegExp(r',\s+not\s')),
  Banned('"Not X, but Y"', RegExp(r'\bnot\b[^.]*,\s*but\b', caseSensitive: false)),
  Banned('"Less X. More Y."', RegExp(r'\bLess\b[^.]*\.\s*More\b')),
  Banned('"it\'s not about"', RegExp(r"\bit(?:'|\u2019)?s not about\b", caseSensitive: false)),
  Banned('"not just"', RegExp(r"\b(?:not|isn't|isn\u2019t) just\b", caseSensitive: false)),
  Banned('"more than just"', RegExp(r'\bmore than just\b', caseSensitive: false)),
  Banned('"not only"', RegExp(r'\bnot only\b', caseSensitive: false)),
  Banned('"rather than"', RegExp(r'\brather than\b', caseSensitive: false)),
  Banned('opener "Welcome to"', RegExp(r'\bWelcome to\b', caseSensitive: false)),
  Banned('opener "In today\'s"', RegExp(r"\bIn today(?:'|\u2019)s\b", caseSensitive: false)),
  Banned('opener "Build faster"', RegExp(r'\bBuild faster\b', caseSensitive: false)),
  Banned('opener "The future of"', RegExp(r'\bThe future of\b', caseSensitive: false)),
  Banned('opener "Everything you need"', RegExp(r'\bEverything you need\b', caseSensitive: false)),
  Banned('CTA "Get started"', RegExp(r'^\s*Get started\s*$', caseSensitive: false)),
  Banned('CTA "Learn more"', RegExp(r'^\s*Learn more\s*$', caseSensitive: false)),
  Banned('filler adjective', RegExp(
    r'\b(?:seamless(?:ly)?|powerful|robust|effortless(?:ly)?|unlock|supercharge|game-changer)\b',
    caseSensitive: false,
  )),
];

/// Every string literal in [source], with adjacent literals joined the way
/// Dart joins them, so a phrase split across two lines is checked whole.
List<Literal> literalsIn(String file, String source) {
  final List<Literal> found = <Literal>[];
  int i = 0;
  int? pendingStart;
  final StringBuffer pending = StringBuffer();

  int lineAt(int offset) => '\n'.allMatches(source.substring(0, offset)).length + 1;

  void flush() {
    if (pendingStart != null) {
      found.add(Literal(file, lineAt(pendingStart!), pending.toString()));
    }
    pendingStart = null;
    pending.clear();
  }

  while (i < source.length) {
    final String c = source[i];
    // Comments are not copy, and a line comment breaks nothing between two
    // adjacent literals.
    if (source.startsWith('//', i)) {
      final int end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end + 1;
      continue;
    }
    if (source.startsWith('/*', i)) {
      final int end = source.indexOf('*/', i + 2);
      i = end < 0 ? source.length : end + 2;
      continue;
    }
    if (c.trim().isEmpty) {
      i++;
      continue;
    }
    final bool raw = c == 'r' &&
        i + 1 < source.length &&
        (source[i + 1] == "'" || source[i + 1] == '"') &&
        (i == 0 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(source[i - 1]));
    final int quoteAt = raw ? i + 1 : i;
    if (quoteAt < source.length &&
        (source[quoteAt] == "'" || source[quoteAt] == '"')) {
      final String q = source[quoteAt];
      final String delimiter =
          source.startsWith('$q$q$q', quoteAt) ? '$q$q$q' : q;
      int j = quoteAt + delimiter.length;
      final StringBuffer text = StringBuffer();
      while (j < source.length && !source.startsWith(delimiter, j)) {
        final String d = source[j];
        if (!raw && d == r'\' && j + 1 < source.length) {
          final String e = source[j + 1];
          if (e == 'u' && j + 2 < source.length && source[j + 2] == '{') {
            final int close = source.indexOf('}', j);
            text.writeCharCode(int.parse(source.substring(j + 3, close), radix: 16));
            j = close + 1;
          } else if (e == 'u') {
            text.writeCharCode(int.parse(source.substring(j + 2, j + 6), radix: 16));
            j += 6;
          } else {
            text.write(e == 'n' ? '\n' : e);
            j += 2;
          }
          continue;
        }
        if (!raw && d == r'$' && j + 1 < source.length && source[j + 1] == '{') {
          // An interpolation is a value, not copy. Skip to its closing brace.
          int depth = 0;
          while (j < source.length) {
            if (source[j] == '{') depth++;
            if (source[j] == '}') {
              depth--;
              if (depth == 0) break;
            }
            j++;
          }
          text.write(' ');
          j++;
          continue;
        }
        text.write(d);
        j++;
      }
      pendingStart ??= i;
      pending.write(text);
      i = j + delimiter.length;
      continue;
    }
    // Anything else ends a run of adjacent literals.
    flush();
    i++;
  }
  flush();
  return found;
}

/// Generated files that quote other text verbatim: compiled code samples and
/// the CLI's own help. Their copy belongs to the samples project and the
/// command table, and rewriting it here would make the docs disagree with
/// what dartvel --help prints. The docs pages around them are scanned.
const List<String> _quoted = <String>[
  'components/docs_samples.dart',
  'components/docs_cli_reference.dart',
];

List<Literal> siteCopy() => <Literal>[
      for (final String dir in <String>['lib/pages', 'lib/components'])
        for (final FileSystemEntity entity
            in Directory(dir).listSync(recursive: true)..sort((a, b) => a.path.compareTo(b.path)))
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              !_quoted.any(entity.path.endsWith))
            ...literalsIn(entity.path, entity.readAsStringSync()),
    ];

void main() {
  test('the scanner joins adjacent literals and skips comments', () {
    final List<Literal> literals = literalsIn('x.dart', '''
// A comment, not copy.
const a = 'Fast, '
    // between the halves
    'not slow.';
const b = "one";
''');
    expect(literals.map((Literal l) => l.text), <String>['Fast, not slow.', 'one']);
  });

  test('every banned pattern is caught on a sample of it', () {
    // A pattern that matches nothing proves nothing, so each is shown firing.
    const Map<String, String> samples = <String, String>{
      'em dash': 'Fast \u2014 and small',
      'en dash used as a dash': 'Fast \u2013 and small',
      'double hyphen used as a dash': 'Fast -- and small',
      '"X, not Y"': 'A compile error, not a 404.',
      '"Not X, but Y"': 'Not a library, but a platform.',
      '"Less X. More Y."': 'Less code. More shipping.',
      '"it\'s not about"': "It's not about speed.",
      '"not just"': 'It is not just a router.',
      '"more than just"': 'More than just a router.',
      '"not only"': 'Not only fast.',
      '"rather than"': 'A compile error rather than a 404.',
      'opener "Welcome to"': 'Welcome to Dartvel',
      'opener "In today\'s"': "In today's world",
      'opener "Build faster"': 'Build faster apps',
      'opener "The future of"': 'The future of Flutter',
      'opener "Everything you need"': 'Everything you need to ship',
      'CTA "Get started"': 'Get started',
      'CTA "Learn more"': 'Learn more',
      'filler adjective': 'A seamless experience',
    };
    expect(samples.keys.toSet(), banned.map((Banned b) => b.name).toSet());
    for (final Banned b in banned) {
      expect(b.pattern.hasMatch(samples[b.name]!), isTrue, reason: b.name);
    }
    // And a plain sentence trips none of them.
    for (final Banned b in banned) {
      expect(b.pattern.hasMatch('Ship the backend in Dart.'), isFalse, reason: b.name);
    }
  });

  test('the site copy uses none of the banned patterns', () {
    final List<Literal> copy = siteCopy();
    expect(copy, isNotEmpty, reason: 'the scan found no strings at all');

    final List<String> hits = <String>[
      for (final Literal literal in copy)
        for (final Banned b in banned)
          if (b.pattern.hasMatch(literal.text))
            '${literal.file}:${literal.line}  ${b.name}  '
                '"${b.pattern.firstMatch(literal.text)!.group(0)}" in '
                '"${literal.text.length > 90 ? '${literal.text.substring(0, 90)}...' : literal.text}"',
    ];
    expect(hits, isEmpty, reason: '\n${hits.join('\n')}\n${hits.length} hit(s)');
  });
}
