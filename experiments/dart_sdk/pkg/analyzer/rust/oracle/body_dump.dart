// Resolved-body oracle using the real upstream analyzer (not a port).
// Full mode records every V1 expression's static type and identifier element.
// --literals selects context-independent literal kinds only; integers need
// downward inference and are deliberately outside that first slice.
// --operators selects expressions whose operator fixes their type (`is`,
// `is!`, `!`, `&&`, `||`, `throw`, `rethrow`) and parentheses around those
// or around --literals expressions.
// --integers selects integer literals whose context type upstream takes from a
// declared type annotation (a variable's type, a formal parameter's type for
// its default value, a function's return type, explicit collection type
// arguments) or which have no context (an expression statement, an
// interpolation); see [isDeclaredContextInteger].
// --identifiers selects reads of local variables and formal parameters
// declared with a type annotation that flow analysis cannot promote, and
// writes their declarations' element kind and name offset after the type;
// see [DeclaredVariableReads].
// --user-operators selects invocations of `==`, `!=` and the user-definable
// binary, unary (`-`, `~`) and index (`[]`) operators whose operands the
// earlier selections or this one type, resolved through the interface of the
// receiver's static type, with the integer literals that are their operands
// and the parentheses around either; see [OperatorInvocations].
// --members selects method invocations `r.m(...)` and property reads `r.p`
// (getters, fields, method tear-offs) on a known receiver whose static type is
// a non-nullable interface type, resolved through that interface, with the
// integer literals that are their arguments; see [MemberAccesses].
import 'dart:io';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/src/dart/element/extensions.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/element/type_system.dart';
import 'element_dump.dart' as elements;

Future<void> main(List<String> args) async {
  String? sdk;
  String? out;
  String? packages = Platform.packageConfig;
  bool literals = false;
  bool operators = false;
  bool integers = false;
  bool identifiers = false;
  bool userOperators = false;
  bool members = false;
  List<String> roots = [];
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--sdk': sdk = args[++i];
      case '--out': out = args[++i];
      case '--packages': packages = new File(args[++i]).absolute.uri.toString();
      case '--literals': literals = true;
      case '--operators': operators = true;
      case '--integers': integers = true;
      case '--identifiers': identifiers = true;
      case '--user-operators': userOperators = true;
      case '--members': members = true;
      default: roots.add(args[i]);
    }
  }
  if (sdk == null || out == null || packages == null || roots.isEmpty ||
      [literals, operators, integers, identifiers, userOperators, members].where((flag) => flag).length > 1) {
    stderr.writeln('usage: body_dump.dart --sdk <dir> [--literals|--operators|--integers|--identifiers|--user-operators|--members] --out <dir> <root>...');
    exit(64);
  }
  var collection = elements.newCollection(
    [for (var root in roots) new Directory(root).absolute.path],
    sdk, Uri.parse(packages).toFilePath(),
  );
  for (var (path, relative) in elements.corpusFiles(roots)) {
    var session = collection.contextFor(path).currentSession;
    var result = await session.getResolvedUnit(path);
    if (result is! ResolvedUnitResult) {
      throw new StateError('Cannot resolve $path: ${result.runtimeType}');
    }
    var buffer = new StringBuffer();
    bool isLiteral(AstNode node) => node is BooleanLiteral ||
        node is DoubleLiteral || node is NullLiteral ||
        node is SimpleStringLiteral || node is AdjacentStrings ||
        node is StringInterpolation || node is SymbolLiteral;
    bool isOperatorTyped(AstNode node) => node is IsExpression ||
        node is ThrowExpression || node is RethrowExpression ||
        (node is BinaryExpression &&
            (node.operator.type == TokenType.AMPERSAND_AMPERSAND ||
                node.operator.type == TokenType.BAR_BAR)) ||
        (node is PrefixExpression && node.operator.type == TokenType.BANG) ||
        (node is ParenthesizedExpression &&
            (isOperatorTyped(node.unParenthesized) ||
                isLiteral(node.unParenthesized)));
    var reads = identifiers || userOperators || members
        ? (DeclaredVariableReads(result.libraryElement.typeSystem)
            ..collect(result.unit as AstNodeImpl))
        : null;
    var invocations = userOperators || members
        ? (OperatorInvocations(
            result.libraryElement.typeSystem as TypeSystemImpl, reads!)
            ..collect(result.unit as AstNodeImpl))
        : null;
    var memberAccesses = members
        ? (MemberAccesses(
            result.libraryElement.typeSystem as TypeSystemImpl, invocations!)
            ..collect(result.unit as AstNodeImpl))
        : null;
    void visit(AstNodeImpl node) {
      Element? read = identifiers &&
              reads != null &&
              node is SimpleIdentifierImpl &&
              reads.selectedLength[node.offset] == node.length
          ? reads.selected[node.offset]
          : null;
      bool selected = literals ? isLiteral(node)
          : operators ? isOperatorTyped(node)
          : integers ? node is IntegerLiteralImpl && isDeclaredContextInteger(node)
          : identifiers ? read != null
          : userOperators ? invocations!.selects(node)
          : members ? memberAccesses!.selects(node)
          : true;
      if (node is Expression && selected) {
        buffer.writeln('${node.runtimeType} ${node.offset}+${node.length} '
            'type=${(node as Expression).staticType?.getDisplayString() ?? '-'}'
            '${read == null ? '' : ' element=${read.kind.name} '
                '${read.firstFragment.nameOffset}'}');
      }
      if (!literals && !operators && !integers && !identifiers &&
          !userOperators && !members && node is Identifier) {
        Element? element = (node as Identifier).element;
        var fragment = element?.firstFragment;
        buffer.writeln('identifier ${node.offset}+${node.length} '
            'element=${element == null ? '-' : '${element.kind.name} '
            '${element.library?.uri} ${fragment?.nameOffset} ${element.name}'}');
      }
      for (var child in node.namedChildEntities) {
        var value = child.value;
        if (value is AstNodeImpl) visit(value);
        if (value is List) {
          for (var item in value) {
            if (item is AstNodeImpl) visit(item);
          }
        }
      }
    }
    visit(result.unit as AstNodeImpl);
    var target = new File('$out/$relative.body');
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(buffer.toString());
  }
}

