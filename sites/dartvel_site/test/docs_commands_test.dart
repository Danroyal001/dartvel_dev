// Every dartvel command the site shows exists, with the flags shown: the docs
// pages, and the home, features and cloud pages, which sell the same commands.
//
// Checked against dartvelCommandRunner(), the table `dartvel --help` prints,
// so a command renamed or a flag removed fails here before a reader types it.
// Some commands have been renamed on purpose, and the old spelling is listed
// below so it cannot come back.
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dartvel_cli/dartvel_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import 'copy_style_test.dart' show Literal, literalsIn;

/// What a docs page must never say, and why.
const Map<String, String> _retired = <String, String>{
  'dartvel build server': 'the backend executable is part of web-server',
  'dartvel build dev-client': 'a development build is --profile development',
  '--release': 'the mode is --profile release',
};

/// The problems with one command line, or none.
List<String> checkCommand(CommandRunner<void> runner, String line) {
  final List<String> tokens = line
      .split('#')
      .first
      .trim()
      .split(RegExp(r'\s+'))
      // Prose ends a command with punctuation: "dartvel deploy, or ...".
      .map((String t) => t.replaceFirst(RegExp(r'[,.;:)]+$'), ''))
      .where((String t) => t.isNotEmpty)
      .toList();
  if (tokens.length < 2 || tokens.first != 'dartvel') return <String>[];
  final String first = tokens[1];
  if (first.startsWith('-')) {
    return first == '--help' || first == '--version' || first == '-h'
        ? <String>[]
        : <String>['"$line": unknown global flag $first'];
  }
  Command<void>? command = runner.commands[first];
  if (command == null) {
    return <String>['"$line": no command "$first"'];
  }
  final List<String> problems = <String>[];
  int i = 2;
  while (i < tokens.length &&
      !tokens[i].startsWith('-') &&
      command!.subcommands.containsKey(tokens[i])) {
    command = command.subcommands[tokens[i]];
    i++;
  }
  final ArgParser parser = command!.argParser;
  if (command.name == 'build' && i < tokens.length && !tokens[i].startsWith('-')) {
    final List<String> targets = parser.options['platform']!.allowed!;
    // "dartvel build runs the SDK you have" is a sentence about the command,
    // and a word after it with more prose following is not a target anyone
    // types. A lone wrong word, or one followed by flags, still is.
    final bool prose = tokens.skip(i + 1).where((String t) => !t.startsWith('-')).length >= 2;
    if (!targets.contains(tokens[i]) && !prose) {
      problems.add('"$line": build has no target "${tokens[i]}"');
    }
  }
  for (; i < tokens.length; i++) {
    final String token = tokens[i];
    if (!token.startsWith('--')) continue;
    String name = token.substring(2).split('=').first;
    if (parser.options.containsKey(name)) continue;
    if (name.startsWith('no-') &&
        parser.options[name.substring(3)]?.negatable == true) {
      continue;
    }
    problems.add('"$line": ${command.name} has no flag --$name');
  }
  return problems;
}

/// Every command line in [literal]: text starting "dartvel " at the start of
/// a line or after a space, running to the end of that line or of its
/// sentence, so prose naming two commands is read as two.
Iterable<String> commandLines(String literal) sync* {
  for (final String sentence in literal.split(RegExp(r'\n|\.\s'))) {
    for (final Match m in RegExp(r'(?:^|\s)(dartvel [a-z-][^\n]*)').allMatches(sentence)) {
      yield m[1]!;
    }
  }
}

void main() {
  final CommandRunner<void> runner = dartvelCommandRunner();
  final List<Literal> literals = <Literal>[
    for (final FileSystemEntity e
        in Directory('lib/pages').listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart'))
        ...literalsIn(e.path, e.readAsStringSync()),
  ];

  test('the checker catches a wrong command, subcommand, flag and target', () {
    expect(checkCommand(runner, 'dartvel db migrate --plan'), isEmpty);
    expect(checkCommand(runner, 'dartvel build web'), isEmpty);
    expect(checkCommand(runner, 'dartvel dev --no-verbose'), isEmpty);
    expect(checkCommand(runner, 'dartvel deploy --target web  # a comment --x'),
        isEmpty);
    expect(checkCommand(runner, 'dartvel frobnicate'), hasLength(1));
    expect(checkCommand(runner, 'dartvel db migrate --no-such-flag'), hasLength(1));
    expect(checkCommand(runner, 'dartvel build playstation'), hasLength(1));
    expect(checkCommand(runner, 'dartvel build playstation --profile release'),
        hasLength(1));
    expect(checkCommand(runner, 'dartvel build runs code generation for you.'),
        isEmpty);
    expect(
        commandLines('dartvel build web-server writes a file. dartvel deploy '
            '--functions writes the rest.'),
        <String>['dartvel build web-server writes a file',
            'dartvel deploy --functions writes the rest.']);
  });

  test('every command on a site page exists with its flags', () {
    // Prose such as "the dartvel command" names no command, so a word after
    // dartvel counts only when it is a command, or the line is typed at a
    // "\$ " prompt, or (on a docs page) the literal starts with it. The home
    // page's terminal also shows what the CLI prints, such as "dartvel
    // backend listening on", which is output and not a command.
    final List<String> problems = <String>[
      for (final Literal literal in literals)
        for (final String line in commandLines(literal.text))
          if (runner.commands.containsKey(line.split(RegExp(r'\s+'))[1]
                  .replaceAll(RegExp(r'[^a-z-]'), '')) ||
              literal.text.contains('\$ $line') ||
              (literal.file.contains('/docs/') &&
                  literal.text.trimLeft().startsWith(line)))
            for (final String p in checkCommand(runner, line))
              '${literal.file}:${literal.line} $p',
    ];
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('no site page uses a retired spelling', () {
    final List<String> hits = <String>[
      for (final Literal literal in literals)
        for (final MapEntry<String, String> r in _retired.entries)
          if (literal.text.contains(r.key))
            '${literal.file}:${literal.line} "${r.key}": ${r.value}',
    ];
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
