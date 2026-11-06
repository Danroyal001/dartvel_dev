import 'dart:io';

import 'package:rust_stack_phase0/components.dart';
import 'package:rust_stack_phase0/line_count.dart';
import 'package:rust_stack_phase0/report.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('rust_stack_report_'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String path, String text) {
    File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  test('a language filter keeps API-surface Dart out of a C++ component', () {
    write('engine/lib/ui/painting.cc', 'a\nb\n');
    write('engine/lib/ui/painting.dart', 'x\ny\nz\n');

    final count = measure(
      const Component(
        name: 'engine natives',
        roots: ['engine/lib/ui'],
        languages: {Language.cpp, Language.objc},
      ),
      root,
    );

    expect(count.implementation, 2);
    expect(count.byLanguage.containsKey(Language.dart), isFalse);
  });

  test('a subset row is reported but never added to the total', () {
    final vm = Count(const Component(name: 'VM', roots: ['vm']))
      ..implementation = 10
      ..tests = 4;
    final backEnds =
        Count(
            const Component(
              name: 'back ends',
              roots: ['vm/compiler'],
              partOf: 'VM',
            ),
          )
          ..implementation = 6
          ..tests = 1;
    final cfe = Count(const Component(name: 'CFE', roots: ['pkg/front_end']))
      ..implementation = 3
      ..tests = 2;

    final totals = portedTotals([vm, backEnds, cfe]);

    expect(totals.implementation, 13);
    expect(totals.tests, 6);
  });

  test('components kept as API surface are not in the ported total', () {
    final framework = Count(
      const Component(
        name: 'Flutter framework',
        roots: ['packages/flutter'],
        ported: false,
      ),
    )..implementation = 100;
    final tools = Count(
      const Component(name: 'flutter_tools', roots: ['packages/flutter_tools']),
    )..implementation = 7;

    expect(portedTotals([framework, tools]).implementation, 7);
  });

  test('a row kept as API surface is sized by its implementation, as Part 2 '
      'sizes the framework, not with its tests added', () {
    final framework =
        Count(
            const Component(
              name: 'Flutter framework',
              roots: ['packages/flutter'],
              ported: false,
            ),
          )
          ..implementation = 571000
          ..tests = 690000
          ..byLanguage[Language.dart] = 1261000;

    expect(
      markdownTable([framework]),
      contains('| Flutter framework | Dart | 571k |'),
    );
  });

  test('Dart-only rows in the manifest do not pick up template C++', () {
    for (final name in ['flutter CLI', 'Flutter framework']) {
      final component = part2Components.singleWhere((c) => c.name == name);
      expect(component.languages, {Language.dart}, reason: name);
    }
  });

  test('the markdown table rounds to thousands the way Part 2 prints them', () {
    final count = Count(const Component(name: 'Analyzer', roots: ['a']))
      ..implementation = 291400
      ..tests = 1112600
      ..byLanguage[Language.dart] = 1404000;

    final table = markdownTable([count]);

    expect(table, contains('| Analyzer | Dart | 291k | 1,113k |'));
    expect(table, contains('| **Total ported** | | **291k** | **1,113k** |'));
  });

  test(
    'the shipped manifest names every Part 2 row once, against a checkout',
    () {
      final names = [for (final c in part2Components) c.name];
      expect(names.toSet().length, names.length);
      for (final component in part2Components) {
        expect(
          checkouts.containsKey(component.checkout),
          isTrue,
          reason: '${component.name} names checkout ${component.checkout}',
        );
        expect(component.roots, isNotEmpty, reason: component.name);
      }
      expect(
        part2Components.where((c) => c.partOf != null).map((c) => c.partOf),
        everyElement(isIn(names)),
      );
    },
  );
}
