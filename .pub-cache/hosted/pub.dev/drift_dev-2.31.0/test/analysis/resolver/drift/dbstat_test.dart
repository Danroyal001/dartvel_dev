import 'package:drift_dev/src/analysis/options.dart';
import 'package:drift_dev/src/analysis/results/results.dart';
import 'package:test/test.dart';

import '../../test_utils.dart';

void main() {
  test('can select from dbstat with option', () async {
    final state = await TestBackend.inTest({
      'a|lib/main.drift': '''
a: SELECT * FROM dbstat;
'''
    }, options: DriftOptions.defaults(modules: [SqlModule.dbstat]));

    final file = await state.analyze('package:a/main.drift');
    state.expectNoErrors();

    final query =
        file.fileAnalysis!.resolvedQueries.values.single as SqlSelectQuery;
    expect(query.resultSet.columns, hasLength(10));
  });
}
