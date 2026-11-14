// The Rust syntax helper against the Dart analyzer, file by file.
//
// Needs the helper built (`cargo build --release` in rust/, or
// DARTVEL_SYNTAX_HELPER naming one). Without it these tests are skipped,
// loudly; the Rust workflow sets DARTVEL_REQUIRE_SYNTAX_HELPER so that a
// missing helper fails there instead.
//
// The corpus is this repository's own Dart (packages, sites, examples,
// apps, tools, tests) and any roots named in DARTVEL_SYNTAX_CORPUS
// (separated by `:`), an application for one.
@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:dartvel_cli/src/analysis/syntax_check.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String _repository = p.normalize(p.join(Directory.current.path, '..', '..'));

String? _helperPath() {
  final String named = Platform.environment['DARTVEL_SYNTAX_HELPER'] ??
      p.join(_repository, 'rust', 'target', 'release', Platform.isWindows ? 'dartvel_syntax.exe' : 'dartvel_syntax');
  return File(named).existsSync() ? named : null;
}

const Set<String> _skippedDirectories = <String>{'.dart_tool', '.git', 'build', 'node_modules', 'target', '.pub-cache'};

List<String> _dartFilesUnder(String root) {
  final List<String> files = <String>[];
  void walk(Directory directory) {
    final List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final FileSystemEntity entry in entries) {
      final String name = p.basename(entry.path);
      if (entry is Directory) {
        if (!_skippedDirectories.contains(name)) walk(entry);
      } else if (entry is File && name.endsWith('.dart')) {
        files.add(entry.path);
      }
    }
  }

  final Directory directory = Directory(root);
  if (directory.existsSync()) walk(directory);
  return files..sort();
}

List<String> _corpus() => <String>[
      for (final String part in <String>['packages', 'sites', 'examples', 'apps', 'tool', 'test'])
        ..._dartFilesUnder(p.join(_repository, part)),
      for (final String root in (Platform.environment['DARTVEL_SYNTAX_CORPUS'] ?? '').split(':'))
        if (root.isNotEmpty) ..._dartFilesUnder(root),
    ];

/// What one engine says about one file: `clean`, `deferred <reason>`,
/// `threw`, or its diagnostics one a line.
typedef _Answers = Map<String, String>;

String _describe(String name, int offset, int length, String message) => '$name@$offset+$length "$message"';

String _unescape(String field) => field.replaceAllMapped(
      RegExp(r'\\(.)'),
      (Match match) => switch (match[1]) { 't' => '\t', 'n' => '\n', 'r' => '\r', _ => match[1]! },
    );

/// Runs the helper with `--diagnostics` over [paths], in batches, starting
/// it again after a file it dies on (answered `died`).
Future<_Answers> _rustAnswers(String helper, List<String> paths) async {
  final _Answers answers = <String, String>{};
  int next = 0;
  while (next < paths.length) {
    final List<String> batch = paths.sublist(next);
    final Process process = await Process.start(helper, const <String>['--diagnostics']);
    // Read while writing: the helper answers as it reads, and waiting for
    // the input to be taken before reading would leave it blocked on a full
    // output pipe.
    final Future<List<String>> reading =
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()).toList();
    final Future<void> draining = process.stderr.drain<void>();
    process.stdin.write(batch.map((String path) => '$path\n').join());
    await process.stdin.close().catchError((Object _) {});
    final List<String> lines = await reading;
    await draining;
    final int exitCode = await process.exitCode;
    expect(lines.first, DVSyntaxHelper.greeting);
    int answered = 0;
    for (final String line in lines.skip(1)) {
      final List<String> fields = line.split('\t');
      final String path = batch[int.parse(fields[1])];
      switch (fields.first) {
        case 'clean':
          answers[path] = 'clean';
          answered++;
        case 'deferred':
          answers[path] = 'deferred ${fields[2]}';
          answered++;
        case 'flagged':
          answers[path] = '';
          answered++;
        case 'diagnostic':
          answers[path] = '${answers[path]}'
              '${_describe(fields[2], int.parse(fields[3]), int.parse(fields[4]), _unescape(fields[5]))}\n';
        default:
          fail('unexpected line from the helper: $line');
      }
    }
    if (exitCode == 0) {
      expect(answered, batch.length);
      break;
    }
    answers[batch[answered]] = 'died';
    next += answered + 1;
  }
  return answers;
}

