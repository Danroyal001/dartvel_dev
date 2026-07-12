import 'package:sqlparser/sqlparser.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  test('iif requires three arguments on old sqlite versions', () {
    final engine = SqlEngine();
    final result = engine.analyze('SELECT iif (0, 1)');

    expect(result.errors, [
      analysisErrorWith(
          lexeme: '0, 1',
          type: AnalysisErrorType.invalidAmountOfParameters,
          message:
              'iif expects 3 arguments (2 are allowed since 3.48), got 2.'),
    ]);
  });

  test('iif supports two arguments starting with sqlite 3.48', () {
    final engine = SqlEngine(EngineOptions(version: SqliteVersion.v3_48));
    final result = engine.analyze('SELECT iif (0, 1)');

    expect(result.errors, isEmpty);
  });

  test('sum', () {
    final engine = SqlEngine();
    final result = engine.analyze('SELECT sum(1, 2, 3)');

    result.expectError(
      '1, 2, 3',
      type: AnalysisErrorType.invalidAmountOfParameters,
    );
  });
}
