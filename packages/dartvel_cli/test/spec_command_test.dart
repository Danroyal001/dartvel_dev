// `dartvel spec status`, which the CLI's own gap list named as missing.
//
// The check itself has existed for a while as tool/spec_status_check.dart and
// runs in CI. It was not reachable from the CLI, so a developer had to know
// the script's path to run the thing that decides whether the status index is
// honest -- and the spec lists `dartvel spec status` among the commands.
import 'package:dartvel_cli/src/build/spec_status.dart';
import 'package:test/test.dart';

void main() {
  group('the status summary', () {
    const index = <Map<String, Object?>>[
      <String, Object?>{'section': 'A', 'status': 'Shipped', 'stability': 'Contract'},
      <String, Object?>{'section': 'B', 'status': 'Partial', 'stability': 'Contract'},
      <String, Object?>{'section': 'C', 'status': 'Partial', 'stability': 'Draft'},
      <String, Object?>{'section': 'D', 'status': 'Designed', 'stability': 'Draft'},
      <String, Object?>{'section': 'E', 'kind': 'narrative'},
    ];

    test('counts each status', () {
      final summary = specStatusSummary(index);

      expect(summary.shipped, 1);
      expect(summary.partial, 2);
      expect(summary.designed, 1);
    });

    test('an unlabelled section is not counted as anything', () {
      // A narrative heading is not an unbuilt feature, and counting it as one
      // would make the totals argue for work that does not exist.
      final summary = specStatusSummary(index);

      expect(summary.labelled, 4);
      expect(summary.total, 5);
    });

    test('it names the contracts that are not built', () {
      // The number worth surfacing. A frozen contract that is deliberately
      // unbuilt is the scope rule working; fourteen of them is a decision
      // someone should be making on purpose.
      final summary = specStatusSummary(index);

      expect(summary.unbuiltContracts, <String>['B']);
    });

    test('a Draft that is Partial is not a contract gap', () {
      final summary = specStatusSummary(index);

      expect(summary.unbuiltContracts, isNot(contains('C')));
    });
  });
}
