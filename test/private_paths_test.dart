// Nothing this repository publishes points into one machine's home directory.
//
// The repository is public. A doc that says "run it in ~/heavy.sh" or names
// ~/agent-context/AGENTS.md sends a reader to a file only one server has,
// and tells everyone how that server is laid out.
import 'dart:io';

import 'package:test/test.dart';

final RegExp private = RegExp(
  r'heavy\.sh|/home/sigmadev|~/(?:agent-context|briefs|wt/|passepartout|naijalife|dartvel-proposals|\.config/dartvel)',
);

/// Files that name the patterns in order to keep them out.
const Set<String> guards = <String>{
  'test/private_paths_test.dart',
  'packages/dartvel_cli/test/architecture_docs_test.dart',
};

void main() {
  test('no tracked file names a private host path', () {
    final ProcessResult files = Process.runSync('git', <String>['ls-files']);
    final List<String> hits = <String>[];
    for (final String path in '${files.stdout}'.split('\n')) {
      if (path.isEmpty || guards.contains(path)) continue;
      if (!RegExp(r'\.(md|dart|ya?ml|json|txt)$').hasMatch(path)) continue;
      final File file = File(path);
      if (!file.existsSync()) continue;
      final List<String> lines;
      try {
        lines = file.readAsLinesSync();
      } on FileSystemException {
        continue;
      }
      for (int i = 0; i < lines.length; i++) {
        if (private.hasMatch(lines[i])) hits.add('$path:${i + 1}');
      }
    }
    expect(hits, isEmpty);
  });
}