/// Whether `--integers` selects [literal], read on the V2 tree (`parent2`):
/// past a `-` whose operand it is (which passes its context on, as
/// `UnaryOperatorInvocationResolver` does) and parentheses, the literal is
/// - an expression statement or an interpolation (no context);
/// - the initializer of a variable whose declaration has a type annotation;
/// - the default value of an optional formal parameter with a type annotation
///   and no function-typed suffix, of a function, method, constructor, local
///   function or function expression;
/// - a returned expression (`return` or `=>`) of a function, method, getter,
///   operator or local function with a return type that is not a generator;
/// - an element of a list or set literal with one type argument, or a key or
///   value of a map literal with two, possibly inside `if` and `for`
///   elements.
bool isDeclaredContextInteger(IntegerLiteralImpl literal) {
  AstNode node = literal;
  var parent = node.parent2;
  if (parent is UnaryOperatorInvocationImpl &&
      parent.unaryOperator == UnaryOperator.negate &&
      identical(parent.operand, node)) {
    node = parent;
  }
  return hasDeclaredContext(node);
}

/// Whether the context type of the expression [node] comes from a declared
/// type annotation or there is none, read past enclosing parentheses: the
/// sites [isDeclaredContextInteger] lists.
bool hasDeclaredContext(AstNode node) {
  var parent = node.parent2;
  while (parent is ParenthesizedExpressionImpl) {
    node = parent;
    parent = node.parent2;
  }
  switch (parent) {
    case ExpressionStatementImpl() || InterpolationExpressionImpl():
      return true;
    case TopLevelVariable2Impl():
      return (parent.parent2 as TopLevelVariablesDeclarationImpl).type != null;
    case Field2Impl():
      return (parent.parent2 as FieldsDeclarationImpl).type != null;
    case LocalVariableImpl():
      return (parent.parent2 as LocalVariablesDeclarationImpl).type != null;
    case FormalParameterDefaultClauseImpl():
      var parameter = parent.parent2;
      if (parameter is! RegularFormalParameterImpl ||
          parameter.type == null ||
          parameter.functionTypedSuffix != null) {
        return false;
      }
      var delimited = parameter.parent2;
      if (delimited is! DelimitedFormalParametersImpl) return false;
      var executable = delimited.parent2?.parent2;
      return executable is TopLevelFunctionDeclarationImpl ||
          executable is MethodDeclaration2Impl ||
          executable is ConstructorDeclaration2Impl ||
          executable is LocalFunctionDeclarationImpl ||
          executable is FunctionExpressionImpl;
    case ReturnStatementImpl():
      AstNode? body = parent.parent2;
      while (body != null &&
          body is! FunctionBodyImpl &&
          body is! AnonymousMethodBodyImpl) {
        body = body.parent2;
      }
      return body is BlockFunctionBodyImpl && _returnsDeclaredType(body);
    case ExpressionFunctionBodyImpl():
      return _returnsDeclaredType(parent);
    case ListLiteralImpl() || SetOrMapLiteralImpl() || MapLiteralEntryImpl() ||
        IfElementImpl() || ForElementImpl():
      return _hasExplicitElementType(node, parent);
    default:
      return false;
  }
}

