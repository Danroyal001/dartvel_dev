import '../node.dart';
import '../visitor.dart';
import 'statement.dart';

/// An [`ANALYZE`](https://sqlite.org/lang_analyze.html) statement in SQL.
final class AnalyzeStatement extends Statement {
  String? schemaName;
  String? elementName;

  AnalyzeStatement({this.schemaName, this.elementName});

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitAnalyzeStatement(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => const [];

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {}
}
