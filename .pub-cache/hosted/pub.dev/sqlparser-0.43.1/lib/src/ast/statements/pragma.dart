import '../ast.dart';

/// A [pragma](https://sqlite.org/pragma.html#syntax) command for SQLite.
final class PragmaCommand extends Statement {
  String? schemaName;
  String pragmaName;

  Expression? value;

  PragmaCommand({this.schemaName, required this.pragmaName, this.value});

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitPragmaCommand(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => [if (value case final value?) value];

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {
    value = transformer.transformNullableChild(value, this, arg);
  }
}