/// Whether [body] belongs to a declaration with a return type, other than a
/// constructor or setter, and is not a generator.
bool _returnsDeclaredType(FunctionBodyImpl body) {
  if (body.star != null) return false;
  var returnType = switch (body.parent2) {
    TopLevelFunctionDeclarationImpl(:var returnType) => returnType,
    MethodDeclaration2Impl(:var returnType) => returnType,
    LocalFunctionDeclarationImpl(:var returnType) => returnType,
    GetterDeclarationImpl(:var returnType) => returnType,
    TopLevelGetterDeclarationImpl(:var returnType) => returnType,
    OperatorDeclarationImpl(:var returnType) => returnType,
    _ => null,
  };
  return returnType != null;
}

/// Whether the collection element [element] of [parent] gets its context
/// from explicit type arguments of the enclosing literal.
bool _hasExplicitElementType(AstNode element, AstNode? parent) {
  var inMapEntry = false;
  while (true) {
    switch (parent) {
      case IfElementImpl():
        if (!identical(parent.thenElement2, element) &&
            !identical(parent.elseElement2, element)) {
          return false;
        }
      case ForElementImpl():
        if (!identical(parent.body2, element)) return false;
      case MapLiteralEntryImpl():
        if (inMapEntry) return false;
        inMapEntry = true;
      case ListLiteralImpl():
        return !inMapEntry && parent.typeArguments?.arguments.length == 1;
      case SetOrMapLiteralImpl():
        return parent.typeArguments?.arguments.length == (inMapEntry ? 2 : 1);
      default:
        return false;
    }
    element = parent!;
    parent = element.parent2;
  }
}

/// What `--identifiers` selects, read on the resolved V2 tree.
///
/// A declared variable is a local variable of a declaration with a type
/// annotation, a for-in loop variable with one, or a regular formal parameter
/// with a type annotation or a function-typed suffix (not a field or super
/// formal parameter). A read is an [UnqualifiedNameExpressionImpl] whose scope
/// lookup finds a declared variable, outside documentation comments and not the
/// name of an annotation (whose identifier has no static type).
///
/// Flow analysis may promote a variable, so a variable is left out entirely
/// when any read of it is in a position that can promote it, or when it is
/// written and its declared type is not non-nullable (an assignment of a
/// non-nullable value promotes such a variable). A position that can promote
/// is decided by tokens, past enclosing parentheses: the token after is `!`,
/// `?.`, `?..`, `is`, `as`, `==` or `!=`, or `?` followed by `[`, or `)` followed by
/// `?.` or `?..` (an extension override); or the token before is `==`, `!=` or
/// `?` (a null-aware element); or the read is an argument of `identical`; or
/// the read is the scrutinee of a switch statement
/// or expression, of an `if`-`case`, or the initializer of a pattern variable
/// declaration or pattern assignment. Writes are
/// [UnqualifiedNameAssignmentTargetImpl]s (assignments, compound assignments,
/// `++`, `--`, for-in loops over an identifier), assigned variable patterns,
/// initializers of local variables (upstream promotes `int? x = 1;` to `int`)
/// and for-in loop variables; a default value does not promote.
class DeclaredVariableReads extends UnifyingAstVisitor2<void> {
  final TypeSystem typeSystem;
  final Set<Element> declared = {};
  final List<(AstNode, Element)> reads = [];
  final List<Element> writes = [];

