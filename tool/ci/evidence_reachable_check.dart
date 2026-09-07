// Runs the reachability check over docs/spec-status.json.
//
// `dart tool/ci/evidence_reachable_check.dart`
//
// Reports every implementation file a section cites that nothing outside a
// test refers to. The check is deliberately forgiving -- one referenced
// symbol makes a file reachable -- because it is looking for the failure
// this repository has now made three times: a correct implementation,
// unit-tested against its own return value, recorded as shipped, and never
// called.
import 'dart:convert';
import 'dart:io';

import 'evidence_reachable.dart';

Future<void> main(List<String> args) async {
  final File index = File('docs/spec-status.json');
  if (!index.existsSync()) {
    stderr.writeln('docs/spec-status.json is not here.');
    exit(2);
  }

  final Map<String, Object?> document =
      jsonDecode(index.readAsStringSync()) as Map<String, Object?>;
  final List<Object?> sections =
      document['sections'] as List<Object?>? ?? const <Object?>[];

  // Which section cited what, so a failure names the claim rather than only
  // the file.
  final Map<String, String> sectionByFile = <String, String>{};
  final Map<String, Set<String>> symbolsByFile = <String, Set<String>>{};

  for (final Object? entry in sections) {
    if (entry is! Map) continue;
    final String section = '${entry['section']}';
    for (final Object? path in entry['evidence'] as List<Object?>? ??
        const <Object?>[]) {
      if (path is! String) continue;
      // Implementation only. A test citing itself is the point of a test.
      if (!path.endsWith('.dart')) continue;
      if (path.contains('/test/') || path.startsWith('test/')) continue;
      final File file = File(path);
      if (!file.existsSync()) continue;
      symbolsByFile[path] = dvPublicSymbols(file.readAsStringSync());
      sectionByFile[path] = section;
    }
  }

  // Everything every other implementation file mentions. Word-boundary
  // tokens rather than a parse: a name appearing anywhere in another
  // library is enough to call the file reached, and being generous here is
  // deliberate -- a false alarm costs somebody an afternoon and teaches
  // them to switch the check off.
  final Map<String, Set<String>> references = <String, Set<String>>{};
  for (final Directory package in Directory('packages')
      .listSync()
      .whereType<Directory>()) {
    final Directory lib = Directory('${package.path}/lib');
    if (!lib.existsSync()) continue;
    for (final File file in lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))) {
      references[file.path] = RegExp(r'[A-Za-z_][A-Za-z0-9_]*')
          .allMatches(file.readAsStringSync())
          .map((RegExpMatch m) => m.group(0)!)
          .toSet();
    }
  }

  final List<String> unreachable = dvUnreachableEvidence(
    symbolsByFile: symbolsByFile,
    referencesByLibFile: references,
  );

  if (unreachable.isEmpty) {
    stdout.writeln('every cited implementation file is called by something '
        '(${symbolsByFile.length} checked)');
    return;
  }

  stdout.writeln('Evidence nothing outside a test calls:');
  for (final String path in unreachable) {
    stdout.writeln('  $path');
    stdout.writeln('    cited by: ${sectionByFile[path]}');
    stdout.writeln('    declares: ${symbolsByFile[path]!.join(', ')}');
  }
  stdout.writeln('');
  stdout.writeln('A section citing a file nothing calls is a section '
      'claiming work that does not run. Either wire it in, or say in the '
      'section what is still absent.');
  exit(1);
}
