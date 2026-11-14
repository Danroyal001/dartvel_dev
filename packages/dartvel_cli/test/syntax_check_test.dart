import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartvel_cli/src/analysis/syntax_check.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A project with the given `lib/` files, removed when the test ends.
Directory _project(Map<String, Object> files) {
  final Directory root = Directory.systemTemp.createTempSync('dv_syntax_check_');
  addTearDown(() => root.deleteSync(recursive: true));
  files.forEach((String relative, Object content) {
    final File file = File(p.join(root.path, relative))..parent.createSync(recursive: true);
    if (content is String) {
      file.writeAsStringSync(content);
    } else {
      file.writeAsBytesSync(content as List<int>);
    }
  });
  return root;
}

/// A stand-in for the Rust helper: a shell script that speaks its protocol
/// and does what [body] says for the paths on its standard input.
DVSyntaxHelper _scriptedHelper(String body, {Duration? stallTimeout}) {
  final Directory directory = Directory.systemTemp.createTempSync('dv_syntax_helper_');
  addTearDown(() => directory.deleteSync(recursive: true));
  final File script = File(p.join(directory.path, 'helper.sh'))..writeAsStringSync('#!/bin/sh\n$body\n');
  Process.runSync('chmod', <String>['+x', script.path]);
  return stallTimeout == null
      ? DVSyntaxHelper(script.path)
      : DVSyntaxHelper(script.path, stallTimeout: stallTimeout);
}

const String _greet = r"printf 'dartvel_syntax\t1\n'";

/// Answers every path with [word].
String _answerAll(String word) => '''
$_greet
index=0
while IFS= read -r path; do
  printf '$word\\t%s${word == 'flagged' ? r'\t1' : ''}\\n' "\$index"
  index=\$((index+1))
done''';

const String _clean = 'void main() {\n  print(1);\n}\n';
const String _missingSemicolon = 'void main() {\n  var count = 1\n}\n';