  /// The selected reads by offset, with the variables they read.
  final Map<int, Element> selected = {};

  /// The length of each selected read, by offset.
  final Map<int, int> selectedLength = {};

  /// The selected reads.
  final Set<AstNode> selectedNodes = {};

  new(this.typeSystem);

  void collect(AstNodeImpl unit) {
    unit.accept2(this);
    // A read may precede its declaration in the tree.
    reads.removeWhere((read) => !declared.contains(read.$2));
    writes.removeWhere((element) => !declared.contains(element));
    var excluded = <Element>{};
    for (var (node, element) in reads) {
      if (_canPromote(node)) excluded.add(element);
    }
    for (var element in writes) {
      var type = switch (element) {
        VariableElement(:var type) => type,
        _ => null,
      };
      if (type == null || !typeSystem.isNonNullable(type)) {
        excluded.add(element);
      }
    }
    for (var (node, element) in reads) {
      if (!excluded.contains(element)) {
        selected[node.offset] = element;
        selectedLength[node.offset] = node.length;
        selectedNodes.add(node);
      }
    }
  }

  @override
  void visitNode(AstNode node) {
    switch (node) {
      case CommentImpl():
        return;
      case LocalVariableImpl(:var declaredFragment?):
        if ((node.parent2 as LocalVariablesDeclarationImpl).type != null) {
          declared.add(declaredFragment.element);
        }
        // Initialization promotes as an assignment does.
        if (node.initializer != null) writes.add(declaredFragment.element);
      case DeclaredIdentifierImpl(:var declaredFragment?):
        if (node.type != null) declared.add(declaredFragment.element);
        writes.add(declaredFragment.element);
      case RegularFormalParameterImpl(:var declaredFragment?)
          when node.type != null || node.functionTypedSuffix != null:
        declared.add(declaredFragment.element);
      case UnqualifiedNameExpressionImpl(:var scopeLookupResult?)
          when node.parent2 is! AnnotationImpl:
        if (scopeLookupResult.getter case var element?) {
          reads.add((node, element));
        }
      case UnqualifiedNameAssignmentTargetImpl(:var scopeLookupResult?):
        if (scopeLookupResult.getter case var element?) writes.add(element);
      case AssignedVariablePatternImpl(:var element?):
        writes.add(element);
    }
    node.visitChildren2(this);
  }
}

bool _canPromote(AstNode read) {
  var node = read;
  while (node.parent2 is ParenthesizedExpressionImpl) {
    node = node.parent2!;
  }
  var after = node.endToken.next!;
  if (const ['!', '?.', '?..', 'is', 'as', '==', '!=']
          .contains(after.lexeme) ||
      (after.lexeme == '?' && after.next!.lexeme == '[')) {
    return true;
  }
  // `E(x)?.m`: an extension override's argument is promoted by the
  // null-aware access on it.
  if (after.lexeme == ')' &&
      const ['?.', '?..'].contains(after.next!.lexeme)) {
    return true;
  }
  // `?x` as a null-aware collection element or map key.
  if (const ['==', '!=', '?'].contains(node.beginToken.previous!.lexeme)) {
    return true;
  }
  // `identical(x, null)` is treated as `x == null`.
  if (node.parent2 case ArgumentListImpl arguments
      when arguments.beginToken.previous!.lexeme == 'identical') {
    return true;
  }
  return switch (node.parent2) {
    SwitchStatementImpl(:var expression2) ||
    SwitchExpressionImpl(:var expression2) ||
    PatternVariableDeclarationImpl(:var expression2) ||
    PatternAssignmentImpl(:var expression2) => identical(expression2, node),
    IfStatementImpl(:var expression2, :var caseClause?) ||
    IfElementImpl(:var expression2, :var caseClause?) =>
      identical(expression2, node),
    _ => false,
  };
}

