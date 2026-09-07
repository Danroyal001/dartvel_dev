// Every section of the specification has an index entry, and the reverse.
//
// `dart tool/ci/spec_coverage_check.dart`
//
// spec_status_check holds an entry to the evidence it names. This asks the
// question one step earlier: whether there is an entry at all. A section
// added to NEW_SPEC.md and not to docs/spec-status.json is invisible to
// every check downstream, and an entry whose heading has gone reports a
// status for something that is no longer in the specification.
import 'dart:convert';
import 'dart:io';

import 'spec_coverage.dart';

void main() {
  final File spec = File('NEW_SPEC.md');
  final File index = File('docs/spec-status.json');
  for (final File file in <File>[spec, index]) {
    if (file.existsSync()) continue;
    stderr.writeln('${file.path} is not here.');
    exit(2);
  }

  final Map<String, Object?> document =
      jsonDecode(index.readAsStringSync()) as Map<String, Object?>;
  final List<String> sections = <String>[
    for (final Object? entry in document['sections'] as List<Object?>? ??
        const <Object?>[])
      if (entry is Map && entry['section'] is String)
        entry['section']! as String,
  ];

  final List<String> headings = dvSpecHeadings(spec.readAsStringSync());
  final ({List<String> unlisted, List<String> unheaded}) coverage =
      dvSpecCoverage(headings: headings, sections: sections);

  if (coverage.unlisted.isEmpty && coverage.unheaded.isEmpty) {
    stdout.writeln('spec coverage: ${headings.length} sections in NEW_SPEC.md, '
        '${sections.length} in the index, every one of them in both');
    return;
  }

  if (coverage.unlisted.isNotEmpty) {
    stdout.writeln('In NEW_SPEC.md and not in docs/spec-status.json:');
    for (final String name in coverage.unlisted) {
      stdout.writeln('  $name');
    }
    stdout.writeln('');
    stdout.writeln('A section with no entry is tracked by nothing. It cannot '
        'be Partial or Shipped, and to anybody reading the index it looks '
        'like a feature that does not exist rather than one nobody '
        'recorded.');
  }

  if (coverage.unheaded.isNotEmpty) {
    if (coverage.unlisted.isNotEmpty) stdout.writeln('');
    stdout.writeln('In docs/spec-status.json and not in NEW_SPEC.md:');
    for (final String name in coverage.unheaded) {
      stdout.writeln('  $name');
    }
    stdout.writeln('');
    stdout.writeln('An entry whose heading was renamed or removed goes on '
        'reporting a status for a section the specification no longer has.');
  }

  exit(1);
}
