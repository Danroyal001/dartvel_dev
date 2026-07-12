import 'package:sqlparser/sqlparser.dart';

/// A transformer adding explicit aliases to columns in a projection.
///
/// In sqlite3, the result name of columns without an alias is undefined. While
/// the names of direct column references (`SELECT foo FROM bar`) is unlikely
/// to change, we shouldn't assume that for more complex columns (`SELECT
/// MAX(id) * 14 FROM bar`). This transformer adds an alias to such columns
/// which avoids undefined behavior that might be different across sqlite3
/// versions.
///
/// In drift3, we only reference columns by their index. This transformer
/// optimizes queries for that, by:
///   - Removing column aliases on the top-level query.
///   - Expanding `*` columns (ensuring that schema mismatches don't invalidate
///     query indexes).
class ExplicitAliasTransformer extends Transformer<bool> {
  int _aliasCounter = 0;
  final Map<Expression, String> _renamed = {};
  final Map<ResultSetAvailableInStatement, String> _renamedResultSets = {};

  final bool _drift3Mode;
  AstNode? _root;

  ExplicitAliasTransformer({bool drift3Mode = false})
      : _drift3Mode = drift3Mode;

  /// Rewrites an SQL [node] to use explicit aliases for columns.
  AstNode rewrite(AstNode node) {
    _root = node;
    node = transform(node, !_drift3Mode)!;
    _root = null;
    return _PatchReferences(this).transform(node, null)!;
  }

  /// Obtain the new name for a [column] after an alias has been added.
  String? newNameFor(Column column) {
    while (column is CompoundSelectColumn) {
      // In compound select statement, the first column determines the overall
      // name
      column = column.columns.first;
    }

    if (column is ExpressionColumn) {
      return _renamed[column.expression];
    }

    return null;
  }

  @override
  AstNode? visitCommonTableExpression(CommonTableExpression e, bool arg) {
    // No need to add explicit column names when they're defined in the CTE
    // definition.
    e.as = transformChild(e.as, e, arg && e.columnNames == null);
    return e;
  }

  @override
  AstNode? visitCompoundSelectStatement(CompoundSelectStatement e, bool arg) {
    // For compound select statements, the column names are only determined by
    // the base select statement. So, let's not transform the names in the other
    // select statements.
    e.withClause = transformNullableChild(e.withClause, e, arg);
    e.base = transformChild(e.base, e, arg);
    e.additional = transformChildren(e.additional, e, false);
    return e;
  }

  @override
  AstNode? visitExpressionResultColumn(ExpressionResultColumn e, bool arg) {
    final expr = e.expression;
    if (expr is! Reference && e.as == null && arg) {
      // Automatically add an alias to column names
      final name = '_c${_aliasCounter++}';
      _renamed[expr] = name;
      return super.visitExpressionResultColumn(
        ExpressionResultColumn(expression: expr, as: name),
        arg,
      );
    } else {
      return super.visitExpressionResultColumn(e, arg);
    }
  }

  @override
  AstNode? visitSelectStatement(SelectStatement e, bool arg) {
    e.withClause = transformNullableChild(e.withClause, e, arg);

    // If we're in drift3 mode, expand * columns. The reason is that we'll try
    // to read columns by their index at runtime, and we want to be defensive
    // against the case of a schema mismatch introducing columns we don't know.
    if (_drift3Mode && e == _root) {
      for (var i = 0; i < e.columns.length; i++) {
        final originalColumn = e.columns[i];
        final expanded = originalColumn.resolvedColumns;

        if (originalColumn is StarResultColumn && expanded != null) {
          e.columns.removeAt(i);
          var added = 0;

          for (final column in expanded) {
            if (column is AvailableColumn) {
              final alias = column.source.alias ??
                  _renamedResultSets.putIfAbsent(column.source, () {
                    return '_s:${_renamedResultSets.length}';
                  });

              e.columns.insert(
                i + added,
                ExpressionResultColumn(
                  expression: Reference(
                    columnName: column.name,
                    entityName: alias,
                  )..resolved = column,
                ),
              );
              added += 1;
            } else {
              throw ArgumentError(
                  'Internal error: Unhandled column type $column');
            }
          }

          i += added - 1; // -1 because we've removed the original node
        }
      }
    }

    e.columns = transformChildren(e.columns, e, arg);
    // arg is going to be false in drift3 mode for the root statement. We still
    // want to introduce explicit aliases in select statements appearing in the
    // FROM clause to ensure the references we've just introduced to expand star
    // columns are valid.
    e.from =
        transformNullableChild(e.from, e, arg || (_drift3Mode && e == _root));
    e.where = transformNullableChild(e.where, e, arg);
    e.groupBy = transformNullableChild(e.groupBy, e, arg);
    e.limit = transformNullableChild(e.limit, e, arg);
    e.orderBy = transformNullableChild(e.orderBy, e, arg);
    return e;
  }

  @override
  AstNode? visitSubQuery(SubQuery e, bool arg) {
    // Subquery expressions only have a single column, so the inner column
    // doesn't matter. For instance, `SELECT (SELECT 1) AS foo` has no undefined
    // behavior, even though the inner `1` has no alias.
    return e..transformChildren(this, false);
  }

  @override
  AstNode? visitTableReference(TableReference e, bool arg) {
    if (_renamedResultSets[e.availableResultSet] case final newName?) {
      e.as = newName;
    }

    return super.visitTableReference(e, arg);
  }

  @override
  AstNode? visitTableValuedFunction(TableValuedFunction e, bool arg) {
    if (_renamedResultSets[e.availableResultSet] case final newName?) {
      e.as = newName;
    }

    return super.visitTableValuedFunction(e, arg);
  }

  @override
  AstNode? visitSelectStatementAsSource(SelectStatementAsSource e, bool arg) {
    if (_renamedResultSets[e.availableResultSet] case final newName?) {
      e.as = newName;
    }

    return super.visitSelectStatementAsSource(e, arg);
  }
}

class _PatchReferences extends Transformer<void> {
  final ExplicitAliasTransformer _transformer;

  _PatchReferences(this._transformer);

  @override
  AstNode? visitReference(Reference e, void arg) {
    final column = e.resolvedColumn;
    var columnName = e.columnName;
    var entityName = e.entityName;

    if (column is AvailableColumn) {
      if (_transformer._renamedResultSets[column.source] case final newName?) {
        entityName = newName;
      }
    }

    final resolved = column?.source;
    if (resolved != null) {
      columnName = _transformer.newNameFor(resolved) ?? columnName;
    }

    if (columnName != e.columnName || entityName != e.entityName) {
      return Reference(columnName: columnName, entityName: entityName);
    }
    return e;
  }
}