/// What `--user-operators` selects, read on the resolved V2 tree.
///
/// An operator invocation is a [BinaryOperatorInvocationImpl] with a binary
/// operator (`==`, `!=` or a user-definable one), a
/// [UnaryOperatorInvocationImpl] (`-` or `~`) or a
/// [ReceiverIndexExpressionImpl] without `?`. It is selected when its receiver
/// and its argument are known and it is resolved through the interface of the
/// receiver's static type ([_isResolvable]).
///
/// Past parentheses, a known expression is a `--literals` literal, a
/// `--operators` expression, a `--identifiers` read, a selected invocation, or
/// an integer literal whose context type is known ([_hasKnownContext]): as a
/// receiver it has none; as an argument it gets the operator's parameter type
/// (`==` and `!=` give none), refined for `+`, `-`, `*` and `%` on a `num`
/// receiver by `refineNumericInvocationContext` from the invocation's own
/// context, which must then be known; an operand of unary minus gets the
/// context of the minus; and the declared contexts of
/// [isDeclaredContextInteger] are known.
///
/// Also selected: the integer literals that are operands of a selected
/// invocation (past parentheses), and parentheses around a selected
/// invocation or such a literal.
class OperatorInvocations extends UnifyingAstVisitor2<void> {
  final TypeSystemImpl typeSystem;
  final DeclaredVariableReads reads;

  /// `'$kind $offset+$length'` of each selected node; the kind is `invocation`,
  /// `integer` or `parentheses`.
  final Set<String> selected = {};

  final Map<AstNode, bool> _selectedInvocations = {};

  new(this.typeSystem, this.reads);

  void collect(AstNodeImpl unit) => unit.accept2(this);

  /// Whether the V1 node [node] projects a selected node.
  bool selects(AstNode node) {
    var kind = switch (node) {
      BinaryExpression() || PrefixExpression() || IndexExpression() =>
        'invocation',
      IntegerLiteral() => 'integer',
      ParenthesizedExpression() => 'parentheses',
      _ => null,
    };
    return kind != null &&
        selected.contains('$kind ${node.offset}+${node.length}');
  }

  @override
  void visitNode(AstNode node) {
    if (node is CommentImpl) return;
    if (_isInvocation(node) && _isSelected(node)) {
      selected.add('invocation ${node.offset}+${node.length}');
    }
    if (node is IntegerLiteralImpl && _isSelectedOperand(node)) {
      selected.add('integer ${node.offset}+${node.length}');
    }
    if (node is ParenthesizedExpressionImpl) {
      var inner = _unParenthesized(node);
      if ((_isInvocation(inner) && _isSelected(inner)) ||
          (inner is IntegerLiteralImpl && _isSelectedOperand(inner))) {
        selected.add('parentheses ${node.offset}+${node.length}');
      }
    }
    node.visitChildren2(this);
  }

  static AstNode _unParenthesized(AstNode node) {
    while (node is ParenthesizedExpressionImpl) {
      node = node.expression2;
    }
    return node;
  }

  static bool _isInvocation(AstNode node) => switch (node) {
    BinaryOperatorInvocationImpl(:var binaryOperator) => binaryOperator != null,
    UnaryOperatorInvocationImpl() => true,
    ReceiverIndexExpressionImpl(:var question) => question == null,
    _ => false,
  };

  static AstNode _receiver(AstNode invocation) => switch (invocation) {
    BinaryOperatorInvocationImpl(:var leftOperand) => leftOperand,
    UnaryOperatorInvocationImpl(:var operand) => operand,
    ReceiverIndexExpressionImpl(:var receiver) => receiver,
    _ => throw StateError('not an invocation'),
  };

  static AstNode? _argument(AstNode invocation) => switch (invocation) {
    BinaryOperatorInvocationImpl(:var rightOperand) => rightOperand,
    ReceiverIndexExpressionImpl(:var index) => index,
    _ => null,
  };

  /// The parent of the integer literal [literal] past parentheses, when it is
  /// a selected invocation.
  bool _isSelectedOperand(IntegerLiteralImpl literal) {
    AstNode? parent = literal.parent2;
    while (parent is ParenthesizedExpressionImpl) {
      parent = parent.parent2;
    }
    return parent != null && _isInvocation(parent) && _isSelected(parent);
  }

