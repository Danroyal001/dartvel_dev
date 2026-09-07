// Every section of the specification, against the index that records it.
//
// spec_status_check holds an entry to the evidence it cites; nothing asked
// the question one step earlier, which is whether there is an entry at all.
// A section added to NEW_SPEC.md and not to the index is invisible to every
// check downstream, and reads to anybody looking at the index as a feature
// that does not exist rather than one nobody recorded.
import 'package:test/test.dart';

import '../../tool/ci/spec_coverage.dart';

void main() {
  group('reading the headings', () {
    test('top-level only', () {
      // ## is used for the subsections inside a feature -- Policy, Sessions,
      // Bindings, Security, Deliberately absent -- and those recur under
      // many features. Counting them would compare two different things.
      const String spec = '''
# Kiosk Mode

Text.

## Policy

More text.

# Multi-Window
''';

      expect(dvSpecHeadings(spec), <String>['Kiosk Mode', 'Multi-Window']);
    });

    test('a comment inside a fenced block is not a heading', () {
      // The specification is full of YAML samples, and a YAML comment starts
      // with the same character. A check that thought one was a heading
      // would demand an index entry for somebody's comment.
      const String spec = '''
# Configuration

```yaml
dartvel:
  # the admin lives here
  admin:
    path: /__studio
```

# Pages
''';

      expect(dvSpecHeadings(spec), <String>['Configuration', 'Pages']);
    });

    test('a tilde fence counts as one too', () {
      const String spec = '''
# One

~~~
# not a heading
~~~

# Two
''';

      expect(dvSpecHeadings(spec), <String>['One', 'Two']);
    });

    test('a hash with no space is not a heading', () {
      // #!/usr/bin/env and #include are not sections.
      expect(dvSpecHeadings('#!/bin/sh\n# Real\n'), <String>['Real']);
    });
  });

  group('comparing the two', () {
    test('a section with no entry is reported', () {
      final ({List<String> unlisted, List<String> unheaded}) result =
          dvSpecCoverage(
        headings: <String>['Kiosk Mode', 'Billing'],
        sections: <String>['Kiosk Mode'],
      );

      expect(result.unlisted, <String>['Billing']);
      expect(result.unheaded, isEmpty);
    });

    test('an entry with no section is reported too', () {
      // The other direction: an entry whose heading was renamed or removed
      // goes on reporting a status for a section that is not in the
      // specification any more.
      final ({List<String> unlisted, List<String> unheaded}) result =
          dvSpecCoverage(
        headings: <String>['Kiosk Mode'],
        sections: <String>['Kiosk Mode', 'Something Removed'],
      );

      expect(result.unlisted, isEmpty);
      expect(result.unheaded, <String>['Something Removed']);
    });

    test('punctuation and case do not make a mismatch', () {
      expect(
        dvSpecCoverage(
          headings: <String>['Queues, Jobs, and Signals'],
          sections: <String>['Queues Jobs and Signals'],
        ).unlisted,
        isEmpty,
      );
    });

    test('but a different section is still a different section', () {
      // Nothing more aggressive than case and punctuation. Dropping words
      // would let a heading match an entry about something else, which is
      // worse than asking somebody to keep two strings the same.
      expect(
        dvSpecCoverage(
          headings: <String>['Model Sync and Presence'],
          sections: <String>['Model Sync'],
        ).unlisted,
        <String>['Model Sync and Presence'],
      );
    });
  });
}
