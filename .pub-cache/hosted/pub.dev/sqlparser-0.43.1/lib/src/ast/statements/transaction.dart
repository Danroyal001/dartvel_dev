import '../../reader/tokenizer/token.dart';
import '../node.dart';
import '../visitor.dart';
import 'statement.dart';

enum TransactionMode { none, deferred, immediate, exclusive }

final class BeginTransactionStatement extends Statement {
  Token? begin, modeToken, transaction;

  final TransactionMode mode;

  BeginTransactionStatement([this.mode = TransactionMode.none]);

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitBeginTransaction(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => const Iterable.empty();

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {}
}

final class CommitStatement extends Statement {
  Token? commitOrEnd, transaction;

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitCommitStatement(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => const Iterable.empty();

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {}
}

final class RollbackStatement extends Statement {
  String? toSavepoint;

  RollbackStatement({this.toSavepoint});

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitRollbackStatement(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => const [];

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {}
}

/// A [savepoint statement](https://sqlite.org/lang_savepoint.html) marking a
/// state that transactions can be rolled back to.
final class SavepointStatement extends Statement {
  String savepointName;

  SavepointStatement(this.savepointName);

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitSavepointStatement(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => const [];

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {}
}

/// A [release statement](https://sqlite.org/lang_savepoint.html) releasing a
/// savepoint.

final class ReleaseStatement extends Statement {
  String savepointName;

  ReleaseStatement(this.savepointName);

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitReleaseStatement(this, arg);
  }

  @override
  Iterable<AstNode> get childNodes => const [];

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {}
}
