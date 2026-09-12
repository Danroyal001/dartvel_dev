// The labels the specification prints, against the index that records them.
//
// Every h1 in NEW_SPEC.md carries `Stability: X · Status: Y`, and
// docs/spec-status.json records the same pair. Two places holding one fact is
// where a fact goes stale -- the Specification Status section says so about
// the agent rule files -- so tool/spec_status_check.dart compares them, and
// this is the parser it compares with.
//
// Imported by path: tool/ci/spec_coverage.dart is shared by the gates, which
// import nothing but dart: libraries so they run from a bare checkout with no
// resolved package config.
import '../../../tool/ci/spec_coverage.dart';
import 'package:test/test.dart';

void main() {
  group('labels read from the specification', () {
    test('a label under an h1 belongs to that section', () {
      const spec = '''
# Kiosk Mode

Stability: `Contract` · Status: `Designed`

Body text.

# Terminal Rendering

Stability: `Draft` · Status: `Partial`
''';

      expect(dvSpecLabels(spec), <String, DVSpecLabel>{
        'Kiosk Mode': (stability: 'Contract', status: 'Designed'),
        'Terminal Rendering': (stability: 'Draft', status: 'Partial'),
      });
    });

    test('an h2 override is not read as its parent h1 label', () {
      // Multi-Window carries its own label and so does one subsection of it.
      // Attributing the subsection's to the section would report the wrong
      // pair for the h1 and silently disagree with the index.
      const spec = '''
# Multi-Window

Stability: `Contract` · Status: `Designed`

## Window restoration

Stability: `Draft` · Status: `Designed`
''';

      expect(dvSpecLabels(spec)['Multi-Window'],
          (stability: 'Contract', status: 'Designed'));
      expect(dvSpecLabels(spec).length, 1);
    });

    test('a section with no label is absent rather than guessed at', () {
      const spec = '# UI\n\nDVBox and DVText.\n';

      expect(dvSpecLabels(spec), isEmpty);
    });

    test('a label inside a code fence is not a label', () {
      // The specification is full of samples, and one of them printing a
      // status line would otherwise label the section it sits in.
      const spec = '''
# CLI

```text
Stability: `Contract` · Status: `Shipped`
```
''';

      expect(dvSpecLabels(spec), isEmpty);
    });
  });
}
