// The site does not read as a phone framework.
//
// The owner, on the Cloud page: "dartvel is beyond iphone and android, stop
// making it look like those are the only platforms we support". And on the
// home page, which listed twelve targets while docs/build-targets.md records
// fifteen that build: the list is checked against that file, so the next
// target that builds cannot be left off it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The targets docs/build-targets.md's main table marks as building.
List<String> buildingTargets() {
  final List<String> lines = File('../../docs/build-targets.md').readAsLinesSync();
  final int header = lines.indexWhere((String l) => l.startsWith('| Target | Status | Evidence |'));
  final List<String> targets = <String>[];
  for (final String line in lines.skip(header + 2)) {
    if (!line.startsWith('|')) break;
    final List<String> cells = line.split('|');
    if (!cells[2].contains('✅')) continue;
    targets.add(RegExp('`([^`]+)`').firstMatch(cells[1])!.group(1)!);
  }
  return targets;
}

const List<String> numbers = <String>[
  'Zero', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight',
  'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen',
  'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen', 'Twenty',
];

void main() {
  test('the home page names every target that builds, and counts them', () {
    final List<String> targets = buildingTargets();
    expect(targets, contains('web-server'));
    final String home = File('lib/pages/index.dart').readAsStringSync();
    for (final String target in targets) {
      expect(home, contains("'$target',"), reason: '$target builds and is not listed');
    }
    expect(home, contains("Heading('${numbers[targets.length]} targets build today.'"));
    expect(home, contains("Figure('${targets.length}', 'targets that build')"));
  });

  test('the Cloud page leads with more than phones, and says cloud builds once', () {
    final String cloud = File('lib/pages/cloud.dart').readAsStringSync();
    expect(cloud, isNot(contains('iPhone and Android')));
    expect(cloud, isNot(contains("Eyebrow('CLOUD BUILDS')")));
    final RegExpMatch hero = RegExp(r"Heading\(\s*'([^']+)',\s*level: 1").firstMatch(cloud)!;
    final String heading = hero.group(1)!;
    final int named = <String>['Android', 'iOS', 'macOS', 'Windows', 'Linux', 'web']
        .where(heading.contains)
        .length;
    expect(named, greaterThanOrEqualTo(4), reason: heading);
  });
}
