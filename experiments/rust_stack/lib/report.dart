/// Turning counts into the proposal's Part 2 table and a JSON record.
library;

import 'dart:convert';

import 'line_count.dart';

final class Totals {
  int implementation = 0;
  int tests = 0;
}

/// The "Total ported" row: ported components only, breakdown rows left out
/// because their parent row already counts them.
Totals portedTotals(Iterable<Count> counts) {
  final totals = Totals();
  for (final count in counts) {
    if (!count.component.ported || count.component.partOf != null) continue;
    totals.implementation += count.implementation;
    totals.tests += count.tests;
  }
  return totals;
}

/// Thousands, rounded, with separators: 1112600 is `1,113k`.
String thousands(int lines) {
  final digits = (lines / 1000).round().toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return '${grouped}k';
}

const _languageNames = {
  Language.dart: 'Dart',
  Language.cpp: 'C++',
  Language.objc: 'ObjC++',
};

String _languages(Count count) => [
  for (final language in Language.values)
    if ((count.byLanguage[language] ?? 0) > 0) _languageNames[language]!,
].join(', ');

/// The ported rows as Part 2 prints them, then the rows kept as API surface.
String markdownTable(List<Count> counts) {
  final out = StringBuffer()
    ..writeln('| Component | Language | Implementation | Tests |')
    ..writeln('|---|---|---|---|');
  for (final count in counts.where((c) => c.component.ported)) {
    final name = count.component.partOf == null
        ? count.component.name
        : '...of which ${count.component.name}';
    out.writeln(
      '| $name | ${_languages(count)} | '
      '${thousands(count.implementation)} | ${thousands(count.tests)} |',
    );
  }
  final totals = portedTotals(counts);
  out.writeln(
    '| **Total ported** | | **${thousands(totals.implementation)}** '
    '| **${thousands(totals.tests)}** |',
  );

  final kept = counts.where((c) => !c.component.ported).toList();
  if (kept.isNotEmpty) {
    out
      ..writeln()
      ..writeln('| Stays as it is | Language | Size |')
      ..writeln('|---|---|---|');
    for (final count in kept) {
      out.writeln(
        '| ${count.component.name} | ${_languages(count)} | '
        '${thousands(count.implementation)} |',
      );
    }
  }
  return out.toString();
}

/// Exact numbers, for the baseline file a later measurement is compared to.
String jsonReport(List<Count> counts, Map<String, String> pins) =>
    const JsonEncoder.withIndent('  ').convert({
      'pins': pins,
      'components': [
        for (final count in counts)
          {
            'name': count.component.name,
            'checkout': count.component.checkout,
            'roots': count.component.roots,
            'ported': count.component.ported,
            if (count.component.partOf != null)
              'partOf': count.component.partOf,
            'implementation': count.implementation,
            'tests': count.tests,
            'byLanguage': {
              for (final entry in count.byLanguage.entries)
                entry.key.name: entry.value,
            },
          },
      ],
      'totalPorted': {
        'implementation': portedTotals(counts).implementation,
        'tests': portedTotals(counts).tests,
      },
    });
