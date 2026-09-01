// The diagnostic registry behind `dartvel explain`.
//
// The specification publishes DV-WINDOW and DV-KIOSK codes as a contract that
// never changes meaning between releases, and says `dartvel explain` reads
// them. Nothing read them: the codes existed as rows in a document and as
// string literals in a switch, with no way for a developer who found one in a
// log to look it up, and no check that the two agreed.
//
// That is how DV-WINDOW-006 came to be emitted for a display-hint miss while
// the specification reserved it for a missing native binding. A registry only
// helps if something proves it matches the document, so the last group here
// reads the document.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('looking a code up', () {
    test('a known code returns its reason and level', () {
      final DVDiagnostic? found = DVDiagnostics.find('DV-WINDOW-001');
      expect(found, isNotNull);
      expect(found!.level, 'debug');
      expect(found.reason, contains('multi-window'));
    });

    test('lookup is case-insensitive, because logs get pasted', () {
      expect(DVDiagnostics.find('dv-window-001')?.code, 'DV-WINDOW-001');
    });

    test('surrounding whitespace does not defeat it', () {
      expect(DVDiagnostics.find('  DV-WINDOW-001 ')?.code, 'DV-WINDOW-001');
    });

    test('an unknown code returns null rather than throwing', () {
      expect(DVDiagnostics.find('DV-WINDOW-999'), isNull);
      expect(DVDiagnostics.find('nonsense'), isNull);
      expect(DVDiagnostics.find(''), isNull);
    });

    test('both families are registered', () {
      expect(DVDiagnostics.find('DV-KIOSK-001'), isNotNull);
      expect(DVDiagnostics.find('DV-WINDOW-013'), isNotNull);
    });

    test('every entry carries a non-empty reason and a known level', () {
      const Set<String> levels = <String>{'debug', 'info', 'warning', 'error'};
      for (final DVDiagnostic entry in DVDiagnostics.all) {
        expect(entry.reason, isNotEmpty, reason: entry.code);
        expect(levels, contains(entry.level), reason: entry.code);
      }
    });

    test('no code is registered twice', () {
      final List<String> codes =
          DVDiagnostics.all.map((DVDiagnostic d) => d.code).toList();
      expect(codes.toSet(), hasLength(codes.length));
    });
  });

  group('searching by family', () {
    test('a family returns its codes in numeric order', () {
      final List<String> window = DVDiagnostics.family('DV-WINDOW')
          .map((DVDiagnostic d) => d.code)
          .toList();

      expect(window.first, 'DV-WINDOW-001');
      expect(window, contains('DV-WINDOW-013'));
      // Not lexicographic: '10' sorts before '2' as text, and a developer
      // reading the list would see them out of order.
      expect(window.indexOf('DV-WINDOW-002'),
          lessThan(window.indexOf('DV-WINDOW-010')));
    });

    test('an unknown family is empty, not an error', () {
      expect(DVDiagnostics.family('DV-NOTHING'), isEmpty);
    });
  });

  group('against the specification', () {
    // The registry is only worth having if it says what the document says.
    final File spec = File('../../NEW_SPEC.md');

    Map<String, ({String reason, String level})> rows() {
      final RegExp row = RegExp(
        r'^\|\s*`(DV-[A-Z]+-\d+)`\s*\|\s*(.+?)\s*\|\s*`([a-z]+)`',
        multiLine: true,
      );
      return <String, ({String reason, String level})>{
        for (final RegExpMatch m in row.allMatches(spec.readAsStringSync()))
          m.group(1)!: (reason: m.group(2)!, level: m.group(3)!),
      };
    }

    test('the table is readable at all', () {
      // Without this, a moved file or a reformatted table would turn every
      // assertion below into a vacuous pass over an empty map.
      expect(spec.existsSync(), isTrue);
      expect(rows(), isNotEmpty);
      expect(rows().keys, contains('DV-WINDOW-001'));
    });

    test('every code the specification lists is registered', () {
      for (final String code in rows().keys) {
        expect(DVDiagnostics.find(code), isNotNull,
            reason: 'the specification lists $code and the registry does not');
      }
    });

    test('and no code is registered that the specification does not list', () {
      final Map<String, ({String reason, String level})> table = rows();
      for (final DVDiagnostic entry in DVDiagnostics.all) {
        expect(table, contains(entry.code),
            reason: '${entry.code} is registered but the specification does '
                'not list it');
      }
    });

    test('at the level the specification assigns', () {
      // The half that catches a code taken for the wrong meaning: a number
      // already spoken for usually carries a different severity.
      rows().forEach((String code, ({String reason, String level}) row) {
        expect(DVDiagnostics.find(code)!.level, row.level, reason: code);
      });
    });
  });
}
