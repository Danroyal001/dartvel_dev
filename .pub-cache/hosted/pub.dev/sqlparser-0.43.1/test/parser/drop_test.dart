import 'package:sqlparser/sqlparser.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  test('drop index', () {
    testStatement(
      'DROP INDEX foo',
      DropStatement(type: DropType.$index, elementName: 'foo'),
    );
  });

  test('drop table', () {
    testStatement(
      'DROP TABLE IF EXISTS foo',
      DropStatement(
        type: DropType.table,
        elementName: 'foo',
        ifExists: true,
      ),
    );
  });

  test('drop view', () {
    testStatement(
      'DROP VIEW IF EXISTS foo.bar',
      DropStatement(
        type: DropType.view,
        schemaName: 'foo',
        elementName: 'bar',
        ifExists: true,
      ),
    );
  });

  test('drop trigger', () {
    testStatement(
      'DROP TRIGGER bar',
      DropStatement(type: DropType.trigger, elementName: 'bar'),
    );
  });
}
