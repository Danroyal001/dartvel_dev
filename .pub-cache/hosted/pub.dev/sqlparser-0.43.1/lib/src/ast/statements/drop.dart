import '../../reader/tokenizer/token.dart';
import '../node.dart';
import '../visitor.dart';
import 'statement.dart';

enum DropType { $index, table, trigger, view }

/// A `DROP INDEX`, `DROP TABLE`, `DROP TRIGGER` or `DROP VIEW` SQL statement.
final class DropStatement extends SchemaStatement {
  final DropType type;
  Token? typeToken;

  bool ifExists;
  String? schemaName;
  String elementName;

  DropStatement({
    required this.type,
    required this.elementName,
    this.ifExists = false,
    this.schemaName,
  });

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitDropStatement(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => [];

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {}
}