void main() {
  group('the Dart engine', () {
    test('finds nothing in a source that parses', () {
      expect(dvDartSyntaxFindings(path: 'lib/main.dart', bytes: utf8.encode(_clean)).findings, isEmpty);
    });

    test('places a syntax error by line and column and names its code', () {
      final List<DVSyntaxFinding> findings =
          dvDartSyntaxFindings(path: 'lib/main.dart', bytes: utf8.encode(_missingSemicolon)).findings;
      expect(findings, hasLength(1));
      expect(findings.single.path, 'lib/main.dart');
      expect(findings.single.line, 2);
      expect(findings.single.column, 15);
      expect(findings.single.code, 'expected_token');
      expect(findings.single.message, "Expected to find ';'.");
      expect(findings.single.toString(), "lib/main.dart:2:15  Expected to find ';'. [expected_token]");
    });

    test('reads bytes that are not UTF-8 without throwing', () {
      final DVSyntaxFileResult result = dvDartSyntaxFindings(
        path: 'lib/latin1.dart',
        bytes: <int>[...utf8.encode("var name = '"), 0xff, 0xfe, ...utf8.encode("';\n")],
      );
      expect(result.findings, isEmpty, reason: 'the bad bytes are inside a string literal');
      expect(result.note, isNull);
    });

    test('accepts a byte order mark, as the compiler does', () {
      final DVSyntaxFileResult result = dvDartSyntaxFindings(
        path: 'lib/marked.dart',
        bytes: <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(_clean)],
      );
      expect(result.findings, isEmpty);
    });

    test('expressions nested past what the analyzer can parse are its own stack_overflow error', () {
      final String nested = 'var x = ${'(' * 400000}1${')' * 400000};';
      final DVSyntaxFileResult result = dvDartSyntaxFindings(path: 'lib/deep.dart', bytes: utf8.encode(nested));
      expect(result.findings.first.code, 'stack_overflow');
      expect(result.findings.first.message, 'The file has too many nested expressions or statements.');
      expect(result.note, isNull);
    });

    test('a source the analyzer throws on is a note, never a crash or a finding', () {
      // Type arguments nested this deep overflow the stack outside the
      // parser's own guard: parseString throws StackOverflowError.
      final String nested = '${'List<' * 400000}int${'>' * 400000} x;';
      final DVSyntaxFileResult result = dvDartSyntaxFindings(path: 'lib/deep.dart', bytes: utf8.encode(nested));
      expect(result.findings, isEmpty);
      expect(result.note, 'lib/deep.dart could not be checked for syntax errors: it is nested too deeply to parse.');
    });
  });

  group('which files are checked', () {
    test("the project's own Dart sources under lib/, in order, without generated files", () {
      final Directory root = _project(<String, Object>{
        'lib/main.dart': _clean,
        'lib/pages/index.dart': _clean,
        'lib/models/user.g.dart': _missingSemicolon,
        'lib/models/user.freezed.dart': _missingSemicolon,
        'lib/routes.dv.dart': _missingSemicolon,
        'lib/api.generated.dart': _missingSemicolon,
        'lib/generated/l10n.dart': _missingSemicolon,
        'lib/dartvel_client/client.dart': _missingSemicolon,
        'lib/notes.txt': 'not Dart',
        'test/widget_test.dart': _missingSemicolon,
        'build/web/main.dart': _missingSemicolon,
      });
      expect(dvSyntaxCheckFiles(root.path), <String>['lib/main.dart', 'lib/pages/index.dart']);
    });

    test('a project with no lib/ has nothing to check', () async {
      final Directory root = _project(<String, Object>{'pubspec.yaml': 'name: empty\n'});
      final DVSyntaxReport report = await dvCheckProjectSyntax(root.path);
      expect(report.findings, isEmpty);
      expect(report.files, 0);
    });
  });

  group('without the helper', () {
    test('every file is parsed in Dart and the errors are listed by file and place', () async {
      final Directory root = _project(<String, Object>{
        'lib/main.dart': _clean,
        'lib/pages/broken.dart': _missingSemicolon,
        'lib/pages/also_broken.dart': 'class {\n',
      });
      final DVSyntaxReport report = await dvCheckProjectSyntax(root.path);
      expect(report.files, 3);
      expect(report.cleanByHelper, 0);
      expect(report.parsedInDart, 3);
      expect(report.findings.map((DVSyntaxFinding finding) => finding.path).toSet(),
          <String>{'lib/pages/also_broken.dart', 'lib/pages/broken.dart'});
      expect(report.findings.first.path, 'lib/pages/also_broken.dart', reason: 'ordered by path');
      expect(report.findings.last.toString(), "lib/pages/broken.dart:2:15  Expected to find ';'. [expected_token]");
      expect(report.notes, isEmpty);
    });
  });

  group('with a helper', () {
    final Map<String, Object> mixedProject = <String, Object>{
      'lib/a.dart': _clean,
      'lib/b.dart': _missingSemicolon,
      'lib/c.dart': _clean,
      'lib/d.dart': 'class {\n',
    };

    Future<DVSyntaxReport> dartOnly(Directory root) => dvCheckProjectSyntax(root.path);

    test('a file the helper answers clean is not parsed again', () async {
      final Directory root = _project(<String, Object>{'lib/a.dart': _clean, 'lib/c.dart': _clean});
      final DVSyntaxReport report =
          await dvCheckProjectSyntax(root.path, helper: _scriptedHelper(_answerAll('clean')));
      expect(report.findings, isEmpty);
      expect(report.cleanByHelper, 2);
      expect(report.parsedInDart, 0);
    });

    test('a file the helper flags is decided by the Dart analyzer, never by the helper', () async {
      // The helper here is wrong about every file: it flags sources that
      // parse. Nothing it says may reach the developer.
      final Directory root = _project(<String, Object>{'lib/a.dart': _clean, 'lib/c.dart': _clean});
      final DVSyntaxReport report =
          await dvCheckProjectSyntax(root.path, helper: _scriptedHelper(_answerAll('flagged')));
      expect(report.findings, isEmpty);
      expect(report.cleanByHelper, 0);
      expect(report.parsedInDart, 2);
    });

    test('flagged and deferred files get exactly the findings of a run without the helper', () async {
      final Directory root = _project(mixedProject);
      final DVSyntaxHelper helper = _scriptedHelper('''
$_greet
printf 'clean\\t0\\n'
printf 'flagged\\t1\\t1\\n'
printf 'deferred\\t2\\tparser-panic\\n'
printf 'flagged\\t3\\t2\\n'
cat > /dev/null''');
      final DVSyntaxReport report = await dvCheckProjectSyntax(root.path, helper: helper);
      final DVSyntaxReport expected = await dartOnly(root);
      expect(report.findings.map((DVSyntaxFinding finding) => '$finding').toList(),
          expected.findings.map((DVSyntaxFinding finding) => '$finding').toList());
      expect(report.findings, isNotEmpty);
      expect(report.cleanByHelper, 1);
      expect(report.parsedInDart, 3);
    });

    test('a helper that dies part way costs nothing but time', () async {
      final Directory root = _project(mixedProject);
      // Answers the first file, then dies the way a stack overflow kills a
      // process, on every start.
      final DVSyntaxHelper helper = _scriptedHelper('''
$_greet
IFS= read -r path
printf 'clean\\t0\\n'
kill -SEGV \$\$''');
      final DVSyntaxReport report = await dvCheckProjectSyntax(root.path, helper: helper);
      final DVSyntaxReport expected = await dartOnly(root);
      expect(report.findings.map((DVSyntaxFinding finding) => '$finding').toList(),
          expected.findings.map((DVSyntaxFinding finding) => '$finding').toList());
      expect(report.files, 4);
      expect(report.cleanByHelper + report.parsedInDart, 4);
    }, testOn: '!windows');

    test('a helper that dies on one file is started again for the files after it', () async {
      final Directory root = _project(<String, Object>{
        'lib/a.dart': _clean,
        'lib/b.dart': _clean,
        'lib/c.dart': _clean,
        'lib/d.dart': _clean,
      });
      // Dies on any file named b.dart, as the real helper would on a file
      // that overflows its stack; answers every other file clean.
      final DVSyntaxHelper helper = _scriptedHelper('''
$_greet
index=0
while IFS= read -r path; do
  case "\$path" in *b.dart) kill -SEGV \$\$ ;; esac
  printf 'clean\\t%s\\n' "\$index"
  index=\$((index+1))
done''');
      final DVSyntaxReport report = await dvCheckProjectSyntax(root.path, helper: helper);
      expect(report.findings, isEmpty);
      expect(report.cleanByHelper, 3, reason: 'a, c and d; b went to Dart');
      expect(report.parsedInDart, 1);
    }, testOn: '!windows');

    test('a helper that greets with another protocol version is not believed', () async {
      final Directory root = _project(mixedProject);
      final DVSyntaxHelper helper = _scriptedHelper(_answerAll('clean').replaceFirst(r'dartvel_syntax\t1', r'dartvel_syntax\t2'));
      final DVSyntaxReport report = await dvCheckProjectSyntax(root.path, helper: helper);
      expect(report.cleanByHelper, 0);
      expect(report.findings, hasLength((await dartOnly(root)).findings.length));
    }, testOn: '!windows');

    test('answers that make no sense are not believed', () async {
      final Directory root = _project(mixedProject);
      for (final String nonsense in <String>[
        r"printf 'clean\t99\n'", // a file that was never asked about
        r"printf 'clean\tzero\n'",
        r"printf 'clean\n'",
        r"printf 'clean\t1\n'", // out of order: file 0 has no answer yet
        r"printf '\377\376\n'",
        r"printf 'spotless\t0\n'",
      ]) {
        final DVSyntaxHelper helper = _scriptedHelper('$_greet\n$nonsense\ncat > /dev/null');
        final DVSyntaxReport report = await dvCheckProjectSyntax(root.path, helper: helper);
        expect(report.cleanByHelper, 0, reason: nonsense);
        expect(report.parsedInDart, 4, reason: nonsense);
        expect(report.findings, isNotEmpty, reason: nonsense);
      }
    }, testOn: '!windows');

    test('a helper that stops answering is killed and Dart takes over', () async {
      final Directory root = _project(mixedProject);
      final DVSyntaxHelper helper = _scriptedHelper(
        '$_greet\nexec sleep 600',
        stallTimeout: const Duration(milliseconds: 300),
      );
      final Stopwatch watch = Stopwatch()..start();
      final DVSyntaxReport report = await dvCheckProjectSyntax(root.path, helper: helper);
      expect(watch.elapsed, lessThan(const Duration(seconds: 30)));
      expect(report.cleanByHelper, 0);
      expect(report.findings, hasLength((await dartOnly(root)).findings.length));
    }, testOn: '!windows');

    test('a helper that stalls on one file keeps its earlier answers and is started again after it', () async {
      final Directory root = _project(<String, Object>{
        'lib/a.dart': _clean,
        'lib/b.dart': _clean,
        'lib/c.dart': _clean,
        'lib/d.dart': _clean,
      });
      // Hangs on any file named b.dart, as the real helper can on a source
      // that sends the parser into a long search; answers the rest clean.
      final DVSyntaxHelper helper = _scriptedHelper('''
$_greet
index=0
while IFS= read -r path; do
  case "\$path" in *b.dart) exec sleep 600 ;; esac
  printf 'clean\\t%s\\n' "\$index"
  index=\$((index+1))
done''', stallTimeout: const Duration(milliseconds: 500));
      final DVSyntaxReport report = await dvCheckProjectSyntax(root.path, helper: helper);
      expect(report.findings, isEmpty);
      expect(report.cleanByHelper, 3, reason: 'a, c and d; b went to Dart');
      expect(report.parsedInDart, 1);
    }, testOn: '!windows');

    test('a helper that is not there is the same as no helper', () async {
      final Directory root = _project(mixedProject);
      final DVSyntaxReport report =
          await dvCheckProjectSyntax(root.path, helper: DVSyntaxHelper(p.join(root.path, 'no-such-helper')));
      expect(report.cleanByHelper, 0);
      expect(report.findings, hasLength((await dartOnly(root)).findings.length));
    });

    test('a path the protocol cannot carry is parsed in Dart', () async {
      final Directory root = _project(<String, Object>{
        'lib/a.dart': _clean,
        'lib/odd\nname.dart': _missingSemicolon,
      });
      final DVSyntaxReport report =
          await dvCheckProjectSyntax(root.path, helper: _scriptedHelper(_answerAll('clean')));
      expect(report.cleanByHelper, 1);
      expect(report.parsedInDart, 1);
      expect(report.findings, hasLength(1));
    }, testOn: '!windows');
  });

  group('the helper carried inside the CLI', () {
    final List<int> program = utf8.encode('#!/bin/sh\n${_answerAll('clean')}\n');
    final String carried = base64.encode(gzip.encode(program));
    final String digest = sha256.convert(program).toString();

    Directory cache() {
      final Directory directory = Directory.systemTemp.createTempSync('dv_syntax_cache_');
      addTearDown(() => directory.deleteSync(recursive: true));
      return directory;
    }

    test('a CLI that carries none has none', () async {
      expect(await dvInstallSyntaxHelper(carried: null, sha256Digest: '', cacheDirectory: cache()), isNull);
    });

    test('is written once, runs, and is found again', () async {
      final Directory directory = cache();
      final DVSyntaxHelper? first =
          await dvInstallSyntaxHelper(carried: carried, sha256Digest: digest, cacheDirectory: directory);
      expect(first, isNotNull);
      expect(File(first!.executable).readAsBytesSync(), program);
      final DateTime written = File(first.executable).lastModifiedSync();

      final Directory root = _project(<String, Object>{'lib/a.dart': _clean});
      expect((await dvCheckProjectSyntax(root.path, helper: first)).cleanByHelper, 1);

      final DVSyntaxHelper? second =
          await dvInstallSyntaxHelper(carried: carried, sha256Digest: digest, cacheDirectory: directory);
      expect(second!.executable, first.executable);
      expect(File(second.executable).lastModifiedSync(), written);
      expect(directory.listSync(), hasLength(1), reason: 'no temporary file left behind');
    }, testOn: '!windows');

    test('a file in the cache that is not the carried helper is replaced, never run', () async {
      final Directory directory = cache();
      final DVSyntaxHelper? first =
          await dvInstallSyntaxHelper(carried: carried, sha256Digest: digest, cacheDirectory: directory);
      File(first!.executable).writeAsStringSync('#!/bin/sh\necho tampered\n');
      final DVSyntaxHelper? second =
          await dvInstallSyntaxHelper(carried: carried, sha256Digest: digest, cacheDirectory: directory);
      expect(File(second!.executable).readAsBytesSync(), program);
    }, testOn: '!windows');

    test('carried bytes that do not match their digest are refused', () async {
      expect(
        await dvInstallSyntaxHelper(carried: carried, sha256Digest: '0' * 64, cacheDirectory: cache()),
        isNull,
      );
    });

    test('a cache that cannot be written means no helper, not a failure', () async {
      final Directory directory = cache();
      final File inTheWay = File(p.join(directory.path, 'file'))..writeAsStringSync('');
      expect(
        await dvInstallSyntaxHelper(carried: carried, sha256Digest: digest, cacheDirectory: Directory(inTheWay.path)),
        isNull,
      );
    });

    test('the repository carries no helper: one is put in when a release binary is built', () {
      expect(dvCarriedSyntaxHelper, isNull);
      expect(dvCarriedSyntaxHelperSha256, isEmpty);
    });
  });

  group('what the developer sees', () {
    test('nothing for a project that parses', () {
      expect(dvSyntaxReportLines(const DVSyntaxReport(files: 3, cleanByHelper: 3, parsedInDart: 0)), isEmpty);
    });

    test('each error with its file, line and column', () async {
      final Directory root = _project(<String, Object>{'lib/pages/broken.dart': _missingSemicolon});
      expect(dvSyntaxReportLines(await dvCheckProjectSyntax(root.path)), <String>[
        '1 syntax error(s) in the project:',
        "   lib/pages/broken.dart:2:15  Expected to find ';'. [expected_token]",
      ]);
    });
  });
}
