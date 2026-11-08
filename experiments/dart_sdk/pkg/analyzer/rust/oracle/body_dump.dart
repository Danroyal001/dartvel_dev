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
import 'dart:io';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'element_dump.dart' as elements;

Future<void> main(List<String> args) async {
  String? sdk;
  String? out;
  String? packages = Platform.packageConfig;
  bool literals = false;
  bool operators = false;
  bool integers = false;
  List<String> roots = [];
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--sdk': sdk = args[++i];
      case '--out': out = args[++i];
      case '--packages': packages = new File(args[++i]).absolute.uri.toString();
      case '--literals': literals = true;
      case '--operators': operators = true;
      case '--integers': integers = true;
      default: roots.add(args[i]);
    }
  }
  if (sdk == null || out == null || packages == null || roots.isEmpty ||
      [literals, operators, integers].where((flag) => flag).length > 1) {
    stderr.writeln('usage: body_dump.dart --sdk <dir> [--literals|--operators|--integers] --out <dir> <root>...');
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
    void visit(AstNodeImpl node) {
      bool selected = literals ? isLiteral(node)
          : operators ? isOperatorTyped(node)
          : integers ? node is IntegerLiteralImpl && isDeclaredContextInteger(node)
          : true;
      if (node is Expression && selected) {
        buffer.writeln('${node.runtimeType} ${node.offset}+${node.length} '
            'type=${(node as Expression).staticType?.getDisplayString() ?? '-'}');
      }
      if (!literals && !operators && !integers && node is Identifier) {
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
