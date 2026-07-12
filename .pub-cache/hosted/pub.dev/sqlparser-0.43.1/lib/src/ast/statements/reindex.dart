import '../node.dart';
import '../visitor.dart';
import 'statement.dart';

/// A [`REINDEX`](https://sqlite.org/lang_reindex.html) statement.
final class ReindexStatement extends Statement {
  String? schemaName;
  String elementName;

  ReindexStatement({required this.elementName, this.schemaName});

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitReindexStatement(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => [];

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {}
}
