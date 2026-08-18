// Validates docs/spec-status.json against NEW_SPEC.md and the tree.
//
// The labels in that index are only worth having if something checks them.
// Without this, a section stays "Shipped" long after the code it named moved,
// which is the drift the Specification Status section exists to end.
//
//   dart run tool/spec_status_check.dart
//
// Exits non-zero and prints every problem it found, rather than the first.
import 'dart:convert';
import 'dart:io';

const _statuses = <String>{'Designed', 'Partial', 'Shipped'};
const _stabilities = <String>{'Draft', 'Contract'};

int main(List<String> arguments) {
  final root = Directory.current.path;
  final specFile = File('$root/NEW_SPEC.md');
  final indexFile = File('$root/docs/spec-status.json');

  if (!specFile.existsSync()) return _fail(['NEW_SPEC.md not found']);
  if (!indexFile.existsSync()) return _fail(['docs/spec-status.json not found']);

  final specSections = <String>[
    for (final line in specFile.readAsLinesSync())
      if (line.startsWith('# ')) line.substring(2).trim(),
  ];

  final Object? decoded;
  try {
    decoded = jsonDecode(indexFile.readAsStringSync());
  } on FormatException catch (error) {
    return _fail(['docs/spec-status.json is not valid JSON: ${error.message}']);
  }
  if (decoded is! Map<String, Object?> || decoded['sections'] is! List) {
    return _fail(['docs/spec-status.json must be an object with a "sections" list']);
  }

  final problems = <String>[];
  final seen = <String>{};

  for (final entry in decoded['sections']! as List<Object?>) {
    if (entry is! Map<String, Object?>) {
      problems.add('A "sections" entry is not an object.');
      continue;
    }
    final name = entry['section'];
    if (name is! String || name.isEmpty) {
      problems.add('A "sections" entry has no "section" name.');
      continue;
    }
    if (!seen.add(name)) problems.add('$name: listed more than once.');
    if (!specSections.contains(name)) {
      problems.add('$name: no such section in NEW_SPEC.md.');
      continue;
    }
    // Narrative sections describe no API, so they carry no labels.
    if (entry['kind'] == 'narrative') continue;

    final stability = entry['stability'];
    if (stability is! String || !_stabilities.contains(stability)) {
      problems.add('$name: stability must be one of ${_stabilities.join(', ')}.');
    }
    final status = entry['status'];
    if (status is! String || !_statuses.contains(status)) {
      problems.add('$name: status must be one of ${_statuses.join(', ')}.');
      continue;
    }

    final evidence = entry['evidence'];
    final paths = evidence is List
        ? evidence.whereType<String>().toList()
        : const <String>[];

    // The rule the whole index rests on: a claim that something is built must
    // name what proves it, and that thing must exist.
    if (status != 'Designed') {
      if (paths.isEmpty) {
        problems.add('$name: "$status" must cite at least one evidence path.');
      }
      for (final path in paths) {
        final exists = File('$root/$path').existsSync() ||
            Directory('$root/$path').existsSync();
        if (!exists) problems.add('$name: evidence "$path" does not exist.');
      }
    } else if (paths.isNotEmpty) {
      problems.add('$name: "Designed" cites evidence; use Partial or Shipped.');
    }

    // "Partial" without saying which part is missing is indistinguishable from
    // "Shipped" to a reader, which is how a gap stops being visible.
    if (status == 'Partial') {
      final absent = entry['absent'];
      if (absent is! String || absent.trim().isEmpty) {
        problems.add('$name: "Partial" must say what is absent.');
      }
    }
  }

  for (final name in specSections) {
    if (!seen.contains(name)) {
      problems.add('$name: section is missing from docs/spec-status.json.');
    }
  }

  if (problems.isNotEmpty) return _fail(problems);

  final labelled = seen.length - _narrativeCount(decoded);
  stdout.writeln('spec-status: ${seen.length} sections, $labelled labelled, '
      'all evidence present.');
  return 0;
}

int _narrativeCount(Map<String, Object?> decoded) => (decoded['sections']! as List)
    .whereType<Map<String, Object?>>()
    .where((e) => e['kind'] == 'narrative')
    .length;

int _fail(List<String> problems) {
  stderr.writeln('spec-status: ${problems.length} problem(s)');
  for (final problem in problems) {
    stderr.writeln('  - $problem');
  }
  exitCode = 1;
  return 1;
}
