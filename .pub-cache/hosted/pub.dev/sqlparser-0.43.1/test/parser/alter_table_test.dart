import 'package:sqlparser/sqlparser.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  test('rename', () {
    testStatement('ALTER TABLE foo RENAME TO bar',
        AlterTableStatement(TableReference('foo'), RenameTo('bar')));

    testStatement(
        'ALTER TABLE s.foo RENAME TO bar',
        AlterTableStatement(
            TableReference(schemaName: 's', 'foo'), RenameTo('bar')));
  });

  test('rename column', () {
    testStatement(
        'ALTER TABLE foo RENAME bar TO baz',
        AlterTableStatement(TableReference('foo'),
            RenameColumnTo(Reference(columnName: 'bar'), 'baz')));

    testStatement(
        'ALTER TABLE foo RENAME COLUMN bar TO baz',
        AlterTableStatement(TableReference('foo'),
            RenameColumnTo(Reference(columnName: 'bar'), 'baz')));
  });

  test('add column', () {
    testStatement(
      'ALTER TABLE foo ADD COLUMN bar TEXT',
      AlterTableStatement(
        TableReference('foo'),
        AddColumn(
          ColumnDefinition(columnName: 'bar', typeName: 'TEXT'),
        ),
      ),
    );

    testStatement(
      'ALTER TABLE foo ADD bar TEXT',
      AlterTableStatement(
        TableReference('foo'),
        AddColumn(
          ColumnDefinition(columnName: 'bar', typeName: 'TEXT'),
        ),
      ),
    );
  });

  test('add column', () {
    testStatement(
      'ALTER TABLE foo DROP bar',
      AlterTableStatement(
        TableReference('foo'),
        DropColumn(Reference(columnName: 'bar')),
      ),
    );

    testStatement(
      'ALTER TABLE foo DROP COLUMN bar',
      AlterTableStatement(
        TableReference('foo'),
        DropColumn(Reference(columnName: 'bar')),
      ),
    );
  });
}