  bool _isSelected(AstNode invocation) =>
      _selectedInvocations[invocation] ??= _isResolvable(invocation) &&
          switch (_argument(invocation)) {
            null => true,
            var argument => _isKnown(argument),
          };

  bool _isKnown(AstNode node) {
    node = _unParenthesized(node);
    return switch (node) {
      BooleanLiteralImpl() || DoubleLiteralImpl() || NullLiteralImpl() ||
      SimpleStringLiteralImpl() || AdjacentStringsImpl() ||
      StringInterpolationImpl() || SymbolLiteralImpl() => true,
      IsExpressionImpl() || ThrowExpressionImpl() || RethrowExpressionImpl() ||
      LogicalAndImpl() || LogicalOrImpl() || LogicalNotImpl() => true,
      UnqualifiedNameExpressionImpl() => reads.selectedNodes.contains(node),
      IntegerLiteralImpl() => _hasKnownContext(node),
      _ => _isInvocation(node) && _isSelected(node),
    };
  }

  /// Whether the context type of [node] (an integer literal, or an
  /// invocation whose context refines the context of its argument) is known.
  bool _hasKnownContext(AstNode node) {
    var parent = node.parent2;
    if (node is IntegerLiteralImpl &&
        parent is UnaryOperatorInvocationImpl &&
        parent.unaryOperator == UnaryOperator.negate &&
        identical(parent.operand, node)) {
      node = parent;
      parent = node.parent2;
    }
    while (parent is ParenthesizedExpressionImpl) {
      node = parent;
      parent = node.parent2;
    }
    if (parent != null && _isInvocation(parent)) {
      if (identical(_receiver(parent), node)) return true;
      if (!_isResolvable(parent)) return false;
      return !_refinesContext(parent) || _hasKnownContext(parent);
    }
    return hasDeclaredContext(node);
  }

  /// Whether `refineNumericInvocationContext` replaces the parameter type of
  /// the resolvable [invocation] as the context of its argument, from the
  /// invocation's own context.
  bool _refinesContext(AstNode invocation) {
    if (invocation is! BinaryOperatorInvocationImpl) return false;
    var element = invocation.element;
    if (element == null ||
        element.enclosingElement is ExtensionElement ||
        element.enclosingElement is ExtensionTypeElement ||
        !const {'+', '-', '*', '%'}.contains(element.name)) {
      return false;
    }
    var left = (invocation.leftOperand as ExpressionImpl).staticType!;
    var numQuestion = typeSystem.typeProvider.numType
        .withNullability(NullabilitySuffix.question);
    return typeSystem.isSubtypeOf(left, numQuestion);
  }

  /// Whether the receiver of [invocation] is known and its operator resolves
  /// as far as the port resolves it: through the interface of the receiver's
  /// static type to a method with declared types, or not at all because the
  /// receiver is `dynamic`, invalid or `Never`. A receiver that may be null
  /// (but for `==` and `!=`, which promote it) and a member the interface
  /// does not have (which an extension may supply) are not resolved.
  bool _isResolvable(AstNode invocation) {
    var receiver = _receiver(invocation);
    if (receiver is! ExpressionImpl || !_isKnown(receiver)) return false;
    var type = receiver.staticType as TypeImpl;
    var bound = typeSystem.resolveToBound(type);
    bool isNever(TypeImpl type) =>
        type is NeverType && type.nullabilitySuffix == NullabilitySuffix.none;
    bool isBounded(TypeImpl type) =>
        typeSystem.isDynamicBounded(type) || typeSystem.isInvalidBounded(type);
    switch (invocation) {
      case BinaryOperatorInvocationImpl(:var binaryOperator):
        if (binaryOperator == BinaryOperator.equal) return true;
        if (binaryOperator == BinaryOperator.notEqual) {
          var element = invocation.element;
          return element == null || !element.hasImplicitReturnType;
        }
        return isNever(bound) || isBounded(type) ||
            (!_mayBeNull(type) && _isDeclared(invocation.element));
      case UnaryOperatorInvocationImpl():
        return type is DynamicType || type is InvalidType || isNever(type) ||
            isBounded(type) || isNever(bound) ||
            (!_mayBeNull(type) && _isDeclared(invocation.element));
      case ReceiverIndexExpressionImpl(:var resolution):
        var element = switch (resolution) {
          MethodIndexReadResolutionImpl(:var element) => element,
          InvalidIndexReadResolutionImpl(:var recoveryElement) =>
            recoveryElement,
          _ => null,
        };
        return isNever(bound) || bound is DynamicType || bound is VoidType ||
            bound is InvalidType ||
            (!_mayBeNull(bound) && _isDeclared(element));
    }
    return false;
  }

