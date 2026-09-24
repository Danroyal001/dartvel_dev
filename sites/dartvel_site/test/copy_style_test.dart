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
  // A hyphen is for a compound word. Swapping an em dash for one is the
  // first mistake people make when they set out to de-slop a paragraph, and
  // it is the same punctuation error wearing a shorter mark: what the
  // sentence usually wanted was a comma, a semicolon or a full stop.
  // A word, a space, a hyphen, a space, a word. Narrower than a bare " - "
  // because the docs pages quote YAML list items and a line of Dart
  // operators, and neither is a sentence.
  Banned('hyphen used as a dash', RegExp(r'\w\s-\s\w')),
  // The reveal opener. It promises the next clause is worth waiting for,
  // which is a promise a sentence should keep by being the point.
  Banned('reveal opener', RegExp(
    r"\b(?:here(?:'|\u2019)?s the (?:kicker|thing|best part)|the best part|but wait)\b",
    caseSensitive: false,
  )),
  Banned('"at the end of the day"', RegExp(r'\bat the end of the day\b', caseSensitive: false)),
  Banned('"delve"', RegExp(r'\bdelv(?:e|es|ing)\b', caseSensitive: false)),
  Banned('"tapestry"', RegExp(r'\btapestr(?:y|ies)\b', caseSensitive: false)),
  Banned('"in the world of"', RegExp(r'\bin the world of\b', caseSensitive: false)),
  Banned('"elevate"', RegExp(r'\belevat(?:e|es|ing)\b', caseSensitive: false)),
  Banned('"next-gen"', RegExp(r'\bnext[- ]gen(?:eration)?\b', caseSensitive: false)),
  Banned('"leverage" as a verb', RegExp(r'\bleverag(?:e|es|ing)\b', caseSensitive: false)),
  // A rounded invented figure. Real numbers are lumpy, and a claim on this
  // site has to be checkable in docs/spec-status.json or
  // docs/build-targets.md, which no invented number ever is.
  Banned('invented round figure', RegExp(r'\b(?:99\.9|99|100|50|10)%')),
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
  structureTests();

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
      'hyphen used as a dash': 'Fast - and small',
      'reveal opener': "Here's the kicker",
      '"at the end of the day"': 'At the end of the day it ships',
      '"delve"': 'Delve into the router',
      '"tapestry"': 'A rich tapestry of tools',
      '"in the world of"': 'In the world of Flutter',
      '"elevate"': 'Elevate your workflow',
      '"next-gen"': 'A next-gen framework',
      '"leverage" as a verb': 'Leverage the generated client',
      'invented round figure': '99.9% uptime',
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

// The owner's copy rules that are structure, not wording: one to three
// bullets in a section, one list of them per section, and the reader's
// objection answered before a button asks for the click. They apply to the
// pages that sell (the home, features and cloud pages); a docs page is a
// reference and is held to the wording rules above only.

/// The marketing pages: every page file directly under lib/pages.
List<File> marketingPages() => <File>[
      for (final FileSystemEntity e in Directory('lib/pages').listSync()
        ..sort((a, b) => a.path.compareTo(b.path)))
        if (e is File &&
            e.path.endsWith('.dart') &&
            !e.path.split('/').last.startsWith('_') &&
            !e.path.contains('.error.') &&
            !e.path.contains('.loading.'))
          e,
    ];

/// The offset just past the bracket that closes the one at [open], skipping
/// strings and comments so a bracket in copy does not count.
int closingBracket(String source, int open) {
  final String opener = source[open];
  final String closer = opener == '[' ? ']' : ')';
  int depth = 0;
  int i = open;
  while (i < source.length) {
    final String c = source[i];
    if (source.startsWith('//', i)) {
      i = source.indexOf('\n', i);
      if (i < 0) return source.length;
      continue;
    }
    if (c == "'" || c == '"') {
      int j = i + 1;
      while (j < source.length && source[j] != c) {
        if (source[j] == r'\') j++;
        j++;
      }
      i = j + 1;
      continue;
    }
    if (c == opener) depth++;
    if (c == closer) {
      depth--;
      if (depth == 0) return i + 1;
    }
    i++;
  }
  return source.length;
}

/// How many items each `Bullets([...])` in [source] holds, with the line it
/// starts on.
List<(int line, int items)> bulletLists(String source) => <(int, int)>[
      for (final Match m in RegExp(r'\bBullets\(').allMatches(source))
        () {
          final int listOpen = source.indexOf('[', m.end);
          final int listClose = closingBracket(source, listOpen);
          final int items = literalsIn('', source.substring(listOpen, listClose)).length;
          return ('\n'.allMatches(source.substring(0, m.start)).length + 1, items);
        }(),
    ];

/// [source] cut into sections: each piece starts at a `Section(` or at a
/// `@DVFunctionalWidget()`, which on these pages is one section's function.
List<String> sectionsOf(String source) {
  final List<int> starts = <int>[
    0,
    for (final Match m
        in RegExp(r'\bSection\(|@DVFunctionalWidget\(\)').allMatches(source))
      m.start,
    source.length,
  ];
  return <String>[
    for (int i = 0; i + 1 < starts.length; i++)
      source.substring(starts[i], starts[i + 1]),
  ];
}

/// Problems with the structure of one page's [source].
List<String> structureProblems(String file, String source) => <String>[
      for (final (int line, int items) list in bulletLists(source))
        if (list.$2 < 1 || list.$2 > 3)
          '$file:${list.$1}  ${list.$2} bullets; a section takes one to three',
      for (final String section in sectionsOf(source))
        if (RegExp(r'\bBullets\(').allMatches(section).length > 1)
          '$file  a section has '
              '${RegExp(r'\bBullets\(').allMatches(section).length} bullet '
              'lists; one idea per section is one list',
      for (final String section in sectionsOf(source))
        for (final Match cta in RegExp(r'\bPrimaryLink\(').allMatches(section))
          if (!section.substring(0, cta.start).contains('Objection('))
            '$file  a PrimaryLink with no Objection before it in its section: '
                '${section.substring(cta.start, (cta.start + 60).clamp(0, section.length))}',
    ];

void structureTests() {
  test('the structure checks fire on a sample of each fault', () {
    expect(structureProblems('x', '''
Section(children: <Widget>[
  Bullets(<String>['one', 'two', 'three', 'four']),
])'''), hasLength(1));
    expect(structureProblems('x', '''
Section(children: <Widget>[
  Bullets(<String>['one']),
  Bullets(<String>['two']),
])'''), hasLength(1));
    expect(structureProblems('x', '''
Section(children: <Widget>[
  PrimaryLink('Create your first app', '/docs'),
  Objection('Too late?', 'Yes.'),
])'''), hasLength(1));
    // A list whose items are split across lines and carry brackets in the
    // copy is still three items, and an objection first is fine.
    expect(structureProblems('x', '''
Section(children: <Widget>[
  Bullets(onDark: true, <String>[
    'Post.Form(...) [validates] '
        'input.',
    'two',
    'three',
  ]),
  Objection('Worried?', 'No need.'),
  PrimaryLink('Create your first app', '/docs'),
])'''), isEmpty);
  });

  test('marketing pages keep one to three bullets, one list a section, '
      'and an objection before each primary button', () {
    final List<File> pages = marketingPages();
    expect(pages.map((File f) => f.path.split('/').last),
        containsAll(<String>['index.dart', 'features.dart', 'cloud.dart']));
    final List<String> problems = <String>[
      for (final File page in pages)
        ...structureProblems(page.path, page.readAsStringSync()),
    ];
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