String _dartAnswer(List<int> bytes) {
  try {
    final List<Diagnostic> diagnostics =
        parseString(content: utf8.decode(bytes, allowMalformed: true), throwIfDiagnostics: false).errors;
    if (diagnostics.isEmpty) return 'clean';
    return diagnostics
        .map((Diagnostic diagnostic) => '${_describe(
              diagnostic.diagnosticCode.lowerCaseUniqueName,
              diagnostic.offset,
              diagnostic.length,
              diagnostic.message,
            )}\n')
        .join();
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return 'threw';
  }
}

/// Compares the engines over [paths] and returns the tally, having failed
/// on any file where the helper's word would have misled.
Future<Map<String, int>> _compare(String helper, List<String> paths, {required String label}) async {
  final _Answers rust = await _rustAnswers(helper, paths);
  final Map<String, int> tally = <String, int>{};
  final List<String> rustCleanDartNot = <String>[];
  final List<String> differentDiagnostics = <String>[];
  final List<String> flaggedDartThrew = <String>[];
  for (final String path in paths) {
    final String rustAnswer = rust[path]!;
    final String dartAnswer = _dartAnswer(File(path).readAsBytesSync());
    final String kind = rustAnswer == 'clean'
        ? 'clean'
        : rustAnswer == 'died' || rustAnswer.startsWith('deferred')
            ? rustAnswer
            : 'flagged';
    tally[kind] = (tally[kind] ?? 0) + 1;
    if (kind == 'clean' && dartAnswer != 'clean') {
      rustCleanDartNot.add('$path\n  dart: $dartAnswer');
    } else if (kind == 'flagged' && dartAnswer == 'threw') {
      // The analyzer has no answer to compare with. The CLI parses such a
      // file in Dart all the same and reports that it could not be checked,
      // exactly as without the helper.
      flaggedDartThrew.add(path);
    } else if (kind == 'flagged' && rustAnswer != dartAnswer) {
      differentDiagnostics.add('$path\n  rust: $rustAnswer  dart: $dartAnswer');
    }
  }
  // ignore: avoid_print
  print('$label: ${paths.length} files; helper answered $tally; '
      '${rustCleanDartNot.length} clean in Rust but not in Dart; '
      '${differentDiagnostics.length} flagged with different diagnostics; '
      '${flaggedDartThrew.length} flagged where package:analyzer threw');
  expect(rustCleanDartNot, isEmpty,
      reason: 'a file the helper calls clean is not parsed again, so this is a missed error');
  expect(differentDiagnostics, isEmpty,
      reason: 'the port is meant to report exactly what package:analyzer reports');
  return tally;
}

const List<String> _malformed = <String>[
  'class', 'class {', 'class A extends {', 'void main( {', 'void main() { return', "'unterminated",
  r'"unterminated ${', "'''unterminated", "r'raw", '/* unterminated comment', '/** /* nested */',
  r'var x = ${};', r"var x = '${'${'${", '}}}}}}}}', ')))))))', ']]]]]]]', '>>>>>>>>>>>', '<<<<<<<<<<<',
  '@', '@@@@@@', '#', '#!', 'import', "import 'a' as;", "import 'a' show hide deferred as;", 'library;;;;',
  'part of;', 'enum {', 'enum E { a, b, ; ; }', 'extension on {', 'extension type (', 'mixin on on on {}',
  'typedef = ;', 'switch', 'void f() { switch (x) { case } }', 'void f() { for (;;;;) }',
  'void f() { if else }', 'void f() { try } catch', 'void f() => => =>;', 'var x = (,);',
  'var x = (a: , b: );', 'var x = [...];', 'var x = {...?};', 'var x = a ? : ;', 'var x = a ?? ?? b;',
  'var x = 0x;', 'var x = 1e;', 'var x = 1.;', 'var x = 1__0;', r"var x = '\u{110000}';", r"var x = '\x';",
  'var \u0000x = 1;', '\u0000\u0000\u0000', 'void main() {}\u001a', 'var \u{1F600} = 1;',
  '// @dart=2.9\nint? x;', '// @dart=99.99\nvoid main() {}', '// @dart=\nvoid main() {}',
  'external abstract static const final late var covariant required x;', 'augment augment class A {}',
  'macro class A {}', 'class A { A.() ; factory = ; operator ; get ; set ; }',
  'class A { int operator [](int i, int j) => 0; operator []=() {} }', 'f<><><>() {}',
  'List<List<List<List<', 'void Function(void Function(void Function(', 'x!!!!!!!!!!.y?..z?.[w]',
  'await await await', 'yield* yield* yield', 'new new new A()', 'const const const A()',
  'throw throw throw', 'is is is as as as', 'a = b = c = = d;', 'a..b..c....d', 'this.super.this.super',
  'super', 'null', '\n\n\n\r\r\r\n\t\t', '',
];