  /// Whether `TypePropertyResolver.resolve` treats a receiver of [type] as
  /// nullable.
  bool _mayBeNull(TypeImpl type) => type.isExtensionType
      ? type.nullabilitySuffix == NullabilitySuffix.question
      : typeSystem.isPotentiallyNullable(type);

  /// Whether [element] is a method of an interface with a declared return
  /// type and declared parameter types.
  static bool _isDeclared(MethodElement? element) =>
      element != null &&
      element.enclosingElement is InterfaceElement &&
      !element.hasImplicitReturnType &&
      !element.formalParameters.any((parameter) => parameter.hasImplicitType);
}

/// What `--members` selects, read on the resolved V2 tree.
///
/// A member access is a [ReceiverMethodInvocationImpl] (`r.m(...)`, without
/// type arguments) or a [ReceiverPropertyExtractionImpl] (`r.p`) whose
/// operator is `.` and whose name is not private (a private field may be
/// promoted by flow analysis, and private names are looked up per library).
/// It is selected when its receiver is known ([_isKnown]), the receiver's
/// static type is not nullable (`_mayBeNull` of [OperatorInvocations]) and
/// its bound is an interface type, and it resolves through that interface:
/// - an invocation to a non-generic method with declared return and
///   parameter types, other than `remainder` and `clamp` on a subtype of
///   `num?`, whose type `refineNumericInvocationType` refines from the
///   arguments;
///   (an invalid return type makes the resolution invalid, with that method
///   in the recovery);
/// - a property read to a getter with a declared return type (a field's
///   getter: a field with a declared type), or to such a method, torn off.
///
/// Past parentheses, a known receiver is what [OperatorInvocations] knows, a
/// selected member access, or an integer literal (no context: `int`).
///
/// Also selected: the integer literals that are arguments of a selected
/// invocation (past parentheses, positional or named) and that match a
/// parameter, whose type is their context.
class MemberAccesses extends UnifyingAstVisitor2<void> {
  final TypeSystemImpl typeSystem;
  final OperatorInvocations operators;

  /// `'$kind $offset+$length'` of each selected node; the kind is
  /// `invocation`, `property` or `integer`.
  final Set<String> selected = {};

  final Map<AstNode, bool> _selectedAccesses = {};

  new(this.typeSystem, this.operators);

  void collect(AstNodeImpl unit) => unit.accept2(this);

  /// Whether the V1 node [node] projects a selected node.
  bool selects(AstNode node) {
    var kind = switch (node) {
      MethodInvocation() => 'invocation',
      PrefixedIdentifier() || PropertyAccess() => 'property',
      IntegerLiteral() => 'integer',
      _ => null,
    };
    return kind != null &&
        selected.contains('$kind ${node.offset}+${node.length}');
  }

  @override
  void visitNode(AstNode node) {
    if (node is CommentImpl) return;
    if (node is ReceiverMethodInvocationImpl && _isSelected(node)) {
      selected.add('invocation ${node.offset}+${node.length}');
    }
    if (node is ReceiverPropertyExtractionImpl && _isSelected(node)) {
      selected.add('property ${node.offset}+${node.length}');
    }
    if (node is IntegerLiteralImpl && _isSelectedArgument(node)) {
      selected.add('integer ${node.offset}+${node.length}');
    }
    node.visitChildren2(this);
  }

  bool _isKnown(AstNode node) {
    node = OperatorInvocations._unParenthesized(node);
    if (node is IntegerLiteralImpl) {
      AstNode? parent = node.parent2;
      while (parent is ParenthesizedExpressionImpl) {
        parent = parent.parent2;
      }
      if (parent is ReceiverMethodInvocationImpl ||
          parent is ReceiverPropertyExtractionImpl) {
        return true;
      }
    }
    if (node is ReceiverMethodInvocationImpl ||
        node is ReceiverPropertyExtractionImpl) {
      return _isSelected(node);
    }
    return operators._isKnown(node);
  }

