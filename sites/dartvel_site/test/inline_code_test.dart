// A command named in a sentence is set as code.
//
// "Run dartvel db migrate before deploying" in one face reads as a sentence
// with some odd words in it, and a reader new to the CLI cannot tell where
// the command stops. The copy puts every command between backticks and
// Prose draws them as code. This keeps it that way: any CLI invocation in a
// string the site renders must sit inside a pair of backticks, and every
// literal's backticks must pair up, since an unpaired one turns the rest of
// the paragraph into code.
//
// Code blocks are skipped, because a line in a terminal is already code, and
// so is @DVPage: its title and description become the page's <title> and
// meta tags, where a backtick would show as a backtick.
import 'dart:io';

import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'copy_style_test.dart' show Literal, literalsIn;


/// Calls whose string arguments are code or page metadata, not prose.
const List<String> _notProse = <String>[
  'CodeBlock(',
  'DocsShell(',
  // The home page's terminal, drawn span by span.
  'TextSpan(',
  '@DVPage(',
];

/// [source] with the argument lists of [_notProse] calls blanked out, line
/// breaks kept so the line numbers in a failure still point at the file.
String withoutCode(String source) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < source.length) {
    String? call = _notProse.firstWhereOrNull(
        (String name) => source.startsWith(name, i));
    // A Text already set in the code face, such as the title bar of the home
    // page's terminal, is code however it is written.
    if (call == null &&
        source.startsWith('Text(', i) &&
        (i == 0 || !RegExp(r'[\w.]').hasMatch(source[i - 1])) &&
        _argumentsOf(source, i + 4).contains('JetBrainsMono')) {
      call = 'Text(';
    }
    if (call == null) {
      out.write(source[i]);
      i++;
      continue;
    }
    int depth = 0;
    int j = i + call.length - 1;
    String? quote;
    for (; j < source.length; j++) {
      final String c = source[j];
      if (quote != null) {
        if (c == r'\') {
          j++;
        } else if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
      } else if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
        if (depth == 0) break;
      }
    }
    out.write('\n' * '\n'.allMatches(source.substring(i, j)).length);
    i = j + 1;
  }
  return out.toString();
}

/// The argument list of the call whose opening parenthesis is at [open].
String _argumentsOf(String source, int open) {
  int depth = 0;
  for (int j = open; j < source.length; j++) {
    if (source[j] == '(') depth++;
    if (source[j] == ')' && --depth == 0) return source.substring(open, j);
  }
  return source.substring(open);
}

extension<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final T item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}

/// A command someone types: the dartvel CLI with any subcommand, and the
/// handful of other tools the pages tell a reader to run.
final RegExp command = RegExp(
  r'\bdartvel (?:--?[a-z][\w-]*|(?!is\b|and\b|or\b|under\b|block\b|binary\b|'
  r'command\b|app\b|apps\b|project\b|site\b|packages?\b|framework\b)[a-z][\w-]*)'
  r'|\bflutter (?:run|create|build|test|pub|doctor|upgrade)\b'
  r'|\bdart (?:run|pub|format|compile|test|analyze|fix)\b'
  r'|\bnpm (?:install|i|run|publish)\b'
  r'|\bnpx [a-z][\w-]*'
  r'|\bbrew install\b'
  r'|\bfirebase deploy\b'
  r'|\bvercel (?:--prod|deploy)\b',
);

/// Generated files that quote other text verbatim, as in copy_style_test,
/// and the one component whose strings are not copy.
const List<String> _quoted = <String>[
  'components/docs_samples.dart',
  'components/docs_cli_reference.dart',
  // The renderer itself, which names the backtick it splits on.
  'components/prose.dart',
];

List<Literal> prose() => <Literal>[
      for (final String dir in <String>['lib/pages', 'lib/components'])
        for (final FileSystemEntity entity
            in Directory(dir).listSync(recursive: true)
              ..sort((a, b) => a.path.compareTo(b.path)))
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              !entity.path.endsWith('.g.dart') &&
              !_quoted.any(entity.path.endsWith))
            ...literalsIn(entity.path, withoutCode(entity.readAsStringSync())),
    ];

void main() {
  test('code blocks and page metadata are not scanned as prose', () {
    final String kept = withoutCode('''
@DVPage(title: 'Run dartvel dev (now)')
Widget a() => Column(children: [
  DocsText('Run `dartvel dev`.'),
  DocsShell(<String>['dartvel dev', 'echo "(")']),
]);
''');
    expect(kept, isNot(contains('Run dartvel dev (now)')));
    expect(kept, isNot(contains("'dartvel dev'")));
    expect(kept, contains('Run `dartvel dev`.'));
    expect('\n'.allMatches(kept).length, 5);
  });

  test('the pattern finds commands and leaves the product name alone', () {
    bool finds(String text) => command.hasMatch(text);
    expect(finds('Run dartvel db migrate first.'), isTrue);
    expect(finds('Every dartvel --help flag.'), isTrue);
    expect(finds('npm install -g dartvel_dev'), isTrue);
    expect(finds('A dartvel project has one pubspec.'), isFalse);
    expect(finds('The dartvel block in pubspec.yaml'), isFalse);
    expect(finds('Dart is typed.'), isFalse);
  });

  test('every command in the copy is between backticks', () {
    final List<String> bare = <String>[];
    for (final Literal literal in prose()) {
      for (final RegExpMatch match in command.allMatches(literal.text)) {
        final int before =
            '`'.allMatches(literal.text.substring(0, match.start)).length;
        if (before.isEven) {
          bare.add('${literal.file}:${literal.line}: '
              '"${match.group(0)}" in "${literal.text}"');
        }
      }
    }
    expect(bare, isEmpty,
        reason: 'Put each command in backticks so Prose sets it as code:\n'
            '${bare.join('\n')}');
  });

  test('backticks pair up in every string', () {
    final List<String> odd = <String>[
      for (final Literal literal in prose())
        if ('`'.allMatches(literal.text).length.isOdd)
          '${literal.file}:${literal.line}: "${literal.text}"',
    ];
    expect(odd, isEmpty, reason: odd.join('\n'));
  });

  testWidgets('Prose sets a backticked command as code and reads without the '
      'backticks', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Prose(
          'Run `dartvel dev` to pair.',
          DVModifier(),
        ),
      ),
    ));
    final RichText rich = tester.widgetList<RichText>(find.byType(RichText))
        .firstWhere((RichText r) => r.text.toPlainText().contains('pair'));
    expect(rich.text.toPlainText(), 'Run dartvel dev to pair.');
    TextStyle? codeStyle;
    rich.text.visitChildren((InlineSpan span) {
      if (span is TextSpan && span.text == 'dartvel dev') codeStyle = span.style;
      return true;
    });
    expect(codeStyle?.fontFamily, 'JetBrainsMono');
    expect(find.bySemanticsLabel('Run dartvel dev to pair.'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('Prose without backticks is the plain DVText it replaced',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Prose('Nothing to set as code.', DVModifier())),
    ));
    expect(find.byType(DVText), findsOneWidget);
  });
}
