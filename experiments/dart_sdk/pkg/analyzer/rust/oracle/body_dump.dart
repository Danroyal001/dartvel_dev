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
import 'dart:io';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'element_dump.dart' as elements;

Future<void> main(List<String> args) async {
  String? sdk;
  String? out;
  String? packages = Platform.packageConfig;
  bool literals = false;
  bool operators = false;
  bool integers = false;
  bool identifiers = false;
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
      default: roots.add(args[i]);
    }
  }
  if (sdk == null || out == null || packages == null || roots.isEmpty ||
      [literals, operators, integers, identifiers].where((flag) => flag).length > 1) {
    stderr.writeln('usage: body_dump.dart --sdk <dir> [--literals|--operators|--integers|--identifiers] --out <dir> <root>...');
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
    var reads = identifiers
        ? (DeclaredVariableReads(result.libraryElement.typeSystem)
            ..collect(result.unit as AstNodeImpl))
        : null;
    void visit(AstNodeImpl node) {
      Element? read = reads != null &&
              node is SimpleIdentifierImpl &&
              reads.selectedLength[node.offset] == node.length
          ? reads.selected[node.offset]
          : null;
      bool selected = literals ? isLiteral(node)
          : operators ? isOperatorTyped(node)
          : integers ? node is IntegerLiteralImpl && isDeclaredContextInteger(node)
          : identifiers ? read != null
          : true;
      if (node is Expression && selected) {
        buffer.writeln('${node.runtimeType} ${node.offset}+${node.length} '
            'type=${(node as Expression).staticType?.getDisplayString() ?? '-'}'
            '${read == null ? '' : ' element=${read.kind.name} '
                '${read.firstFragment.nameOffset}'}');
      }
      if (!literals && !operators && !integers && !identifiers &&
          node is Identifier) {
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
    parent = node.parent2;
  }
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