  bool _isSelected(AstNode access) =>
      _selectedAccesses[access] ??= _computeIsSelected(access);

  bool _computeIsSelected(AstNode access) {
    var (receiver, operator, name) = switch (access) {
      ReceiverMethodInvocationImpl(:var receiver, :var operator, :var name) =>
        (receiver, operator, name),
      ReceiverPropertyExtractionImpl(:var receiver, :var operator, :var name) =>
        (receiver, operator, name),
      _ => throw StateError('not a member access'),
    };
    if (operator.type != TokenType.PERIOD || name.lexeme.startsWith('_')) {
      return false;
    }
    if (receiver is! ExpressionImpl || !_isKnown(receiver)) return false;
    var type = receiver.staticType as TypeImpl;
    if (operators._mayBeNull(type) ||
        typeSystem.resolveToBound(type) is! InterfaceType) {
      return false;
    }
    switch (access) {
      case ReceiverMethodInvocationImpl(:var typeArguments):
        if (typeArguments != null) return false;
        var element = _invokedMethod(access);
        if (element == null) return false;
        if (element is! MethodElement ||
            !_isDeclaredMethod(element as MethodElement)) {
          return false;
        }
        var numQuestion = typeSystem.typeProvider.numType
            .withNullability(NullabilitySuffix.question);
        return !(element.enclosingElement is! ExtensionTypeElement &&
            const {'remainder', 'clamp'}.contains(element.name) &&
            typeSystem.isSubtypeOf(type, numQuestion));
      case ReceiverPropertyExtractionImpl(:var resolution):
        return switch (resolution) {
          GetterInvocationResolutionImpl(:var element) =>
            element.enclosingElement is InterfaceElement &&
                (element.isOriginVariable
                    ? !element.variable.hasImplicitType
                    : !element.hasImplicitReturnType),
          ExecutableTearOffResolutionImpl(:var element) =>
            element is MethodElement &&
                _isDeclaredMethod(element as MethodElement),
          _ => false,
        };
    }
    return false;
  }

  /// The executable [invocation] invokes: the element of its resolution, or
  /// of its recovery when the invocation's type is invalid (an invalid
  /// return type makes the resolution invalid, with the valid resolution as
  /// the recovery).
  static ExecutableElement? _invokedMethod(
      ReceiverMethodInvocationImpl invocation) {
    return switch (invocation.resolution) {
      ExecutableInvocationResolutionImpl(:var element) => element,
      InvalidInvocationResolutionImpl(
        recovery: ExecutableInvocationResolutionImpl(:var element),
      ) =>
        element,
      _ => null,
    };
  }

  /// Whether [element] is a non-generic method of an interface with a
  /// declared return type and declared parameter types.
  static bool _isDeclaredMethod(MethodElement element) =>
      element.typeParameters.isEmpty &&
      OperatorInvocations._isDeclared(element);

  /// Whether the integer literal [literal] is an argument of a selected
  /// invocation, past parentheses, that matches one of its parameters.
  bool _isSelectedArgument(IntegerLiteralImpl literal) {
    AstNode argument = literal;
    while (argument.parent2 is ParenthesizedExpressionImpl) {
      argument = argument.parent2!;
    }
    String? name;
    var parent = argument.parent2;
    if (parent is NamedArgumentImpl) {
      name = parent.name.lexeme;
      argument = parent;
      parent = parent.parent2;
    }
    if (parent is! ArgumentListImpl) return false;
    var invocation = parent.parent2;
    if (invocation is! ReceiverMethodInvocationImpl ||
        !_isSelected(invocation)) {
      return false;
    }
    var element = _invokedMethod(invocation)!;
    var parameters = element.formalParameters;
    if (name != null) {
      return parameters.any(
          (parameter) => parameter.isNamed && parameter.name == name);
    }
    var index = parent.arguments2
        .where((argument) => argument is! NamedArgumentImpl)
        .toList()
        .indexWhere((each) => identical(each, argument));
    return index <
        parameters.where((parameter) => parameter.isPositional).length;
  }
}