const List<String> _spliced = <String>[
  '(', ')', '{', '}', '[', ']', '<', '>', "'", '"', "'''", r'${', r'$', r'\', '/*', '*/', '//', ';', ',',
  '.', '..', '...', '?', '??', '?.', '!', '=>', '=', '==', '>>', '>>>', '@', '#', 'class ', 'extension type ',
  'enum ', 'mixin ', 'switch ', 'case ', 'when ', 'await ', 'async ', 'yield ', 'late ', 'final ', 'const ',
  'required ', 'covariant ', 'augment ', 'import ', 'part of ', '0x', '1e', "r'", '\u0000', '\n', '\r',
  ' ', '\u{1F600}',
];

List<int> _mutate(List<int> source, Random random) {
  final List<int> bytes = List<int>.of(source);
  for (int edits = random.nextInt(4); edits >= 0 && bytes.isNotEmpty; edits--) {
    final int position = random.nextInt(bytes.length);
    final int end = min(position + 1 + random.nextInt(40), bytes.length);
    switch (random.nextInt(6)) {
      case 0:
        bytes.length = position;
      case 1:
        bytes.removeAt(position);
      case 2:
        bytes[position] = random.nextInt(256);
      case 3:
        bytes.insertAll(position, utf8.encode(_spliced[random.nextInt(_spliced.length)]));
      case 4:
        bytes.removeRange(position, end);
      default:
        bytes.insertAll(position, bytes.sublist(position, end));
    }
  }
  return bytes;
}

