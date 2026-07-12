import '../expressions/expressions.dart';
import '../node.dart';
import '../visitor.dart';
import 'statement.dart';

/// An [`ATTACH`](https://sqlite.org/lang_attach.html) statement.
final class AttachStatement extends Statement {
  Expression path;
  String as;

  AttachStatement({required this.path, required this.as});

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitAttachStatement(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => [path];

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {
    path = transformer.transformChild(path, this, arg);
  }
}

/// A [`DETACH`](https://sqlite.org/lang_detach.html) statement.
final class DetachStatement extends Statement {
  String schemaName;

  DetachStatement(this.schemaName);

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitDetachStatement(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => [];

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {}
}
