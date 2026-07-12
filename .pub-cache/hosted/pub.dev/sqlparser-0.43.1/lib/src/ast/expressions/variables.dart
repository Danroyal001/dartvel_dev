part of '../ast.dart';

abstract class Variable extends Expression implements InExpressionTarget {
  int? resolvedIndex;
}

/// A "?" or "?123" variable placeholder
class NumberedVariable extends Expression implements Variable {
  QuestionMarkVariableToken? token;

  int? explicitIndex;

  @override
  int? resolvedIndex;

  NumberedVariable(this.explicitIndex) : resolvedIndex = explicitIndex;

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitNumberedVariable(this, arg);
  }

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {}

  @override
  Iterable<AstNode> get childNodes => const [];
}

class NamedVariable extends Expression implements Variable {
  final String name;

  /// The [name] plus a variable prefix (e.g. `:user`)
  final String fullName;

  @override
  int? resolvedIndex;

  NamedVariable.synthetic(String prefix, this.name) : fullName = '$prefix$name';

  NamedVariable(NamedVariableToken token)
      : fullName = token.fullName,
        name = token.name;

  @override
  R accept<A, R>(AstVisitor<A, R> visitor, A arg) {
    return visitor.visitNamedVariable(this, arg);
  }

  @override
  void transformChildren<A>(Transformer<A> transformer, A arg) {}

  @override
  Iterable<AstNode> get childNodes => [];
}
