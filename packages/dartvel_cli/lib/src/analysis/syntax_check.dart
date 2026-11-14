/// Whether the project's Dart sources parse, checked before anything is
/// generated or built.
///
/// The generators and the lexical checks read source text, and a file that
/// does not parse makes them report nonsense or generate code that fails
/// minutes later inside `flutter build`. This says so first, with the file,
/// line and column.
///
/// Two engines answer, and the Dart analyzer always has the last word:
///
/// * The Rust helper (`rust/dartvel_syntax`, a port of the analyzer's
///   `parseString`) is asked first. A file it answers `clean` is done.
/// * Every other file -- flagged, deferred, not answered because the helper
///   died or is not there -- is parsed by `package:analyzer`, and only what
///   the analyzer reports is shown.
///
/// So the helper can make the check faster and can never make it say
/// something the analyzer would not: a file is never reported as broken on
/// the Rust parser's word.
library dartvel_cli.analysis.syntax_check;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'syntax_helper_carried.g.dart';

export 'syntax_helper_carried.g.dart';

/// One syntax error.
class DVSyntaxFinding {
  const DVSyntaxFinding({
    required this.path,
    required this.line,
    required this.column,
    required this.offset,
    required this.code,
    required this.message,
  });

  /// Relative to the project, with forward slashes.
  final String path;

  /// One-based, as editors count.
  final int line;
  final int column;

  /// In UTF-16 code units from the start of the file.
  final int offset;

  /// The analyzer's name for the diagnostic, `expected_token` for one.
  final String code;
  final String message;

  @override
  String toString() => '$path:$line:$column  $message [$code]';
}

/// What the Dart analyzer found in one file.
class DVSyntaxFileResult {
  const DVSyntaxFileResult({this.findings = const <DVSyntaxFinding>[], this.note});

  final List<DVSyntaxFinding> findings;

  /// Set when the file could not be checked at all. Not an error in the
  /// file: the build goes on and the compiler decides.
  final String? note;
}

/// What the check found in a project.
class DVSyntaxReport {
  const DVSyntaxReport({
    required this.files,
    required this.cleanByHelper,
    required this.parsedInDart,
    this.findings = const <DVSyntaxFinding>[],
    this.notes = const <String>[],
  });

  /// How many files were checked.
  final int files;

  /// How many of them the Rust helper answered clean.
  final int cleanByHelper;

  /// How many of them the Dart analyzer parsed.
  final int parsedInDart;

  /// Ordered by path, then by place in the file.
  final List<DVSyntaxFinding> findings;

  /// Files that could not be checked, in words.
  final List<String> notes;
}

/// The lines `dartvel build` and `dartvel doctor` print for [report];
/// none when every file parses.
List<String> dvSyntaxReportLines(DVSyntaxReport report) {
  if (report.findings.isEmpty) return const <String>[];
  return <String>[
    '${report.findings.length} syntax error(s) in the project:',
    for (final DVSyntaxFinding finding in report.findings) '   $finding',
  ];
}

final RegExp _generatedFile = RegExp(r'\.(g|freezed|dv|generated)\.dart$');