void main() {
  final String? helper = _helperPath();
  if (helper == null) {
    test('the Rust helper against the Dart analyzer', () {
      if (Platform.environment.containsKey('DARTVEL_REQUIRE_SYNTAX_HELPER')) {
        fail('no helper at rust/target/release/dartvel_syntax: build it with `cargo build --release` in rust/');
      }
      markTestSkipped('NOT RUN: no helper at rust/target/release/dartvel_syntax '
          '(build it with `cargo build --release` in rust/)');
    });
    return;
  }

  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('dv_syntax_differential_'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test('every Dart file of the corpus gets the analyzer\'s answer', () async {
    final List<String> corpus = _corpus();
    expect(corpus.length, greaterThan(1000), reason: 'the repository alone has more Dart files than this');
    final Map<String, int> tally = await _compare(helper, corpus, label: 'corpus');
    expect(tally['clean'] ?? 0, greaterThan(corpus.length * 9 ~/ 10),
        reason: 'the corpus is working code: the helper should vouch for nearly all of it');
    expect(tally['died'], isNull);
  });

  test('malformed sources get the analyzer\'s answer', () async {
    final List<String> paths = <String>[];
    for (int index = 0; index < _malformed.length; index++) {
      final File file = File(p.join(scratch.path, 'malformed_$index.dart'))..writeAsStringSync(_malformed[index]);
      paths.add(file.path);
    }
    final Map<String, int> tally = await _compare(helper, paths, label: 'malformed');
    expect(tally['died'], isNull);
  });

  test('seeded mutations of corpus files get the analyzer\'s answer', () async {
    final Random random = Random(20261114);
    final List<String> corpus = _corpus();
    final List<String> paths = <String>[];
    for (int index = 0; index < 3000; index++) {
      final List<int> original = File(corpus[random.nextInt(corpus.length)]).readAsBytesSync();
      if (original.length > 60000) continue;
      final File file = File(p.join(scratch.path, 'mutated_$index.dart'))
        ..writeAsBytesSync(_mutate(original, random));
      paths.add(file.path);
    }
    final Map<String, int> tally = await _compare(helper, paths, label: 'mutations');
    expect(tally['flagged'] ?? 0, greaterThan(paths.length ~/ 2), reason: 'the mutations must reach error paths');
    expect(tally['died'], isNull);
  });

  test('nesting of every shape and depth gives the report of a run without the helper', () async {
    final Map<String, String Function(int)> shapes = <String, String Function(int)>{
      'parentheses': (int depth) => 'var x = ${'(' * depth}1${')' * depth};',
      'unclosed': (int depth) => 'var x = ${'(' * depth}',
      'lists': (int depth) => 'var x = ${'[' * depth}${']' * depth};',
      'blocks': (int depth) => 'void f() ${'{' * depth}${'}' * depth}',
      'type_arguments': (int depth) => '${'List<' * depth}int${'>' * depth} x;',
      'negations': (int depth) => 'var x = ${'!' * depth}true;',
      'awaits': (int depth) => 'f() async { ${'await ' * depth}x; }',
      'conditionals': (int depth) => 'var x = ${'a ? b : ' * depth}c;',
      'assignments': (int depth) => 'f() { ${'a = ' * depth}1; }',
      'if_statements': (int depth) => 'f() { ${'if (a) ' * depth}; }',
      'closures': (int depth) => 'var x = ${'() => ' * depth}1;',
      'interpolations': (int depth) => 'var x = ${r"'${" * depth}1${"}'" * depth};',
      'function_types': (int depth) => '${'void Function(' * depth}int${')' * depth} x;',
      'patterns': (int depth) => 'f() { var ${'[' * depth}a${']' * depth} = x; }',
      'additions': (int depth) => 'var x = ${'a + ' * depth}a;',
      'calls': (int depth) => 'var x = a${'.b()' * depth};',
    };
    final List<String> relative = <String>[];
    for (final MapEntry<String, String Function(int)> shape in shapes.entries) {
      // Deeper than this the Dart analyzer takes minutes a file; 400,000
      // deep is in syntax_check_test, for the shapes it is quick on.
      for (final int depth in <int>[50, 250, 499, 501, 1500, 5000, 50000]) {
        final String name = 'lib/${shape.key}_$depth.dart';
        File(p.join(scratch.path, name))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(shape.value(depth));
        relative.add(name);
      }
    }
    final DVSyntaxReport withHelper =
        await dvCheckSyntaxOf(scratch.path, relative, helper: DVSyntaxHelper(helper));
    final DVSyntaxReport withoutHelper = await dvCheckSyntaxOf(scratch.path, relative);
    final Set<String> vouched = (await DVSyntaxHelper(helper)
            .cleanAmong(<String>[for (final String name in relative) p.join(scratch.path, name)]))
        .map((String path) => p.relative(path, from: scratch.path))
        .toSet();

    // Whether the Dart analyzer runs out of stack on a file nested a few
    // thousand deep depends on how much stack is in use when it starts, so
    // two Dart-only runs can disagree about such a file (function types 1,500
    // deep did, under load). Those files are checked for what matters -- the
    // helper never vouched for them -- and every other file must get the
    // same findings with and without the helper.
    final Set<String> unsteady = <String>{
      for (final String note in <String>[...withHelper.notes, ...withoutHelper.notes]) note.split(' ').first,
    };
    List<String> steady(DVSyntaxReport report) => <String>[
          for (final DVSyntaxFinding finding in report.findings)
            if (!unsteady.contains(finding.path)) '$finding',
        ];
    final Set<String> foundWithoutHelper = <String>{
      for (final DVSyntaxFinding finding in withoutHelper.findings) finding.path,
    };
    // ignore: avoid_print
    print('nesting: ${relative.length} files, ${vouched.length} answered clean by the helper, '
        '${withoutHelper.findings.length} findings and ${withoutHelper.notes.length} notes without it; '
        '${unsteady.length} files the analyzer could not always parse');
    expect(vouched, isNotEmpty);
    expect(vouched.intersection(foundWithoutHelper), isEmpty, reason: 'the helper vouched for a file with errors');
    expect(vouched.intersection(unsteady), isEmpty, reason: 'the helper vouched for a file Dart cannot parse');
    expect(steady(withHelper), steady(withoutHelper));
  });

  test('a project with errors gets the same report with and without the helper', () async {
    final Map<String, String> files = <String, String>{
      'lib/main.dart': 'void main() {\n  print(1);\n}\n',
      'lib/pages/index.dart': 'class Index {\n  void build() {\n    var count = 1\n  }\n}\n',
      'lib/pages/about.dart': 'class {\n',
      'lib/models/user.dart': "class User { final String name = 'unterminated; }\n",
      'lib/marked.dart': '﻿void marked() {}\n',
    };
    files.forEach((String name, String source) {
      File(p.join(scratch.path, name))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(source);
    });
    File(p.join(scratch.path, 'lib/latin1.dart')).writeAsBytesSync(<int>[...utf8.encode('var x = '), 0xff, 0x3b]);
    final DVSyntaxReport withHelper = await dvCheckProjectSyntax(scratch.path, helper: DVSyntaxHelper(helper));
    final DVSyntaxReport withoutHelper = await dvCheckProjectSyntax(scratch.path);
    expect(dvSyntaxReportLines(withHelper), dvSyntaxReportLines(withoutHelper));
    expect(withoutHelper.findings.map((DVSyntaxFinding finding) => finding.path).toSet(),
        <String>{'lib/pages/index.dart', 'lib/pages/about.dart', 'lib/models/user.dart', 'lib/latin1.dart'});
    expect(withHelper.cleanByHelper, 1, reason: 'main.dart; the marked file is deferred to Dart');
    expect(withHelper.parsedInDart, 5);
  });
}
