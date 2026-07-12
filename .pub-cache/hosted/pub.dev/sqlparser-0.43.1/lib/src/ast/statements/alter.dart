import '../../reader/tokenizer/token.dart';
import '../ast.dart';

/// An `ALTER TABLE` statement in SQLite.
final class AlterTableStatement extends Statement {
  TableReference table;
  AlterTableInstruction instruction;

  AlterTableStatement(this.table, this.instruction);

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitAlterTableStatement(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => [table, instruction];

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {
    table = transformer.transformChild(table, this, arg);
    instruction = transformer.transformChild(instruction, this, arg);
  }
}

/// An instruction to run as part of an [AlterTableStatement].
sealed class AlterTableInstruction extends AstNode {}

final class RenameTo extends AlterTableInstruction {
  String newTableName;
  Token? newTableNameToken;

  RenameTo(this.newTableName);

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitRenameTo(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => const [];

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {}
}

final class RenameColumnTo extends AlterTableInstruction {
  Reference oldName;
  String newName;
  Token? newNameToken;

  RenameColumnTo(this.oldName, this.newName);

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitRenameColumnTo(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => [oldName];

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {
    oldName = transformer.transformChild(oldName, this, arg);
  }
}

final class AddColumn extends AlterTableInstruction {
  ColumnDefinition definition;

  AddColumn(this.definition);

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitAddColumn(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => [definition];

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {
    definition = transformer.transformChild(definition, this, arg);
  }
}

final class DropColumn extends AlterTableInstruction {
  Reference column;

  DropColumn(this.column);

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitDropColumn(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => [column];

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {
    column = transformer.transformChild(column, this, arg);
  }
}
