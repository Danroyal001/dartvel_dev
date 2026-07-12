import 'package:sqlparser/src/ast/node.dart';

import 'package:sqlparser/src/ast/visitor.dart';

import '../expressions/expressions.dart';
import 'statement.dart';

/// A [`VACUUM`](https://sqlite.org/lang_vacuum.html) statement in SQL.
final class VacuumStatement extends Statement {
  String? schemaName;
  Expression? into;

  VacuumStatement({this.schemaName, this.into});

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitVacuumStatement(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => [if (into case final into?) into];

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {
    into = transformer.transformNullableChild(into, this, arg);
  }
}
