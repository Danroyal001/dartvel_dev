// The diagnostic codes, checked against the specification that reserves them.
//
// The codes are a published contract -- `dartvel explain` reads them and they
// never change meaning between releases -- but nothing tied the enum to the
// table that assigns them. So DV-WINDOW-006, which the specification reserves
// for "native binding missing or refused the request" at `error`, was handed to
// a display-hint miss at `warning`, and every test still passed: the code was
// well formed, it was unique among the enum's own values, and the enum had no
// idea the number already meant something else.
//
// Reading the table is the only assertion that could have caught it, so this
// reads the table.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every `DV-WINDOW-nnn` row the specification declares, code to level.
Map<String, String> specCodes() {
  final File spec = File('../../NEW_SPEC.md');
  final RegExp row = RegExp(
    r'^\|\s*`(DV-WINDOW-\d+)`\s*\|[^|]*\|\s*`([a-z]+)`',
    multiLine: true,
  );
  return <String, String>{
    for (final RegExpMatch m in row.allMatches(spec.readAsStringSync()))
      m.group(1)!: m.group(2)!,
  };
}

void main() {
  test('the specification table is readable at all', () {
    // Without this, a moved file or a changed table format would turn every
    // assertion below into a vacuous pass over an empty map.
    final Map<String, String> codes = specCodes();
    expect(codes, isNotEmpty);
    expect(codes.keys, contains('DV-WINDOW-001'));
  });

  test('every code the runtime emits is one the specification reserves', () {
    final Map<String, String> codes = specCodes();

    for (final DVWindowDegradation degradation in DVWindowDegradation.values) {
      final String? code = degradation.code;
      if (code == null) continue;
      expect(codes, contains(code),
          reason: '$degradation emits $code, which the specification does not '
              'list. Add the row, or use the code that already means this.');
    }
  });

  test('and emits it at the level the specification assigns', () {
    // The half that catches a code taken for the wrong meaning: a number
    // already spoken for usually carries a different severity, because
    // severity follows what the developer can do about it.
    final Map<String, String> codes = specCodes();

    for (final DVWindowDegradation degradation in DVWindowDegradation.values) {
      final String? code = degradation.code;
      if (code == null) continue;
      expect(degradation.level, codes[code],
          reason: '$degradation emits $code at ${degradation.level}, but the '
              'specification lists $code at ${codes[code]}');
    }
  });

  test('no two degradations share a code', () {
    final List<String> emitted = <String>[
      for (final DVWindowDegradation d in DVWindowDegradation.values)
        if (d.code != null) d.code!,
    ];
    expect(emitted.toSet(), hasLength(emitted.length));
  });

  _oneSource();

  test('every degradation but none carries a reason', () {
    for (final DVWindowDegradation degradation in DVWindowDegradation.values) {
      expect(degradation.reason, isNotEmpty);
      expect(degradation.code == null, degradation == DVWindowDegradation.none);
    }
  });
}

// One source for the text, not two.
//
// The enum carried its own hand-written reason and level while the registry
// carried the specification's. Two copies of a published contract drift, and
// the level half already had: nothing compared them, so the enum was free to
// call DV-WINDOW-006 a warning while the specification called it an error.
void _oneSource() {
  group('the enum and the registry agree', () {
    test('every degradation reads its level from the registry', () {
      for (final DVWindowDegradation degradation in DVWindowDegradation.values) {
        final String? code = degradation.code;
        if (code == null) continue;
        expect(degradation.level, DVDiagnostics.find(code)!.level,
            reason: code);
      }
    });

    test('and its reason, in the specification words', () {
      for (final DVWindowDegradation degradation in DVWindowDegradation.values) {
        final String? code = degradation.code;
        if (code == null) continue;
        expect(degradation.reason, DVDiagnostics.find(code)!.reason,
            reason: code);
      }
    });

    test('none still reads as something, since it has no code', () {
      // It is the "nothing degraded" case rather than a diagnostic, so it has
      // no registry entry to read from and must not blow up looking for one.
      expect(DVWindowDegradation.none.code, isNull);
      expect(DVWindowDegradation.none.reason, isNotEmpty);
      expect(DVWindowDegradation.none.level, isNotEmpty);
    });
  });
}
