/// The freeze rule's measurement: convert every file of a corpus to the
/// dialect and back, and count what did not come back byte for byte.
///
/// The proposal freezes the insertion rules when the whole pub.dev corpus
/// round-trips. Until then each failure here is either a missing rule or a
/// construct the dialect will refuse with a named error.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/token.dart';

import 'dv_dialect.dart';

final class RoundTrip {
  RoundTrip({
    required this.identical,
    required this.semicolons,
    required this.removed,
    this.firstDifferenceLine,
  });

  /// Whether dialect and back gave the original text, byte for byte.
  final bool identical;

  /// Semicolon tokens in the original.
  final int semicolons;

  /// How many of them the dialect drops.
  final int removed;

  /// The original's line where the round trip first differs.
  final int? firstDifferenceLine;
}

/// Round-trips one standard Dart source. Throws [FormatException] when it is
/// not standard Dart.
RoundTrip roundTrip(String source) {
  final dialect = toDialect(source);
  final back = toDart(dialect).source;
  final identical = back == source;
  return RoundTrip(
    identical: identical,
    semicolons: _semicolons(source),
    removed: source.length - dialect.length,
    firstDifferenceLine: identical
        ? null
        : _lineOf(source, _firstDifference(source, back)),
  );
}

final class CorpusFailure {
  const CorpusFailure(this.path, this.line);
  final String path;
  final int line;
}

final class CorpusReport {
  int files = 0;
  int identical = 0;
  int notStandard = 0;
  int semicolons = 0;
  int removed = 0;
  final failures = <CorpusFailure>[];

  double get identicalShare => files == 0 ? 0 : identical / files;
  double get removedShare => semicolons == 0 ? 0 : removed / semicolons;
}

const _skipped = {'.dart_tool', '.git', 'build', '.pub-cache'};

/// Round-trips every `.dart` file under [roots]. Files that are not standard
/// Dart (test inputs for parse errors, templates) are counted apart, since
/// they have no meaning to preserve.
CorpusReport roundTripCorpus(List<Directory> roots) {
  final report = CorpusReport();
  for (final root in roots) {
    for (final file in _dartFiles(root)) {
      final String source;
      try {
        source = file.readAsStringSync();
      } on FileSystemException {
        report.notStandard++;
        continue;
      }
      final RoundTrip result;
      try {
        result = roundTrip(source);
      } on FormatException {
        report.notStandard++;
        continue;
      }
      report
        ..files += 1
        ..semicolons += result.semicolons
        ..removed += result.removed;
      if (result.identical) {
        report.identical++;
      } else {
        report.failures.add(
          CorpusFailure(file.path, result.firstDifferenceLine!),
        );
      }
    }
  }
  return report;
}

Iterable<File> _dartFiles(Directory directory) sync* {
  final entries = directory.listSync(followLinks: false)
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final entry in entries) {
    final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (entry is Directory) {
      if (_skipped.contains(name)) continue;
      yield* _dartFiles(entry);
    } else if (entry is File && name.endsWith('.dart')) {
      yield entry;
    }
  }
}

int _semicolons(String source) {
  var count = 0;
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  for (
    Token token = parsed.unit.beginToken;
    token.type != TokenType.EOF;
    token = token.next!
  ) {
    if (token.type == TokenType.SEMICOLON && !token.isSynthetic) count++;
  }
  return count;
}

int _firstDifference(String a, String b) {
  final length = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    if (a.codeUnitAt(i) != b.codeUnitAt(i)) return i;
  }
  return length;
}

int _lineOf(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;
