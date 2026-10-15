// Every link on the site goes to a generated route.
//
// A route written as a string drifts the moment its page moves, and nothing
// catches it: the link simply 404s. The generated DVRoutes member turns that
// into a compile error, which is why the conventions forbid the literal in
// application code -- and this site had 104 of them.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no site link names its page with a string', () {
    final RegExp literal = RegExp(
      r"(?:(?:PrimaryLink|GhostLink|NavLink|FooterLink|SiteButton)\(\s*'[^']*',\s*"
      r"|(?:href|current|path|to):\s*)"
      r"'/",
    );
    final List<String> found = <String>[];
    for (final FileSystemEntity entry in Directory('lib').listSync(recursive: true)) {
      if (entry is! File || !entry.path.endsWith('.dart')) continue;
      if (entry.path.contains('dartvel_client')) continue;
      // Comments are prose about old shapes, not links.
      final String source = entry
          .readAsLinesSync()
          .map((String l) => l.trimLeft().startsWith('//') ? '' : l)
          .join('\n');
      for (final Match m in literal.allMatches(source)) {
        final int line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
        found.add('${entry.path}:$line');
      }
    }
    expect(found, isEmpty, reason: 'use the DVRoutes member instead');
  });
}