/// The files the check reads: the project's own Dart sources under `lib/`,
/// relative to [root], sorted.
///
/// Generated files are left out, as the conventions check leaves them out:
/// the build that is about to run writes them again, and a stale one must
/// not stop it.
List<String> dvSyntaxCheckFiles(String root) {
  final Directory lib = Directory(p.join(root, 'lib'));
  if (!lib.existsSync()) return const <String>[];
  final List<String> files = <String>[];
  for (final File file in lib.listSync(recursive: true, followLinks: false).whereType<File>()) {
    final String relative = p.relative(file.path, from: root).replaceAll(r'\', '/');
    if (!relative.endsWith('.dart') ||
        relative.startsWith('lib/dartvel_client/') ||
        _generatedFile.hasMatch(relative) ||
        relative.contains('/generated/')) {
      continue;
    }
    files.add(relative);
  }
  return files..sort();
}

/// Parses one file with the Dart analyzer. Never throws.
///
/// [bytes] are read as the compiler reads a source: a byte order mark is
/// dropped and a byte sequence that is not UTF-8 becomes U+FFFD.
DVSyntaxFileResult dvDartSyntaxFindings({required String path, required List<int> bytes}) {
  final ParseStringResult result;
  try {
    result = parseString(
      content: utf8.decode(bytes, allowMalformed: true),
      path: path,
      throwIfDiagnostics: false,
    );
    // The analyzer runs out of stack on a source nested hundreds of
    // thousands deep, and that is an Error, not an Exception.
    // ignore: avoid_catches_without_on_clauses
  } catch (error) {
    final String reason = error is StackOverflowError ? 'it is nested too deeply to parse' : 'the parser failed';
    return DVSyntaxFileResult(note: '$path could not be checked for syntax errors: $reason.');
  }
  final LineInfo lines = result.lineInfo;
  return DVSyntaxFileResult(findings: <DVSyntaxFinding>[
    for (final Diagnostic diagnostic in result.errors)
      if (diagnostic.severity == Severity.error)
        DVSyntaxFinding(
          path: path,
          line: lines.getLocation(diagnostic.offset).lineNumber,
          column: lines.getLocation(diagnostic.offset).columnNumber,
          offset: diagnostic.offset,
          code: diagnostic.diagnosticCode.lowerCaseUniqueName,
          message: diagnostic.message,
        ),
  ]);
}

/// Checks every file of [dvSyntaxCheckFiles]. With no [helper], every file
/// is parsed in Dart.
Future<DVSyntaxReport> dvCheckProjectSyntax(String root, {DVSyntaxHelper? helper}) =>
    dvCheckSyntaxOf(root, dvSyntaxCheckFiles(root), helper: helper);

/// Checks [relativePaths] of the project at [root].
Future<DVSyntaxReport> dvCheckSyntaxOf(
  String root,
  List<String> relativePaths, {
  DVSyntaxHelper? helper,
}) async {
  final Set<String> clean = helper == null
      ? const <String>{}
      : await helper.cleanAmong(<String>[for (final String relative in relativePaths) p.join(root, relative)]);

  final List<DVSyntaxFinding> findings = <DVSyntaxFinding>[];
  final List<String> notes = <String>[];
  int parsedInDart = 0;
  for (final String relative in relativePaths) {
    final String absolute = p.join(root, relative);
    if (clean.contains(absolute)) continue;
    parsedInDart++;
    final List<int> bytes;
    try {
      bytes = File(absolute).readAsBytesSync();
    } on FileSystemException catch (error) {
      notes.add('$relative could not be read: ${error.osError?.message ?? error.message}.');
      continue;
    }
    final DVSyntaxFileResult result = dvDartSyntaxFindings(path: relative, bytes: bytes);
    findings.addAll(result.findings);
    if (result.note != null) notes.add(result.note!);
  }
  return DVSyntaxReport(
    files: relativePaths.length,
    cleanByHelper: relativePaths.length - parsedInDart,
    parsedInDart: parsedInDart,
    findings: findings,
    notes: notes,
  );
}

/// The Rust helper program, run as a separate process.
///
/// A separate process on purpose. The parser is recursive descent with
/// thousands of ported `throw`s, and a source can be written to exhaust any
/// stack; in this process that would take the CLI down with it. Out there
/// it costs the helper, and the files it did not answer are parsed in Dart.
class DVSyntaxHelper {
  DVSyntaxHelper(this.executable, {this.stallTimeout = const Duration(seconds: 20)});

  final String executable;

  /// How long the helper may go without answering before it is killed.
  final Duration stallTimeout;

  /// The protocol this CLI speaks; `PROTOCOL_VERSION` in the helper.
  static const String greeting = 'dartvel_syntax\t1';

  /// A helper that dies is started again after the file it died on, this
  /// many times. A project with more hostile files than that is parsed in
  /// Dart from there on.
  static const int restarts = 3;

  /// Which of [paths] the helper answers clean. Never throws: whatever
  /// goes wrong, the paths it did not vouch for are simply not returned.
  Future<Set<String>> cleanAmong(List<String> paths) async {
    // One path a line: a path with a line break in it cannot be asked about.
    final List<String> askable = <String>[
      for (final String path in paths)
        if (!path.contains('\n') && !path.contains('\r')) path,
    ];
    final Set<String> clean = <String>{};
    int next = 0;
    for (int starts = 0; next < askable.length && starts <= restarts; starts++) {
      final _HelperRun run = await _run(askable.sublist(next));
      if (!run.believable) break;
      for (final int index in run.clean) {
        clean.add(askable[next + index]);
      }
      if (run.finished) break;
      // It died on the file after the last one it answered.
      next += run.answered + 1;
    }
    return clean;
  }

  Future<_HelperRun> _run(List<String> paths) async {
    final Process process;
    try {
      process = await Process.start(executable, const <String>[]);
    } on ProcessException {
      return const _HelperRun.unbelievable();
    }
    // The helper may be gone before it has read everything.
    unawaited(process.stdin.done.catchError((Object _) {}));
    unawaited(process.stderr.drain<void>().catchError((Object _) {}));
    try {
      process.stdin.write(paths.map((String path) => '$path\n').join());
      unawaited(process.stdin.close().catchError((Object _) {}));
    } on Object {
      // Broken pipe: its exit code tells the rest.
    }

    final List<int> clean = <int>[];
    int answered = 0;
    bool greeted = false;
    bool believable = true;
    bool stalled = false;
    try {
      await for (final String line in process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .timeout(stallTimeout)) {
        if (!believable) continue;
        if (!greeted) {
          greeted = true;
          believable = line == greeting;
          continue;
        }
        final List<String> fields = line.split('\t');
        final String word = fields.first;
        final int? index = fields.length > 1 ? int.tryParse(fields[1]) : null;
        if (word == 'diagnostic' && index == answered - 1) continue;
        if (index != answered || index! >= paths.length) {
          believable = false;
        } else if (word == 'clean' && fields.length == 2) {
          clean.add(index);
          answered++;
        } else if ((word == 'flagged' || word == 'deferred') && fields.length == 3) {
          answered++;
        } else {
          believable = false;
        }
      }
    } on TimeoutException {
      stalled = true;
    } on Object {
      believable = false;
    }
    if (stalled || !believable) {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      return const _HelperRun.unbelievable();
    }
    final int exitCode = await process.exitCode;
    if (!greeted) return const _HelperRun.unbelievable();
    final bool finished = exitCode == 0;
    if (finished && answered != paths.length) return const _HelperRun.unbelievable();
    return _HelperRun(clean: clean, answered: answered, finished: finished);
  }
}

class _HelperRun {
  const _HelperRun({required this.clean, required this.answered, required this.finished}) : believable = true;

  const _HelperRun.unbelievable()
      : clean = const <int>[],
        answered = 0,
        finished = false,
        believable = false;

  /// Indexes, into the paths of this run, of the files answered clean.
  final List<int> clean;

  /// How many files were answered, in order from the first.
  final int answered;

  /// Whether the helper answered everything and exited normally.
  final bool finished;

  /// False when the helper broke its protocol: nothing it said counts.
  final bool believable;
}

/// Writes the helper a CLI carries to [cacheDirectory] (once) and returns
/// it, or null when the CLI carries none or it cannot be put there.
///
/// [carried] is the program gzipped and base64-encoded, [sha256Digest] its
/// SHA-256. The file is named by its digest and checked against it before
/// every use, so a file somebody else put at that name is replaced, never
/// run. Never throws.
Future<DVSyntaxHelper?> dvInstallSyntaxHelper({
  required String? carried,
  required String sha256Digest,
  Directory? cacheDirectory,
}) async {
  if (carried == null) return null;
  try {
    final List<int> program = gzip.decode(base64.decode(carried));
    if (sha256.convert(program).toString() != sha256Digest) return null;
    final Directory directory = cacheDirectory ?? _defaultHelperDirectory();
    directory.createSync(recursive: true);
    final String name = 'dartvel_syntax-${sha256Digest.substring(0, 16)}${Platform.isWindows ? '.exe' : ''}';
    final File installed = File(p.join(directory.path, name));
    if (installed.existsSync() && sha256.convert(installed.readAsBytesSync()).toString() == sha256Digest) {
      return DVSyntaxHelper(installed.path);
    }
    // Written beside its final name and renamed, so another `dartvel`
    // starting now sees the whole program or none of it.
    final File partial = File(p.join(directory.path, '.$name.$pid.partial'))..writeAsBytesSync(program, flush: true);
    if (!Platform.isWindows) {
      final ProcessResult mode = Process.runSync('chmod', <String>['755', partial.path]);
      if (mode.exitCode != 0) {
        partial.deleteSync();
        return null;
      }
    }
    partial.renameSync(installed.path);
    return DVSyntaxHelper(installed.path);
    // Anything at all -- no home, a read-only disk, bytes that are not
    // gzip -- means the check runs in Dart.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return null;
  }
}

/// `~/.dartvel/native`, beside the toolchains Dartvel manages.
Directory _defaultHelperDirectory() {
  final String? home = Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  if (home == null || home.isEmpty) throw StateError('no home directory');
  return Directory(p.join(home, '.dartvel', 'native'));
}

Future<DVSyntaxHelper?>? _helperOfThisCli;

/// The helper this CLI carries, ready to run, or null.
///
/// `DARTVEL_SYNTAX_ENGINE=dart` in the environment turns the helper off.
Future<DVSyntaxHelper?> dvSyntaxHelperOfThisCli() {
  if (Platform.environment['DARTVEL_SYNTAX_ENGINE'] == 'dart') {
    return Future<DVSyntaxHelper?>.value();
  }
  return _helperOfThisCli ??= dvInstallSyntaxHelper(
    carried: dvCarriedSyntaxHelper,
    sha256Digest: dvCarriedSyntaxHelperSha256,
  );
}
