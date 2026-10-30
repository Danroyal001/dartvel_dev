// Generates src/dart/ast/ast.rs, the Rust port of lib/src/dart/ast/ast.dart
// (see ../README.md).
//
// Upstream generates most of every node class from its constructor and its
// `@GenerateNodeImpl` annotation (the members marked `@generated`): the
// fields, `beginToken`, `endToken` and the named child entities. This
// program reads ast.dart with the analyzer itself and writes the same
// members in Rust for every node class the AstBuilder can build (the "V2"
// and shared classes): a struct per class, holding the constructor's
// parameters as fields, and `AstNodeImpl`, the enum of all of them.
// `beginToken`, `endToken` and `_childEntities2` are translated from their
// Dart bodies when they have one of the generated shapes; the few that are
// written by hand upstream are in [handBodies], translated by hand.
//
// Run it again when ast.dart changes:
//   dart --packages=<package_config.json> \
//     pkg/analyzer/rust/oracle/generate_ast.dart \
//     pkg/analyzer/lib/src/dart/ast/ast.dart pkg/analyzer/rust/src/src/dart/ast/ast.rs
//
// It fails, naming the member, when a body has a shape it cannot translate
// and no hand translation.

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// Hand translations of members upstream writes by hand, keyed by
/// `<class>.<member>`. `self` is the node's struct, `ast` the `AstStore` and
/// `tokens` the `TokenStore`.
const Map<String, String> handBodies = {
  '_AnnotatedNodeMixin.beginToken': '''
let first = tokens.lexically_first(&[
            if self.documentation_comment != NO_NODE {
                ast.begin_token(self.documentation_comment, tokens)
            } else {
                NO_TOKEN
            },
            ast.node_list_begin_token(&self.metadata, tokens),
        ]);
        if first != NO_TOKEN {
            return first;
        }
        self.first_token_after_comment_and_metadata(ast, tokens)''',
  'CommentImpl.beginToken': 'self.tokens[0]',
  'CommentImpl.endToken': 'self.tokens[self.tokens.len() - 1]',
  // Inherited only by the three classes with an `operand`, which is where the
  // loop starts after its first iteration.
  'ParsedExpressionImpl.beginToken': '''
let mut node = self.operand;
        loop {
            match ast.node(node) {
                AstNodeImpl::ParsedCascadeNameImpl(n) => return n.name,
                AstNodeImpl::ParsedUnqualifiedNameImpl(n) => return n.name,
                AstNodeImpl::ParsedDotShorthandNameImpl(n) => return n.period,
                AstNodeImpl::ParsedNameAccessImpl(n) => node = n.operand,
                AstNodeImpl::ParsedTypeArgumentsImpl(n) => node = n.operand,
                AstNodeImpl::ParsedValueArgumentsImpl(n) => node = n.operand,
                _ => return ast.begin_token(node, tokens),
            }
        }''',
  'IncrementOrDecrementExpressionImpl.beginToken': '''
match self.position {
            IncrementOrDecrementPosition::prefix => self.operator_,
            IncrementOrDecrementPosition::postfix => ast.begin_token(self.target, tokens),
        }''',
  'IncrementOrDecrementExpressionImpl.endToken': '''
match self.position {
            IncrementOrDecrementPosition::prefix => ast.end_token(self.target, tokens),
            IncrementOrDecrementPosition::postfix => self.operator_,
        }''',
};

/// Hand translations of `_childEntities2` bodies: Rust statements adding
/// to `entities`.
const Map<String, String> handChildren = {
  // Upstream first throws for a V1 projection, which is never built here.
  'FunctionExpressionImpl': '''
entities.add_node("typeParameters", self.type_parameters);
        entities.add_node("parameters", self.parameters);
        entities.add_node("body", self.body);''',
  'CascadeSectionImpl': '''
// _bodyIncludesOperator
        if !(ast.begin_token(self.body, tokens) == self.operator_) {
            entities.add_token("operator", self.operator_);
        }
        entities.add_node("body", self.body);''',
  // Upstream first throws when the node was made from a constructor type
  // reference, which only the V1 view does.
  'NamedTypeImpl': '''
entities.add_node("importPrefix", self.import_prefix);
        entities.add_token("name", self.name);
        entities.add_node("typeArguments", self.type_arguments);
        entities.add_token("question", self.question);''',
  'IncrementOrDecrementExpressionImpl': '''
match self.position {
            IncrementOrDecrementPosition::prefix => {
                entities.add_token("operator", self.operator_);
                entities.add_node("target", self.target);
            }
            IncrementOrDecrementPosition::postfix => {
                entities.add_node("target", self.target);
                entities.add_token("operator", self.operator_);
            }
        }''',
};

/// Types of fields that hold resolution results, which parsing leaves
/// null; the port does not store them.
const Set<String> resolutionTypes = {
  'Fragment',
  'Fragment?',
  'ExtensionElementImpl',
  'ExtensionElementImpl?',
  'MethodElement',
  'MethodElement?',
};

late CompilationUnit unit;
final Map<String, ClassInfo> classes = {};

class ClassInfo {
  final String name;
  final bool isAbstract;
  final bool isMixin;
  final String? superclass;
  final List<String> mixins;
  final List<String> interfaces;
  final List<ClassMember> members;

  new(
    this.name, {
    required this.isAbstract,
    required this.isMixin,
    required this.superclass,
    required this.mixins,
    required this.interfaces,
    required this.members,
  });

  /// The supertypes, nearest first in Dart's lookup order: the mixins (last
  /// one first), then the superclass and its own chain.
  Iterable<ClassInfo> get lookupChain sync* {
    yield this;
    for (String mixin in mixins.reversed) {
      ClassInfo? info = classes[mixin];
      if (info != null) yield* info.lookupChain;
    }
    if (superclass != null) {
      ClassInfo? info = classes[superclass];
      if (info != null) yield* info.lookupChain;
    }
  }

  Set<String> get allSupertypes {
    Set<String> result = {name};
    for (String s in [?superclass, ...mixins, ...interfaces]) {
      ClassInfo? info = classes[s];
      if (info != null) {
        result.addAll(info.allSupertypes);
      } else {
        result.add(s);
      }
    }
    return result;
  }

  ConstructorDeclaration? get unnamedConstructor {
    for (ClassMember m in members) {
      if (m is ConstructorDeclaration && m.name == null) return m;
    }
    return null;
  }

  /// The declared type of the field [fieldName], in this class or a
  /// supertype.
  String? fieldType(String fieldName) {
    for (ClassInfo c in lookupChain) {
      for (ClassMember m in c.members) {
        if (m is FieldDeclaration && !m.isStatic) {
          for (VariableDeclaration v in m.fields.variables) {
            if (v.name.lexeme == fieldName) {
              return m.fields.type?.toSource();
            }
          }
        }
      }
    }
    return null;
  }

  /// The body of member [name] (a getter), as Dart looks it up from this
  /// class, and the class declaring it.
  /// The body of method [name], as Dart looks it up from this class.
  (ClassInfo, FunctionBody)? lookupMethod(String name, {bool skipSelf = false}) {
    bool first = true;
    for (ClassInfo c in lookupChain) {
      if (first && skipSelf) {
        first = false;
        continue;
      }
      first = false;
      for (ClassMember m in c.members) {
        if (m is MethodDeclaration &&
            !m.isGetter &&
            !m.isSetter &&
            m.name.lexeme == name) {
          if (m.body is EmptyFunctionBody) continue;
          return (c, m.body);
        }
      }
    }
    return null;
  }

  (ClassInfo, FunctionBody)? lookupGetter(String name, {bool skipSelf = false}) {
    bool first = true;
    for (ClassInfo c in lookupChain) {
      if (first && skipSelf) {
        first = false;
        continue;
      }
      first = false;
      for (ClassMember m in c.members) {
        if (m is MethodDeclaration && m.isGetter && m.name.lexeme == name) {
          if (m.body is EmptyFunctionBody) continue;
          return (c, m.body);
        }
      }
    }
    return null;
  }
}

/// The kind of a field: how the port stores it.
enum Kind { token, node, nodeList, tokenList, other }

class Field {
  final String dartName;
  final String type;
  final Kind kind;
  final bool nullable;

  new(this.dartName, this.type, this.kind, this.nullable);

  String get rustName => snake(dartName);

  String get rustType => switch (kind) {
    Kind.token => 'TokenId',
    Kind.node => 'NodeId',
    Kind.nodeList => 'NodeListImpl',
    Kind.tokenList => 'Vec<TokenId>',
    Kind.other => otherType(type),
  };
}

String otherType(String type) => switch (type) {
  'bool' => 'bool',
  'String' => 'Vec<u16>',
  'int?' => 'Option<i64>',
  'int' => 'i64',
  'double' => 'f64',
  'FeatureSet' => 'FeatureSet',
  'LineInfo' => 'LineInfo',
  'LibraryLanguageVersion' => 'LibraryLanguageVersion',
  'ParameterKind' => 'ParameterKind',
  'IncrementOrDecrementPosition' => 'IncrementOrDecrementPosition',
  'List<MdCodeBlock>' => 'Vec<MdCodeBlock>',
  'List<DocImport>' => 'Vec<DocImport>',
  'List<DocDirective>' => 'Vec<DocDirective>',
  _ => unknownType(type),
};

Kind kindOf(String type) {
  String t = type.endsWith('?') ? type.substring(0, type.length - 1) : type;
  if (t == 'Token') return Kind.token;
  if (t == 'List<Token>') return Kind.tokenList;
  if ((t.startsWith('List<') || t.startsWith('NodeListImpl<')) &&
      classes.containsKey(t.substring(t.indexOf('<') + 1, t.length - 1))) {
    return Kind.nodeList;
  }
  if (t.endsWith('Impl') && classes.containsKey(t)) return Kind.node;
  return Kind.other;
}

String snake(String name) {
  if (name.startsWith('_')) name = name.substring(1);
  StringBuffer sb = StringBuffer();
  for (int i = 0; i < name.length; i++) {
    String c = name[i];
    if (c.toUpperCase() == c && c.toLowerCase() != c) {
      if (i > 0) sb.write('_');
      sb.write(c.toLowerCase());
    } else {
      sb.write(c);
    }
  }
  String result = sb.toString();
  return switch (result) {
    'type' => 'type_',
    'operator' => 'operator_',
    _ => result,
  };
}

/// The fields of concrete class [c]: its constructor parameters (the
/// fields it declares, for a class only in the V1 view).
List<Field> fieldsOf(ClassInfo c) {
  if (isV1Only(c)) return fieldsOfV1(c);
  List<Field> result = [];
  void addParams(ClassInfo owner, ConstructorDeclaration ctor) {
    for (FormalParameter p in ctor.parameters.parameters) {
      FormalParameter param = p;
      String name = param.name!.lexeme;
      if (param is SuperFormalParameter) {
        ClassInfo superInfo = classes[owner.superclass]!;
        ConstructorDeclaration? superCtor = superInfo.unnamedConstructor;
        if (superCtor == null) {
          throw StateError('${owner.name}: no super constructor');
        }
        // Only the named super parameter.
        int before = result.length;
        addParams(superInfo, superCtor);
        List<Field> added = result.sublist(before);
        result.removeRange(before, result.length);
        for (Field f in added) {
          if (f.dartName == name ||
              (name == 'comment' && f.dartName == 'documentationComment')) {
            result.add(f);
          }
        }
        continue;
      }
      String type;
      if (param is FieldFormalParameter) {
        type = param.type?.toSource() ?? owner.fieldType(name)!;
      } else if (param is RegularFormalParameter) {
        type = param.type!.toSource();
      } else {
        throw StateError('${owner.name}: parameter $param');
      }
      if (name == 'comment' && type == 'CommentImpl?') {
        name = 'documentationComment';
      }
      if (resolutionTypes.contains(type)) continue;
      if (name.startsWith('_')) name = name.substring(1);
      result.add(Field(name, type, kindOf(type), type.endsWith('?')));
    }
  }

  ConstructorDeclaration? ctor = c.unnamedConstructor;
  if (ctor != null) addParams(c, ctor);
  return result;
}

bool isV1Only(ClassInfo c) {
  var getter = c.lookupGetter('_astNodeApi');
  if (getter == null) return false;
  String body = getter.$2.toSource();
  return body.contains('AstNodeApi.v1') &&
      !body.contains('AstNodeApi.shared') &&
      !body.contains('AstNodeApi.v2');
}

bool isAstNode(ClassInfo c) => c.allSupertypes.contains('AstNodeImpl');

/// Translates the expression [e] of a getter of [c] whose result is a
/// token. Returns Rust code of type `TokenId`.
class Translator {
  final ClassInfo c;
  final Map<String, Field> fields;
  final String member;

  new(this.c, this.fields, this.member);

  Never fail(Object what) =>
      throw StateError('${c.name}.$member: cannot translate $what');

  Field? field(String name) {
    if (name.startsWith('_')) name = name.substring(1);
    return fields[name];
  }

  /// [e] as a token (`NO_TOKEN` when null).
  String token(Expression e) {
    if (e is MethodInvocation &&
        e.target is SimpleIdentifier &&
        (e.target as SimpleIdentifier).name == "Token" &&
        e.methodName.name == "lexicallyFirst") {
      List<String> args = [
        for (var a in e.argumentList.arguments) token(a as Expression),
      ];
      return "tokens.lexically_first(&[${args.join(", ")}])";
    }
    if (e is IndexExpression && e.target is SimpleIdentifier) {
      Field? f = field((e.target as SimpleIdentifier).name);
      if (f != null && f.kind == Kind.tokenList) {
        String index = e.index.toSource();
        String fieldName = (e.target as SimpleIdentifier).name;
        if (index == "0") return "self.${f.rustName}[0]";
        if (index == "$fieldName.length - 1") {
          return "self.${f.rustName}[self.${f.rustName}.len() - 1]";
        }
      }
      fail(e);
    }
    if (e is PrefixedIdentifier && e.identifier.name == "first") {
      Field? f = field(e.prefix.name);
      if (f != null && f.kind == Kind.tokenList) return "self.${f.rustName}[0]";
    }
    if (e is SimpleIdentifier) {
      Field? f = field(e.name);
      if (f != null && f.kind == Kind.token) return 'self.${f.rustName}';
      fail(e);
    }
    if (e is PrefixedIdentifier || e is PropertyAccess) {
      Expression target;
      String property;
      if (e is PrefixedIdentifier) {
        target = e.prefix;
        property = e.identifier.name;
      } else {
        e as PropertyAccess;
        target = e.target!;
        property = e.propertyName.name;
      }
      if (target is SuperExpression) {
        var found = c.lookupGetter(property, skipSelf: true);
        if (found == null) fail(e);
        return '{ ${body(found.$1, found.$2, property)} }';
      }
      String which = switch (property) {
        'beginToken' => 'begin_token',
        'endToken' => 'end_token',
        _ => fail(e),
      };
      if (target is SimpleIdentifier) {
        Field? f = field(target.name);
        if (f != null && f.kind == Kind.node) {
          if (f.nullable && e is! PropertyAccess) {
            // `x.beginToken` on a nullable x only appears after a check.
          }
          return 'ast.$which(self.${f.rustName}, tokens)';
        }
        if (f != null && f.kind == Kind.nodeList) {
          return 'ast.node_list_$which(&self.${f.rustName}, tokens)';
        }
      }
      fail(e);
    }
    fail(e);
  }

  /// The body of getter [member] declared in [owner], translated for [c].
  String body(ClassInfo owner, FunctionBody body, String member) {
    String? hand = handBodies['${owner.name}.$member'];
    if (hand != null) return hand;
    if (body is ExpressionFunctionBody) {
      return token(body.expression);
    }
    if (body is BlockFunctionBody) {
      List<String> out = [];
      for (Statement s in body.block.statements) {
        out.add(statement(s));
      }
      return out.join('\n        ');
    }
    fail(body);
  }

  String statement(Statement s) {
    if (s is ReturnStatement) {
      return 'return ${token(s.expression!)};';
    }
    if (s is ExpressionStatement && s.expression is ThrowExpression) {
      var t = s.expression as ThrowExpression;
      var call = t.expression as MethodInvocation;
      var message = call.argumentList.arguments.first as SimpleStringLiteral;
      return 'panic!("${message.value}");';
    }
    if (s is IfStatement && s.caseClause != null && s.elseStatement == null) {
      // if (<e> case var v?) { return v[.beginToken|.endToken]; }
      var pattern = s.caseClause!.guardedPattern.pattern;
      if (pattern is NullCheckPattern &&
          pattern.pattern is DeclaredVariablePattern) {
        String v = (pattern.pattern as DeclaredVariablePattern).name.lexeme;
        Statement then = s.thenStatement;
        if (then is Block && then.statements.length == 1) {
          then = then.statements.single;
        }
        if (then is! ReturnStatement) fail(s);
        Expression result = then.expression!;
        Expression subject = s.expression;
        // A nullable node whose begin or end token is returned.
        if (subject is SimpleIdentifier) {
          Field? f = field(subject.name);
          if (f != null && f.kind == Kind.node) {
            String which = switch (result) {
              PrefixedIdentifier(
                prefix: SimpleIdentifier(name: var p),
                identifier: SimpleIdentifier(name: 'beginToken'),
              )
                  when p == v =>
                'begin_token',
              PrefixedIdentifier(
                prefix: SimpleIdentifier(name: var p),
                identifier: SimpleIdentifier(name: 'endToken'),
              )
                  when p == v =>
                'end_token',
              _ => fail(s),
            };
            return 'if self.${f.rustName} != NO_NODE {\n'
                '            return ast.$which(self.${f.rustName}, tokens);\n'
                '        }';
          }
          if (f != null && f.kind == Kind.token) {
            if (result is! SimpleIdentifier || result.name != v) fail(s);
            return 'if self.${f.rustName} != NO_TOKEN {\n'
                '            return self.${f.rustName};\n'
                '        }';
          }
        }
        // A token expression that may be null.
        if (result is SimpleIdentifier && result.name == v) {
          return '{\n'
              '            let $v = ${token(subject)};\n'
              '            if $v != NO_TOKEN {\n'
              '                return $v;\n'
              '            }\n'
              '        }';
        }
      }
    }
    fail(s);
  }
}

class ChildTranslator {
  final ClassInfo c;
  final Map<String, Field> fields;

  new(this.c, this.fields);

  Never fail(Object what) =>
      throw StateError('${c.name}._childEntities2: cannot translate $what');

  /// The calls adding the child entities, from the body of
  /// `_childEntities2` declared in [owner].
  List<String> body(ClassInfo owner, FunctionBody body) {
    Expression e;
    if (body is ExpressionFunctionBody) {
      e = body.expression;
    } else if (body is BlockFunctionBody &&
        body.block.statements.length == 1 &&
        body.block.statements.single is ReturnStatement) {
      e = (body.block.statements.single as ReturnStatement).expression!;
    } else {
      fail(body);
    }
    if (e is! CascadeExpression) {
      if (e is InstanceCreationExpression || e is MethodInvocation) return [];
      fail(e);
    }
    List<String> result = [];
    Expression target = e.target;
    if (target is PropertyAccess && target.target is SuperExpression) {
      var found = owner.lookupGetter('_childEntities2', skipSelf: true);
      if (found == null) fail(target);
      result.addAll(this.body(found.$1, found.$2));
    } else if (target is! MethodInvocation &&
        target is! InstanceCreationExpression) {
      fail(target);
    }
    for (Expression section in e.cascadeSections) {
      var call = section as MethodInvocation;
      var args = call.argumentList.arguments;
      String name = (args[0] as SimpleStringLiteral).value;
      var value = args[1];
      if (value is! SimpleIdentifier) fail(section);
      String fieldName = value.name;
      if (fieldName.startsWith('_')) fieldName = fieldName.substring(1);
      Field? f = fields[fieldName];
      if (f == null) fail(section);
      String method = call.methodName.name;
      String expected = switch (f.kind) {
        Kind.token => 'addToken',
        Kind.node => 'addNode',
        Kind.nodeList => 'addNodeList',
        Kind.tokenList => 'addTokenList',
        Kind.other => fail(section),
      };
      if (method != expected) fail(section);
      String rust = snake(method);
      String arg = switch (f.kind) {
        Kind.nodeList || Kind.tokenList => '&self.${f.rustName}',
        _ => 'self.${f.rustName}',
      };
      result.add('entities.$rust("$name", $arg);');
    }
    return result;
  }
}

void main(List<String> args) {
  String source = File(args[0]).readAsStringSync();
  unit = parseString(content: source, throwIfDiagnostics: false).unit;
  for (CompilationUnitMember d in unit.declarations) {
    if (d is ClassDeclaration) {
      var body = d.body;
      classes[d.namePart.typeName.lexeme] = ClassInfo(
        d.namePart.typeName.lexeme,
        isAbstract: d.abstractKeyword != null || d.sealedKeyword != null,
        isMixin: false,
        superclass: d.extendsClause?.superclass.name.lexeme,
        mixins: [
          for (NamedType t in d.withClause?.mixinTypes ?? []) t.name.lexeme,
        ],
        interfaces: [
          for (NamedType t in d.implementsClause?.interfaces ?? [])
            t.name.lexeme,
        ],
        members: body is BlockClassBody ? body.members : [],
      );
    } else if (d is MixinDeclaration) {
      var body = d.body;
      classes[d.name.lexeme] = ClassInfo(
        d.name.lexeme,
        isAbstract: true,
        isMixin: true,
        superclass: null,
        mixins: [],
        interfaces: [
          for (NamedType t in d.onClause?.superclassConstraints ?? [])
            t.name.lexeme,
          for (NamedType t in d.implementsClause?.interfaces ?? [])
            t.name.lexeme,
        ],
        members: body is BlockClassBody ? body.members : [],
      );
    }
  }

  // The classes the AstBuilder and the DocCommentBuilder construct.
  Set<String> built = {
    for (String path in args.skip(2))
      for (Match m in RegExp(r"\b([A-Z][A-Za-z0-9]*Impl)\(").allMatches(
        File(path).readAsStringSync(),
      ))
        m[1]!,
  };
  List<ClassInfo> concrete = [
    for (ClassInfo c in classes.values)
      if (!c.isAbstract &&
          c.name.endsWith('Impl') &&
          isAstNode(c) &&
          (isV1Only(c) || built.contains(c.name)))
        c,
  ]..sort((a, b) => a.name.compareTo(b.name));

  StringBuffer out = StringBuffer();
  out.write(header);
  List<String> errors = [];
  StringBuffer impls = StringBuffer();
  for (ClassInfo c in concrete) {
    List<Field> fields = fieldsOf(c);
    Map<String, Field> byName = {for (Field f in fields) f.dartName: f};
    out.writeln('#[derive(Clone, Debug)]');
    out.writeln('pub struct ${c.name} {');
    for (Field f in fields) {
      out.writeln('    pub ${f.rustName}: ${f.rustType},');
    }
    out.writeln('}');
    out.writeln();

    impls.writeln('impl ${c.name} {');
    bool v1Only = isV1Only(c);
    for (var (String getter, String rust) in [
      ('beginToken', v1Only ? 'begin_token1' : 'begin_token'),
      ('endToken', v1Only ? 'end_token1' : 'end_token'),
      ('firstTokenAfterCommentAndMetadata',
          'first_token_after_comment_and_metadata'),
    ]) {
      var found = c.lookupGetter(getter);
      if (byName.containsKey(getter)) {
        found = (c, (parseString(content: "get x => $getter;").unit.declarations.single as FunctionDeclaration).functionExpression.body);
      }
      if (found == null) {
        if (getter == 'firstTokenAfterCommentAndMetadata') continue;
        errors.add('${c.name}.$getter: not found');
        continue;
      }
      try {
        String body = Translator(c, byName, getter).body(
          found.$1,
          found.$2,
          getter,
        );
        impls.writeln(
          rust.endsWith('1')
              ? '    pub fn $rust(&self, ast: &AstStore, tokens: &TokenStore, id: NodeId) '
                    '-> TokenId {\n        let _ = id;'
              : '    pub fn $rust(&self, ast: &AstStore, tokens: &TokenStore) '
                    '-> TokenId {',
        );
        impls.writeln('        $body');
        impls.writeln('    }');
        impls.writeln();
      } on StateError catch (e) {
        if (!v1Only) {
          errors.add(e.message);
        } else if (rust == 'first_token_after_comment_and_metadata') {
          handGetters.add('${c.name}.$getter');
          impls.writeln(
            '    pub fn $rust(&self, ast: &AstStore, tokens: &TokenStore) -> TokenId {',
          );
          impls.writeln('        self.${rust}_hand(Ast::new(ast, tokens))');
          impls.writeln('    }');
          impls.writeln();
        } else {
          handGetters.add('${c.name}.$getter');
          impls.writeln(
            '    pub fn $rust(&self, ast: &AstStore, tokens: &TokenStore, id: NodeId) -> TokenId {',
          );
          impls.writeln('        self.${rust}_hand(Ast::new(ast, tokens), id)');
          impls.writeln('    }');
          impls.writeln();
        }
      }
    }
    if (v1Only) {
      String bare = c.name.substring(0, c.name.length - 4);
      impls.writeln(
        "    pub fn child_entities2<'a>(&'a self, "
        "ast: &AstStore, tokens: &TokenStore, entities: &mut ChildEntities<'a>) {",
      );
      impls.writeln('        panic!("StateError: $bare is not in the V2 AST view.");');
      impls.writeln('    }');
      impls.writeln();
      impls.writeln(
        "    pub fn visit_children2<V: AstVisitor2 + ?Sized>(&self, ast: Ast<'_>, visitor: &mut V) {",
      );
      impls.writeln('        panic!("StateError: $bare is not in the V2 AST view.");');
      impls.writeln('    }');
      impls.writeln();
      impls.writeln('    pub fn for_each_child_node(&self, f: &mut impl FnMut(NodeId)) {');
      impls.writeln('        let _ = f;');
      impls.writeln('    }');
      writeV1Members(c, byName, impls, errors);
      impls.writeln('}');
      impls.writeln();
      continue;
    }
    var children = c.lookupGetter('_childEntities2');
    try {
      List<String> calls = handChildren.containsKey(c.name)
          ? [handChildren[c.name]!]
          : children == null
          ? []
          : ChildTranslator(c, byName).body(children.$1, children.$2);
      impls.writeln(
        "    pub fn child_entities2<'a>(&'a self, "
        "ast: &AstStore, tokens: &TokenStore, entities: &mut ChildEntities<'a>) {",
      );
      for (String call in calls) {
        impls.writeln('        $call');
      }
      if (calls.isEmpty) impls.writeln('        let _ = entities;');
      impls.writeln('    }');
    } on StateError catch (e) {
      errors.add(e.message);
    }
    writeV2Members(c, byName, impls, errors);
    writeV1Members(c, byName, impls, errors);
    impls.writeln('}');
    impls.writeln();
  }

  out.writeln('/// Every node class, `AstNodeImpl` and its subclasses upstream.');
  out.writeln('#[derive(Clone, Debug)]');
  out.writeln('pub enum AstNodeImpl {');
  for (ClassInfo c in concrete) {
    out.writeln(
      isBoxed(c)
          ? '    ${c.name}(Box<${c.name}>),'
          : '    ${c.name}(${c.name}),',
    );
  }
  out.writeln('}');
  out.writeln();
  for (ClassInfo c in concrete) {
    out.writeln('impl From<${c.name}> for AstNodeImpl {');
    out.writeln('    fn from(node: ${c.name}) -> AstNodeImpl {');
    out.writeln(
      isBoxed(c)
          ? '        AstNodeImpl::${c.name}(Box::new(node))'
          : '        AstNodeImpl::${c.name}(node)',
    );
    out.writeln('    }');
    out.writeln('}');
    out.writeln();
  }

  out.writeln('impl AstNodeImpl {');
  out.writeln('    /// `runtimeType.toString()`.');
  out.writeln("    pub fn runtime_type(&self) -> &'static str {");
  out.writeln('        match self {');
  for (ClassInfo c in concrete) {
    out.writeln('            AstNodeImpl::${c.name}(_) => "${c.name}",');
  }
  out.writeln('        }');
  out.writeln('    }');
  out.writeln();
  for (var (String rust, String args, String ret) in [
    ('begin_token', 'ast: &AstStore, tokens: &TokenStore', 'TokenId'),
    ('end_token', 'ast: &AstStore, tokens: &TokenStore', 'TokenId'),
  ]) {
    out.writeln('    pub fn $rust(&self, $args) -> $ret {');
    out.writeln('        match self {');
    for (ClassInfo c in concrete) {
      out.writeln(
        isV1Only(c)
            ? '            AstNodeImpl::${c.name}(_) => panic!("${c.name}: a V1 projection needs its id"),'
            : '            AstNodeImpl::${c.name}(n) => n.$rust(ast, tokens),',
      );
    }
    out.writeln('        }');
    out.writeln('    }');
    out.writeln();
    out.writeln('    /// `$rust` of the node [id].');
    out.writeln('    #[inline]');
    out.writeln('    pub fn ${rust}_of(&self, $args, id: NodeId) -> $ret {');
    out.writeln('        match self {');
    for (ClassInfo c in concrete) {
      out.writeln(
        isV1Only(c)
            ? '            AstNodeImpl::${c.name}(n) => n.${rust}1(ast, tokens, id),'
            : '            AstNodeImpl::${c.name}(n) => n.$rust(ast, tokens),',
      );
    }
    out.writeln('        }');
    out.writeln('    }');
    out.writeln();
  }
  out.writeln('    /// `_childEntities2.entities`.');
  out.writeln(
    "    pub fn child_entities2<'a>(&'a self, "
    "ast: &AstStore, tokens: &TokenStore, entities: &mut ChildEntities<'a>) {",
  );
  out.writeln('        match self {');
  for (ClassInfo c in concrete) {
    out.writeln(
      '            AstNodeImpl::${c.name}(n) => n.child_entities2(ast, tokens, entities),',
    );
  }
  out.writeln('        }');
  out.writeln('    }');
  out.writeln();

  writeV2Dispatch(concrete, out);
  writeV1Dispatch(concrete, out);

  // Accessors that stand for `as XImpl` casts.
  for (ClassInfo c in concrete) {
    String s = snake(c.name);
    out.writeln('    /// `this as ${c.name}`.');
    out.writeln('    pub fn as_$s(&self) -> &${c.name} {');
    out.writeln('        match self {');
    out.writeln('            AstNodeImpl::${c.name}(n) => n,');
    out.writeln(
      '            _ => panic!("{} is not a ${c.name}", self.runtime_type()),',
    );
    out.writeln('        }');
    out.writeln('    }');
    out.writeln();
    out.writeln('    pub fn as_${s}_mut(&mut self) -> &mut ${c.name} {');
    out.writeln('        match self {');
    out.writeln('            AstNodeImpl::${c.name}(n) => n,');
    out.writeln('            _ => panic!("not a ${c.name}"),');
    out.writeln('        }');
    out.writeln('    }');
    out.writeln();
  }

  // Type tests for every class and mixin with node subclasses: `is XImpl`.
  List<ClassInfo> tested = [
    for (ClassInfo c in classes.values)
      if (c.name.endsWith('Impl') && isAstNode(c)) c,
  ]..sort((a, b) => a.name.compareTo(b.name));
  for (ClassInfo t in tested) {
    List<ClassInfo> subtypes = [
      for (ClassInfo c in concrete)
        if (c.allSupertypes.contains(t.name)) c,
    ];
    if (subtypes.isEmpty) continue;
    out.writeln('    /// `this is ${t.name}`.');
    out.writeln('    pub fn is_${snake(t.name)}(&self) -> bool {');
    out.writeln('        matches!(');
    out.writeln('            self,');
    out.write('            ');
    out.write(
      [for (ClassInfo c in subtypes) 'AstNodeImpl::${c.name}(_)'].join(
        '\n                | ',
      ),
    );
    out.writeln();
    out.writeln('        )');
    out.writeln('    }');
    out.writeln();
  }
  out.writeln('}');
  out.writeln();
  out.write(impls);
  writeMutations(concrete, out, errors);

  File('${args[1]}.hand.txt').writeAsStringSync(
    '${(handGetters.toList()..sort()).join('\n')}\n',
  );
  if (unknownTypes.isNotEmpty) errors.add("unknown types: $unknownTypes");
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    stderr.writeln('${errors.length} members not translated');
    exitCode = 1;
  }
  // The members written by hand upstream that the generator does not
  // translate are kept below [handMarker] in the output, across runs.
  File target = File(args[1]);
  String hand = "";
  if (target.existsSync()) {
    String old = target.readAsStringSync();
    int index = old.indexOf(handMarker);
    if (index >= 0) hand = old.substring(index + handMarker.length);
  }
  out.write(handMarker);
  out.write(hand);
  target.writeAsStringSync(out.toString());
}

const String header = '''
// Port of lib/src/dart/ast/ast.dart, the node classes.
//
// Generated by oracle/generate_ast.dart from ast.dart, except the members
// below the "Written by hand" line, which the generator keeps. Run the
// generator again when ast.dart changes (see ../../../../README.md).
//
// Every node class the AstBuilder builds is a struct holding its
// constructor's parameters, and `AstNodeImpl` (upstream's base class) is the
// enum of them all. Nodes live in an `AstStore` (ast_store.rs) addressed by
// `NodeId`s, as tokens live in a `TokenStore`; `NO_NODE` is null.
// A node whose fields take more than 24 bytes is boxed in the enum, which
// keeps every node at 32 bytes.
// `beginToken`, `endToken`, `_childEntities2`, `accept2`, `visitChildren2`
// and `precedence` are translated from upstream's bodies, and the children
// a constructor makes this node the parent of are its node fields; `is XImpl` and `as XImpl` are `is_x_impl` and `as_x_impl`.
// The classes that exist only in the V1 view of the AST, which upstream
// projects from these, are structs holding the fields they declare; the V1
// members (`_childEntities`, `visitChildren`, `accept`,
// `_childContainingRange`) of every class are translated as the V2 ones are,
// and the getters they read that upstream writes by hand are in ast_v1.rs.
#![allow(clippy::all)]
#![allow(non_snake_case, non_camel_case_types, unused_variables)]

use fe_analyzer_shared::scanner::token::{NO_TOKEN, TokenId, TokenStore};

use crate::dart::ast::precedence::Precedence;
use crate::src::dart::ast::ast_g::{AstVisitor, AstVisitor2};
use crate::src::dart::ast::ast_store::{Ast, AstNodeApi, AstStore, ChildEntities, ChildEntities1, NO_NODE, NodeId, NodeListImpl, V1_BASE};
use crate::dart::analysis::features::FeatureSet;
use crate::dart::ast::doc_comment::{DocDirective, DocImport, MdCodeBlock};
use crate::dart::element::element::LibraryLanguageVersion;
use crate::source::line_info::LineInfo;
use crate::src::generated::utilities_dart::ParameterKind;

/// `enum IncrementOrDecrementPosition { prefix, postfix }`.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum IncrementOrDecrementPosition {
    prefix,
    postfix,
}

''';

final Set<String> unknownTypes = {};

String unknownType(String type) {
  unknownTypes.add(type);
  return 'UNKNOWN';
}

const String handMarker = '''
// ---------------------------------------------------------------------------
// Written by hand (kept by the generator): members of ast.dart's node classes
// that upstream writes by hand and that parsing uses.
// ---------------------------------------------------------------------------
''';

/// The bytes a struct's fields take, roughly (a `Vec` is 24).
int structSize(ClassInfo c) {
  int size = 0;
  for (Field f in fieldsOf(c)) {
    size += switch (f.kind) {
      Kind.token || Kind.node => 4,
      Kind.nodeList || Kind.tokenList => 24,
      Kind.other => switch (f.type) {
        'bool' || 'ParameterKind' || 'IncrementOrDecrementPosition' => 1,
        'int' || 'double' => 8,
        'int?' => 16,
        _ => 24,
      },
    };
  }
  return size;
}

/// Whether `AstNodeImpl` holds the class's struct in a box: a struct larger
/// than most nodes would make every node as large, since an enum is as large
/// as its largest variant.
bool isBoxed(ClassInfo c) => structSize(c) > 24;

/// Hand translations of `visitChildren2` bodies: Rust statements.
const Map<String, String> handVisitChildren = {
  // Upstream first throws for a V1 projection, which is never built here.
  'FunctionExpressionImpl': '''
if self.type_parameters != NO_NODE {
            ast.accept2(self.type_parameters, visitor);
        }
        if self.parameters != NO_NODE {
            ast.accept2(self.parameters, visitor);
        }
        ast.accept2(self.body, visitor);''',
  // Upstream first throws when the node was made from a constructor type
  // reference, which only the V1 view does.
  'NamedTypeImpl': '''
if self.import_prefix != NO_NODE {
            ast.accept2(self.import_prefix, visitor);
        }
        if self.type_arguments != NO_NODE {
            ast.accept2(self.type_arguments, visitor);
        }''',
  'CompilationUnitImpl': '''
if self.script_tag != NO_NODE {
            ast.accept2(self.script_tag, visitor);
        }
        // _directivesAreBeforeDeclarations
        let before = self.directives.is_empty()
            || self.declarations2.is_empty()
            || ast.offset(self.directives[self.directives.len() - 1])
                < ast.offset(self.declarations2[0]);
        if before {
            for &element in &self.directives {
                ast.accept2(element, visitor);
            }
            for &element in &self.declarations2 {
                ast.accept2(element, visitor);
            }
        } else {
            for child in ast.sorted_by_offset(&[&self.directives[..], &self.declarations2[..]]) {
                ast.accept2(child, visitor);
            }
        }''',
};

/// Hand translations of `accept2`: the visit method.
const Map<String, String> handAccept = {
  'FunctionExpressionImpl': 'visitFunctionExpression',
  'NamedTypeImpl': 'visitNamedType',
};

/// Hand translations of `precedence` getters, keyed by the declaring class.
const Map<String, String> handPrecedence = {
  'BinaryOperatorInvocationImpl':
      'Precedence::for_token_type(ast.tokens.type_(self.operator_))',
  'IncrementOrDecrementExpressionImpl': '''
match self.position {
            IncrementOrDecrementPosition::prefix => Precedence::prefix,
            IncrementOrDecrementPosition::postfix => Precedence::postfix,
        }''',
  'ParsedDotShorthandExpressionImpl': 'ast.precedence(self.expression)',
  'TypeLiteralImpl': '''
let type_ = ast.node(self.type_).as_named_type_impl();
        if type_.type_arguments != NO_NODE {
            Precedence::postfix
        } else if type_.import_prefix != NO_NODE {
            Precedence::postfix
        } else {
            Precedence::primary
        }''',
};

/// The field a getter or field named [name] of [c] reads: the field itself,
/// or the one a getter `=> _x` returns.
Field? resolveField(ClassInfo c, Map<String, Field> fields, String name) {
  String bare = name.startsWith('_') ? name.substring(1) : name;
  Field? f = fields[bare];
  if (f != null) return f;
  var getter = c.lookupGetter(name);
  if (getter != null) {
    var body = getter.$2;
    if (body is ExpressionFunctionBody && body.expression is SimpleIdentifier) {
      String target = (body.expression as SimpleIdentifier).name;
      if (target != name) return resolveField(c, fields, target);
    }
  }
  return null;
}

/// `visitChildren2` of [c]: Rust statements visiting its children.
List<String> visitChildrenBody(
  ClassInfo c,
  Map<String, Field> fields,
  ClassInfo owner,
  FunctionBody body,
) {
  Never fail(Object what) =>
      throw StateError('${c.name}.visitChildren2: cannot translate $what');
  if (body is! BlockFunctionBody) fail(body);
  List<String> out = [];
  for (Statement s in body.block.statements) {
    if (s is! ExpressionStatement || s.expression is! MethodInvocation) {
      fail(s);
    }
    var call = s.expression as MethodInvocation;
    var target = call.target;
    String method = call.methodName.name;
    if (target is SuperExpression && method == 'visitChildren2') {
      var found = owner.lookupMethod('visitChildren2', skipSelf: true);
      if (found != null) {
        out.addAll(visitChildrenBody(c, fields, found.$1, found.$2));
      }
      continue;
    }
    if (target == null && method == '_visitCommentAndAnnotations2') {
      out.add(
        'ast.visit_comment_and_annotations2('
        'self.documentation_comment, &self.metadata, visitor);',
      );
      continue;
    }
    if (method != 'accept2' || target is! SimpleIdentifier) fail(s);
    Field? f = resolveField(c, fields, target.name);
    if (f == null) fail(s);
    switch (f.kind) {
      case Kind.node:
        if (f.nullable || call.operator?.lexeme == '?.') {
          out.add(
            'if self.${f.rustName} != NO_NODE {\n'
            '            ast.accept2(self.${f.rustName}, visitor);\n'
            '        }',
          );
        } else {
          out.add('ast.accept2(self.${f.rustName}, visitor);');
        }
      case Kind.nodeList:
        out.add(
          'for &element in &self.${f.rustName} {\n'
          '            ast.accept2(element, visitor);\n'
          '        }',
        );
      default:
        fail(s);
    }
  }
  return out;
}

/// `precedence` of [c], or null when [c] has none (it is not an expression).
String? precedenceBody(ClassInfo c, Map<String, Field> fields) {
  for (ClassInfo owner in c.lookupChain) {
    for (ClassMember m in owner.members) {
      if (m is MethodDeclaration && m.isGetter && m.name.lexeme == 'precedence') {
        if (m.body is EmptyFunctionBody) continue;
        if (m.returnType?.toSource() != 'Precedence') return null;
        String? hand = handPrecedence[owner.name];
        if (hand != null) return hand;
        var body = m.body;
        if (body is ExpressionFunctionBody) {
          var e = body.expression;
          if (e is PrefixedIdentifier && e.prefix.name == 'Precedence') {
            return 'Precedence::${e.identifier.name}';
          }
        }
        throw StateError('${c.name}.precedence: cannot translate $body');
      }
    }
  }
  return null;
}

void writeV2Members(
  ClassInfo c,
  Map<String, Field> fields,
  StringBuffer impls,
  List<String> errors,
) {
  // accept2
  var accept = c.lookupMethod('accept2');
  String? visit;
  if (accept != null && accept.$2 is ExpressionFunctionBody) {
    var e = (accept.$2 as ExpressionFunctionBody).expression;
    if (e is MethodInvocation &&
        e.target is SimpleIdentifier &&
        (e.target as SimpleIdentifier).name == 'visitor') {
      visit = e.methodName.name;
    }
  }
  visit ??= handAccept[c.name];
  if (visit == null) {
    errors.add('${c.name}.accept2: cannot translate');
  } else {
    acceptMethods[c.name] = visit;
  }

  // visitChildren2
  try {
    List<String> statements;
    if (handVisitChildren.containsKey(c.name)) {
      statements = [handVisitChildren[c.name]!];
    } else {
      var found = c.lookupMethod('visitChildren2');
      statements = found == null
          ? []
          : visitChildrenBody(c, fields, found.$1, found.$2);
    }
    impls.writeln();
    impls.writeln(
      "    pub fn visit_children2<V: AstVisitor2 + ?Sized>(&self, ast: Ast<'_>, visitor: &mut V) {",
    );
    if (statements.isEmpty) impls.writeln('        let _ = (ast, visitor);');
    for (String s in statements) {
      impls.writeln('        $s');
    }
    impls.writeln('    }');
  } on StateError catch (e) {
    errors.add(e.message);
  }

  // The children the constructor makes this node the parent of.
  impls.writeln();
  impls.writeln('    pub fn for_each_child_node(&self, f: &mut impl FnMut(NodeId)) {');
  bool any = false;
  List<String> parented;
  try {
    parented = parentedFields(c, c);
  } on StateError catch (e) {
    errors.add(e.message);
    parented = [];
  }
  for (String name in parented) {
    Field? field = fields[name];
    if (field == null) {
      errors.add('${c.name}: parented field $name is not stored');
      continue;
    }
    if (field.kind == Kind.node) {
      impls.writeln('        f(self.${field.rustName});');
      any = true;
    } else if (field.kind == Kind.nodeList) {
      impls.writeln('        for &element in &self.${field.rustName} {');
      impls.writeln('            f(element);');
      impls.writeln('        }');
      any = true;
    }
  }
  if (!any) impls.writeln('        let _ = f;');
  impls.writeln('    }');

  try {
    String? precedence = precedenceBody(c, fields);
    if (precedence != null) {
      precedenceClasses.add(c.name);
      impls.writeln();
      impls.writeln("    pub fn precedence(&self, ast: Ast<'_>) -> Precedence {");
      impls.writeln('        $precedence');
      impls.writeln('    }');
    }
  } on StateError catch (e) {
    errors.add(e.message);
  }
}

final Map<String, String> acceptMethods = {};
final Set<String> precedenceClasses = {};

void writeV2Dispatch(List<ClassInfo> concrete, StringBuffer out) {
  out.writeln('    /// `accept2(visitor)`: the visitor\'s method for this class.');
  out.writeln(
    "    pub fn accept2<V: AstVisitor2 + ?Sized>(&self, ast: Ast<'_>, id: NodeId, visitor: &mut V) -> Option<V::R> {",
  );
  out.writeln('        match self {');
  for (ClassInfo c in concrete) {
    String? visit = acceptMethods[c.name];
    if (visit == null) {
      String bare = c.name.substring(0, c.name.length - 4);
      out.writeln(
        '            AstNodeImpl::${c.name}(_) => panic!("StateError: $bare is not in the V2 AST view."),',
      );
      continue;
    }
    out.writeln(
      '            AstNodeImpl::${c.name}(_) => visitor.${snakeVisit(visit)}(ast, id),',
    );
  }
  out.writeln('        }');
  out.writeln('    }');
  out.writeln();
  out.writeln('    /// `visitChildren2(visitor)`.');
  out.writeln(
    "    pub fn visit_children2<V: AstVisitor2 + ?Sized>(&self, ast: Ast<'_>, visitor: &mut V) {",
  );
  out.writeln('        match self {');
  for (ClassInfo c in concrete) {
    out.writeln(
      '            AstNodeImpl::${c.name}(n) => n.visit_children2(ast, visitor),',
    );
  }
  out.writeln('        }');
  out.writeln('    }');
  out.writeln();
  out.writeln('    /// The nodes the constructor makes this node the parent of.');
  out.writeln(
    '    pub fn for_each_child_node(&self, f: &mut impl FnMut(NodeId)) {',
  );
  out.writeln('        match self {');
  for (ClassInfo c in concrete) {
    out.writeln(
      '            AstNodeImpl::${c.name}(n) => n.for_each_child_node(f),',
    );
  }
  out.writeln('        }');
  out.writeln('    }');
  out.writeln();
  out.writeln('    /// `(this as ExpressionImpl).precedence`.');
  out.writeln("    pub fn precedence(&self, ast: Ast<'_>) -> Precedence {");
  out.writeln('        match self {');
  for (ClassInfo c in concrete) {
    if (!precedenceClasses.contains(c.name)) continue;
    out.writeln(
      '            AstNodeImpl::${c.name}(n) => n.precedence(ast),',
    );
  }
  out.writeln(
    '            _ => panic!("{} has no precedence", self.runtime_type()),',
  );
  out.writeln('        }');
  out.writeln('    }');
  out.writeln();
}

/// `visitFooBar2` as the Rust method `visit_foo_bar2`.
String snakeVisit(String name) {
  StringBuffer sb = StringBuffer();
  for (int i = 0; i < name.length; i++) {
    String c = name[i];
    if (c.toUpperCase() == c && c.toLowerCase() != c) {
      if (i > 0) sb.write('_');
      sb.write(c.toLowerCase());
    } else {
      sb.write(c);
    }
  }
  return sb.toString();
}

/// The fields whose nodes the constructor of [owner] (run for [c]) makes
/// the node the parent of in the V2 view, in order.
List<String> parentedFields(ClassInfo c, ClassInfo owner) {
  ConstructorDeclaration? ctor = owner.unnamedConstructor;
  if (ctor == null) return [];
  Never fail(Object what) =>
      throw StateError('${c.name}: constructor of ${owner.name}: $what');
  String bare(String name) => name.startsWith('_') ? name.substring(1) : name;
  List<String> result = [];
  bool hasSuper =
      ctor.parameters.parameters.any((p) => p is SuperFormalParameter) ||
      ctor.initializers.any((i) => i is SuperConstructorInvocation);
  if (hasSuper && owner.superclass != null) {
    ClassInfo? superInfo = classes[owner.superclass];
    if (superInfo != null) result.addAll(parentedFields(c, superInfo));
  }
  var body = ctor.body;
  if (body is EmptyFunctionBody) return result;
  if (body is! BlockFunctionBody) fail(body);
  for (Statement s in body.block.statements) {
    String source = s.toSource();
    // Assertions, the V1 view and the API override set no V2 parent.
    if (s is AssertStatement ||
        (!source.contains('_becomeParentOf2') &&
            !source.contains('_becomeParentOf12') &&
            !source.contains('_initialize') &&
            (source.contains('_becomeParentOf1(') ||
                source.contains('._astNodeApiOverride = ')))) {
      continue;
    }
    if (s is! ExpressionStatement || s.expression is! MethodInvocation) {
      fail(s.toSource());
    }
    var call = s.expression as MethodInvocation;
    String method = call.methodName.name;
    var args = call.argumentList.arguments;
    switch (method) {
      case '_becomeParentOf12' ||
          '_becomeParentOf2' ||
          '_becomeParentOf2AndExisting1' ||
          '_becomeParentOfOwnedView':
        var arg = args.single;
        if (arg is! SimpleIdentifier) fail(s.toSource());
        result.add(bare(arg.name));
      case '_becomeParentOf1':
        // The V1 view only.
        break;
      case '_initialize' || '_initializeProjected':
        var target = call.target;
        String name = switch (target) {
          PropertyAccess(:var propertyName) => propertyName.name,
          SimpleIdentifier(:var name) => name,
          _ => fail(s.toSource()),
        };
        result.add(bare(name));
      case '_initializeCommentAndAnnotations':
        result.addAll(['documentationComment', 'metadata']);
      default:
        fail(s.toSource());
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// The V1 view.
//
// Upstream generates, for every node class, the members that walk the V1 view
// (`_childEntities`, `visitChildren`, `accept`, `_childContainingRange`) as
// it does the V2 ones, from the same `@GenerateNodeImpl` annotation; a V1
// child is a V2 field, or a V2 field projected by `V1Projection`
// (`_becomeParentOf1(V1Projection.toV1Expression(expression2))`), or a getter
// written by hand. These are translated as the V2 members are, and a getter
// written by hand becomes a call of the method of the same name, which
// ast_v1.rs ports by hand. The classes that exist only in the V1 view (the
// projections) are structs too, holding the fields they declare.
// ---------------------------------------------------------------------------

/// The fields of a class that exists only in the V1 view: the node and
/// token fields it and its superclasses declare (not those of `AstNodeImpl`,
/// and not the `late` caches, which ast_v1.rs keeps in the store).
List<Field> fieldsOfV1(ClassInfo c) {
  List<Field> result = [];
  Set<String> seen = {};
  for (ClassInfo owner in c.lookupChain) {
    if (owner.name == 'AstNodeImpl') continue;
    for (ClassMember m in owner.members) {
      if (m is! FieldDeclaration || m.isStatic) continue;
      String? type = m.fields.type?.toSource();
      if (type == null) continue;
      for (VariableDeclaration v in m.fields.variables) {
        if (m.fields.isLate && v.initializer != null) continue;
        if (v.initializer != null && !type.startsWith('NodeListImpl')) {
          continue;
        }
        String name = v.name.lexeme;
        if (name.startsWith('_')) name = name.substring(1);
        if (name == 'parent' || name == 'parent2') continue;
        if (!seen.add(name)) continue;
        Kind kind = type.startsWith('_ConstructorReferenceV2Origin')
            ? Kind.node
            : kindOf(type);
        if (kind == Kind.other) continue;
        // A field typed by an interface (`_ConstructorReferenceV2Origin`)
        // holds a node too.
        result.add(Field(name, type, kind, type.endsWith('?')));
      }
    }
  }
  return result;
}

/// A constructor call `C(args)` (unresolved, it parses as a method
/// invocation) as its class name and arguments.
(String, List<Expression>)? invocation(Expression e) {
  if (e is InstanceCreationExpression) {
    return (
      e.constructorName.type.name.lexeme,
      [for (var a in e.argumentList.arguments) a as Expression],
    );
  }
  if (e is MethodInvocation && e.target == null) {
    return (
      e.methodName.name,
      [for (var a in e.argumentList.arguments) a as Expression],
    );
  }
  return null;
}

/// The member [name] as Dart looks it up from [c]: a getter, or a field.
(ClassInfo, ClassMember, VariableDeclaration?)? lookupMember(
  ClassInfo c,
  String name, {
  bool skipSelf = false,
}) {
  bool first = true;
  for (ClassInfo owner in c.lookupChain) {
    if (first && skipSelf) {
      first = false;
      continue;
    }
    first = false;
    for (ClassMember m in owner.members) {
      if (m is MethodDeclaration &&
          m.isGetter &&
          m.name.lexeme == name &&
          m.body is! EmptyFunctionBody) {
        return (owner, m, null);
      }
      if (m is FieldDeclaration && !m.isStatic) {
        for (VariableDeclaration v in m.fields.variables) {
          if (v.name.lexeme == name) return (owner, m, v);
        }
      }
    }
  }
  return null;
}

/// `V1Projection.toV1X` as the `Ast` method that ports it.
String projectionMethod(String name) => switch (name) {
  'toV1Expression' => 'to_v1_expression',
  'toV1Argument' => 'to_v1_argument',
  'toV1CollectionElement' => 'to_v1_collection_element',
  'toV1CombinatorName' => 'to_v1_combinator_name',
  'toV1LocalVariables' => 'to_v1_local_variables',
  'toV1RecordLiteralField' => 'to_v1_record_literal_field',
  'toV1Statement' => 'to_v1_statement',
  'toV1ClassMember' => 'to_v1_class_member',
  'toV1CompilationUnitMember' => 'to_v1_compilation_unit_member',
  'toV1ClassBody' => 'to_v1_class_body',
  'toV1NamedReceiver' => 'to_v1_named_receiver',
  _ => throw StateError('unknown projection $name'),
};

/// A child of a node in the V1 view, as Rust: an expression of type
/// `NodeId` (or `TokenId`), or of type `Vec<NodeId>` for a list.
class V1Child {
  final Kind kind;
  final String rust;

  /// Whether the child may be null (`NO_NODE`).
  final bool nullable;

  /// For a list: the Rust expression of the slice, when no projection is
  /// needed (`&self.x`).
  final String? slice;

  new(this.kind, this.rust, {this.nullable = false, this.slice});
}

/// The hand-written getters ast_v1.rs must define, `Class.getter`.
final Set<String> handGetters = {};

class V1Translator {
  final ClassInfo c;
  final Map<String, Field> fields;
  final String member;

  new(this.c, this.fields, this.member);

  Never fail(Object what) =>
      throw StateError('${c.name}.$member: cannot translate $what');

  /// The V2 field [expression] reads (`expression2`, `_expression2`).
  Field? v2Field(Expression expression) {
    if (expression is! SimpleIdentifier) return null;
    // A getter written by hand (`target2` of a projection) is not the
    // field it may share a name with.
    var found = lookupMember(c, expression.name);
    if (found != null && found.$2 is MethodDeclaration) {
      var body = (found.$2 as MethodDeclaration).body;
      if (body is! ExpressionFunctionBody ||
          body.expression is! SimpleIdentifier) {
        return null;
      }
    }
    return resolveField(c, fields, expression.name);
  }

  /// The child [name] of the V1 view, read with [kind] (from the
  /// ChildEntities method or the visit statement).
  V1Child child(String name, Kind kind) {
    var found = lookupMember(c, name);
    if (found != null) {
      var (owner, m, v) = found;
      if (m is MethodDeclaration) {
        var r = getterBody(owner, m, kind);
        if (r != null) return r;
      } else if (v != null) {
        // A field.
        var init = v.initializer;
        if (init != null && init.toSource() == 'NodeListImpl._()') {
          String bare = name.startsWith('_') ? name.substring(1) : name;
          Field? f = fields[bare];
          if (f != null) return fieldChild(f);
        } else if (init != null) {
          var call = invocation(init);
          if (call != null && call.$1 == '_V1ProjectedNodeListImpl') {
            var args = call.$2;
            Field? base = v2Field(args[0]);
            var project = args[1];
            if (base != null &&
                base.kind == Kind.nodeList &&
                project is PrefixedIdentifier &&
                project.prefix.name == 'V1Projection') {
              return V1Child(
                Kind.nodeList,
                'ast.v1_projected_list(id, &self.${base.rustName}, '
                'Ast::${projectionMethod(project.identifier.name)})',
              );
            }
          }
        } else {
          String bare = name.startsWith('_') ? name.substring(1) : name;
          Field? f = fields[bare];
          if (f != null) return fieldChild(f);
        }
      }
    }
    String bare = name.startsWith('_') ? name.substring(1) : name;
    if (found == null && fields[bare] != null) return fieldChild(fields[bare]!);
    return hand(name, kind);
  }

  V1Child fieldChild(Field f) => switch (f.kind) {
    Kind.node => V1Child(Kind.node, 'self.${f.rustName}', nullable: f.nullable),
    Kind.token => V1Child(Kind.token, 'self.${f.rustName}'),
    Kind.nodeList => V1Child(
      Kind.nodeList,
      'self.${f.rustName}.clone()',
      slice: '&self.${f.rustName}',
    ),
    Kind.tokenList => V1Child(Kind.tokenList, 'self.${f.rustName}.clone()'),
    Kind.other => fail(f.dartName),
  };

  V1Child hand(String name, Kind kind) {
    String bare = name.startsWith('_') ? 'v1_${name.substring(1)}' : name;
    handGetters.add('${c.name}.$name');
    return V1Child(kind, 'self.${snake(bare)}(ast, id)', nullable: true);
  }

  /// The child a generated getter returns, or null when the getter is
  /// written by hand.
  V1Child? getterBody(ClassInfo owner, MethodDeclaration m, Kind kind) {
    bool generated = m.metadata.any((a) => a.name.name == 'generated');
    var body = m.body;
    if (body is! ExpressionFunctionBody) return null;
    Expression e = body.expression;
    if (e is SimpleIdentifier) {
      Field? f = resolveField(c, fields, e.name);
      if (f != null) return fieldChild(f);
      return null;
    }
    bool parent = false;
    if (e is MethodInvocation &&
        e.target == null &&
        e.methodName.name == '_becomeParentOf1') {
      parent = true;
      e = e.argumentList.arguments.single as Expression;
    }
    String wrap(String projected) =>
        parent ? 'ast.become_parent_of1(id, $projected)' : projected;
    if (e is MethodInvocation &&
        e.target is SimpleIdentifier &&
        (e.target as SimpleIdentifier).name == 'V1Projection') {
      Field? f = v2Field(e.argumentList.arguments.single as Expression);
      if (f == null || f.kind != Kind.node) return null;
      return V1Child(
        Kind.node,
        wrap('ast.${projectionMethod(e.methodName.name)}(self.${f.rustName})'),
      );
    }
    if (e is SwitchExpression && e.cases.length == 2) {
      // switch (x) { var node? => V1Projection.toV1X(node), _ => null }
      Field? f = v2Field(e.expression);
      var first = e.cases[0].expression;
      if (f != null &&
          first is MethodInvocation &&
          first.target is SimpleIdentifier &&
          (first.target as SimpleIdentifier).name == 'V1Projection') {
        String method = projectionMethod(first.methodName.name);
        return V1Child(
          Kind.node,
          wrap(
            'if self.${f.rustName} != NO_NODE { '
            'ast.$method(self.${f.rustName}) } else { NO_NODE }',
          ),
          nullable: true,
        );
      }
    }
    return null;
  }

  /// `_childEntities`: statements adding to `entities`.
  List<String> childEntities(ClassInfo owner, FunctionBody body) {
    Expression? e;
    if (body is ExpressionFunctionBody) {
      e = body.expression;
    } else if (body is BlockFunctionBody) {
      var statements = body.block.statements;
      if (statements.isNotEmpty) {
        var last = statements.last;
        if (last is ReturnStatement && statements.length == 1) {
          e = last.expression;
        } else if (last is ExpressionStatement &&
            last.expression is ThrowExpression) {
          return [throwStatement(last.expression as ThrowExpression)];
        }
      }
    }
    if (e == null) fail(body);
    if (e is! CascadeExpression) {
      if (e is InstanceCreationExpression || e is MethodInvocation) return [];
      if (e is PropertyAccess && e.target is SuperExpression) {
        var found = owner.lookupGetter('_childEntities', skipSelf: true);
        if (found == null) return [];
        return childEntities(found.$1, found.$2);
      }
      fail(e);
    }
    List<String> result = [];
    Expression target = e.target;
    if (target is PropertyAccess && target.target is SuperExpression) {
      var found = owner.lookupGetter('_childEntities', skipSelf: true);
      if (found != null) result.addAll(childEntities(found.$1, found.$2));
    } else if (target is! MethodInvocation &&
        target is! InstanceCreationExpression) {
      fail(target);
    }
    for (Expression section in e.cascadeSections) {
      var call = section as MethodInvocation;
      var args = call.argumentList.arguments;
      String name = (args[0] as SimpleStringLiteral).value;
      var value = args[1];
      if (value is! SimpleIdentifier) fail(section);
      String method = call.methodName.name;
      Kind kind = switch (method) {
        'addToken' => Kind.token,
        'addNode' => Kind.node,
        'addNodeList' => Kind.nodeList,
        'addTokenList' => Kind.tokenList,
        _ => fail(section),
      };
      V1Child child = this.child(value.name, kind);
      if (child.kind != kind) fail(section);
      result.add('entities.${snake(method)}("$name", ${child.rust});');
    }
    return result;
  }

  String throwStatement(ThrowExpression t) {
    var call = t.expression;
    String kind;
    String message;
    if (call is MethodInvocation) {
      kind = call.methodName.name;
      message = (call.argumentList.arguments.first as StringLiteral)
          .toSource();
    } else if (call is InstanceCreationExpression) {
      kind = call.constructorName.type.name.lexeme;
      message = (call.argumentList.arguments.first as StringLiteral)
          .toSource();
    } else {
      fail(t);
    }
    message = message.substring(1, message.length - 1);
    message = message.replaceAll(r"\'", "'").replaceAll('"', r'\"');
    return 'panic!("$kind: $message");';
  }

  /// `visitChildren`: statements visiting the children.
  List<String> visitChildren(ClassInfo owner, FunctionBody body) {
    if (body is EmptyFunctionBody) return [];
    if (body is! BlockFunctionBody) fail(body);
    List<String> out = [];
    for (Statement s in body.block.statements) {
      if (s is ExpressionStatement && s.expression is ThrowExpression) {
        out.add(throwStatement(s.expression as ThrowExpression));
        continue;
      }
      if (s is! ExpressionStatement || s.expression is! MethodInvocation) {
        fail(s);
      }
      var call = s.expression as MethodInvocation;
      var target = call.target;
      String method = call.methodName.name;
      if (target is SuperExpression && method == 'visitChildren') {
        var found = owner.lookupMethod('visitChildren', skipSelf: true);
        if (found != null) out.addAll(visitChildren(found.$1, found.$2));
        continue;
      }
      if (target == null && method == '_visitCommentAndAnnotations') {
        out.add(
          'ast.visit_comment_and_annotations('
          'self.documentation_comment, &self.metadata, visitor);',
        );
        continue;
      }
      if (method != 'accept' || target is! SimpleIdentifier) fail(s);
      // The V1 child; its kind is that of a node unless it is a list.
      V1Child child = this.child(target.name, Kind.node);
      if (child.kind == Kind.nodeList ||
          lookupListKind(target.name)) {
        V1Child list = this.child(target.name, Kind.nodeList);
        String iter = list.slice ?? list.rust;
        out.add(
          'for element in $iter {\n'
          '            ast.accept(${list.slice != null ? '*element' : 'element'}, visitor);\n'
          '        }',
        );
      } else if (child.nullable || call.operator?.lexeme == '?.') {
        out.add(
          '{\n'
          '            let child = ${child.rust};\n'
          '            if child != NO_NODE {\n'
          '                ast.accept(child, visitor);\n'
          '            }\n'
          '        }',
        );
      } else {
        out.add('ast.accept(${child.rust}, visitor);');
      }
    }
    return out;
  }

  /// Whether [name] names a node list in the V1 view.
  bool lookupListKind(String name) {
    var found = lookupMember(c, name);
    if (found == null) {
      String bare = name.startsWith('_') ? name.substring(1) : name;
      return fields[bare]?.kind == Kind.nodeList;
    }
    var (_, m, v) = found;
    TypeAnnotation? type;
    if (m is MethodDeclaration) type = m.returnType;
    if (m is FieldDeclaration) type = m.fields.type;
    String source = type?.toSource() ?? '';
    return source.startsWith('NodeListImpl') || source.startsWith('List<');
  }

  /// `_childContainingRange` (or `_childContainingRange2` when [v2]):
  /// statements returning the child.
  List<String> childContainingRange(
    ClassInfo owner,
    FunctionBody body, {
    required bool v2,
  }) {
    String method = v2 ? '_childContainingRange2' : '_childContainingRange';
    if (body is ExpressionFunctionBody && body.expression is ThrowExpression) {
      return [throwStatement(body.expression as ThrowExpression)];
    }
    if (body is! BlockFunctionBody) fail(body);
    List<String> out = [];
    String node(String name) {
      if (v2) {
        Field? f = resolveField(c, fields, name);
        if (f == null || f.kind != Kind.node) {
          handGetters.add('${c.name}.$name#2');
          return 'self.${snake(name.startsWith('_') ? 'v2_${name.substring(1)}' : name)}(ast, id)';
        }
        return 'self.${f.rustName}';
      }
      return child(name, Kind.node).rust;
    }

    String list(String name) {
      if (v2) {
        Field? f = resolveField(c, fields, name);
        if (f == null || f.kind != Kind.nodeList) fail(name);
        return 'ast.element_containing_range(&self.${f.rustName}, range_offset, range_end)';
      }
      V1Child l = child(name, Kind.nodeList);
      if (l.slice != null) {
        return 'ast.element_containing_range(${l.slice}, range_offset, range_end)';
      }
      // A projected list searches its base, then projects what it finds.
      var found = lookupMember(c, name);
      var call = found?.$3?.initializer == null
          ? null
          : invocation(found!.$3!.initializer!);
      if (call != null &&
          call.$1 == '_V1ProjectedNodeListImpl' &&
          call.$2[1] is PrefixedIdentifier) {
        var args = call.$2;
        Field base = v2Field(args[0])!;
        var project = args[1] as PrefixedIdentifier;
        return 'ast.v1_projected_element_containing_range(id, &self.${base.rustName}, '
            'Ast::${projectionMethod(project.identifier.name)}, range_offset, range_end)';
      }
      handGetters.add('${c.name}.$name#range');
      return 'self.${snake(name.startsWith('_') ? 'v1_${name.substring(1)}' : name)}_element_containing_range(ast, id, range_offset, range_end)';
    }

    for (Statement s in body.block.statements) {
      String source = s.toSource();
      if (s is ReturnStatement) {
        var e = s.expression;
        if (e is NullLiteral) {
          out.add('NO_NODE');
          continue;
        }
        if (e is MethodInvocation &&
            e.methodName.name == '_elementContainingRange' &&
            e.target is SimpleIdentifier) {
          out.add(list((e.target as SimpleIdentifier).name));
          continue;
        }
        fail(source);
      }
      if (s is ExpressionStatement && s.expression is ThrowExpression) {
        out.add(throwStatement(s.expression as ThrowExpression));
        continue;
      }
      if (s is VariableDeclarationStatement &&
          s.variables.variables.single.name.lexeme == 'childFromSuper') {
        // var childFromSuper = super._childContainingRange(a, b);
        // if (childFromSuper != null) return childFromSuper;
        var found = owner.lookupMethod(method, skipSelf: true);
        if (found == null) fail(source);
        var inner = childContainingRange(found.$1, found.$2, v2: v2);
        out.add(
          '{\n'
          '            let result = (|| -> NodeId {\n'
          '                ${inner.join('\n                ')}\n'
          '            })();\n'
          '            if result != NO_NODE {\n'
          '                return result;\n'
          '            }\n'
          '        }',
        );
        continue;
      }
      if (s is IfStatement &&
          s.expression.toSource() == 'childFromSuper != null') {
        continue;
      }
      if (s is IfStatement &&
          s.expression is BinaryExpression &&
          (s.expression as BinaryExpression).operator.lexeme == '!=' &&
          (s.expression as BinaryExpression).leftOperand.toSource().contains(
            'Origin',
          )) {
        // if (_v1ProjectionOrigin != null) throw ...: only a projection
        // object has an origin.
        Statement then = s.thenStatement;
        if (then is Block) then = then.statements.single;
        out.add(
          'if ast.has_v1_origin(id) {\n'
          '            ${throwStatement((then as ExpressionStatement).expression as ThrowExpression)}\n'
          '        }',
        );
        continue;
      }
      if (s is IfStatement &&
          s.caseClause == null &&
          s.expression is BinaryExpression &&
          (s.expression as BinaryExpression).operator.lexeme == '??') {
        // if (x?._containsOffset(a, b) ?? false) return x;
        var left = (s.expression as BinaryExpression).leftOperand;
        if (left is MethodInvocation &&
            left.methodName.name == '_containsOffset' &&
            left.target is SimpleIdentifier) {
          String x = node((left.target as SimpleIdentifier).name);
          out.add(
            '{\n'
            '            let child = $x;\n'
            '            if child != NO_NODE && ast.contains_offset(child, range_offset, range_end) {\n'
            '                return child;\n'
            '            }\n'
            '        }',
          );
          continue;
        }
      }
      if (s is IfStatement) {
        var cond = s.expression;
        var caseClause = s.caseClause;
        Statement then = s.thenStatement;
        if (then is Block && then.statements.length == 1) {
          then = then.statements.single;
        }
        if (caseClause == null &&
            cond is MethodInvocation &&
            cond.methodName.name == '_containsOffset' &&
            cond.target is SimpleIdentifier) {
          // if (x._containsOffset(a, b)) return x;
          String x = node((cond.target as SimpleIdentifier).name);
          out.add(
            '{\n'
            '            let child = $x;\n'
            '            if ast.contains_offset(child, range_offset, range_end) {\n'
            '                return child;\n'
            '            }\n'
            '        }',
          );
          continue;
        }
        if (caseClause != null) {
          var pattern = caseClause.guardedPattern.pattern;
          if (cond is MethodInvocation &&
              cond.target is SuperExpression &&
              cond.methodName.name == method) {
            // if (super._childContainingRange(a, b) case var result?) ...
            var found = owner.lookupMethod(method, skipSelf: true);
            if (found == null) fail(source);
            var inner = childContainingRange(found.$1, found.$2, v2: v2);
            out.add(
              '{\n'
              '            let result = (|| -> NodeId {\n'
              '                ${inner.join('\n                ')}\n'
              '            })();\n'
              '            if result != NO_NODE {\n'
              '                return result;\n'
              '            }\n'
              '        }',
            );
            continue;
          }
          if (cond is MethodInvocation &&
              cond.methodName.name == '_elementContainingRange' &&
              cond.target is SimpleIdentifier) {
            String l = list((cond.target as SimpleIdentifier).name);
            out.add(
              '{\n'
              '            let result = $l;\n'
              '            if result != NO_NODE {\n'
              '                return result;\n'
              '            }\n'
              '        }',
            );
            continue;
          }
          if (cond is SimpleIdentifier && pattern is NullCheckPattern) {
            // if (x case var x?) { if (x._containsOffset(a, b)) return x; }
            String x = node(cond.name);
            out.add(
              '{\n'
              '            let child = $x;\n'
              '            if child != NO_NODE && ast.contains_offset(child, range_offset, range_end) {\n'
              '                return child;\n'
              '            }\n'
              '        }',
            );
            continue;
          }
        }
      }
      fail(source);
    }
    if (out.isEmpty || !out.last.startsWith('NO_NODE') && !out.last.startsWith('panic') && !out.last.startsWith('ast.')) {
      if (out.isEmpty || !out.last.startsWith('NO_NODE')) {
        // Falls off the end only after a return in every path upstream.
      }
    }
    return out;
  }
}

/// Hand translations of V1 members, keyed by `Class.member`: Rust
/// statements (for `_childEntities`, `visitChildren`,
/// `_childContainingRange`) that the translator cannot produce.
const Map<String, String> handV1 = {};

/// The value of `_astNodeApi` of [c], as Rust.
String apiOf(ClassInfo c) {
  var found = c.lookupGetter('_astNodeApi');
  if (found == null) return 'AstNodeApi::shared';
  var body = found.$2;
  if (body is ExpressionFunctionBody) {
    var e = body.expression;
    if (e is PrefixedIdentifier && e.prefix.name == 'AstNodeApi') {
      return 'AstNodeApi::${e.identifier.name}';
    }
    if (e is BinaryExpression &&
        e.operator.lexeme == '??' &&
        e.rightOperand.toSource() == 'AstNodeApi.shared') {
      // `_astNodeApiOverride ?? AstNodeApi.shared`: the override is in the
      // store.
      return 'AstNodeApi::shared';
    }
    if (c.name == 'FunctionExpressionImpl') {
      // `_v1ProjectionOrigin == null ? AstNodeApi.shared : AstNodeApi.v1`.
      return 'if id >= V1_BASE { AstNodeApi::v1 } else { AstNodeApi::shared }';
    }
  }
  throw StateError('${c.name}._astNodeApi: cannot translate $body');
}

/// The visit method `accept` calls, or null when it throws.
String? acceptMethod1(ClassInfo c) {
  var accept = c.lookupMethod('accept');
  if (accept == null) return null;
  var body = accept.$2;
  if (body is ExpressionFunctionBody) {
    var e = body.expression;
    if (e is MethodInvocation &&
        e.target is SimpleIdentifier &&
        (e.target as SimpleIdentifier).name == 'visitor') {
      return e.methodName.name;
    }
  }
  return null;
}

/// Writes the V1 members of [c] into [impls].
void writeV1Members(
  ClassInfo c,
  Map<String, Field> fields,
  StringBuffer impls,
  List<String> errors,
) {
  // _childEntities
  try {
    List<String> calls;
    if (handV1.containsKey('${c.name}._childEntities')) {
      calls = [handV1['${c.name}._childEntities']!];
    } else {
      var found = c.lookupGetter('_childEntities');
      calls = found == null
          ? []
          : V1Translator(c, fields, '_childEntities').childEntities(
              found.$1,
              found.$2,
            );
    }
    impls.writeln();
    impls.writeln(
      "    pub fn child_entities1(&self, ast: Ast<'_>, id: NodeId, entities: &mut ChildEntities1) {",
    );
    impls.writeln('        let _ = (ast, id, &entities);');
    for (String call in calls) {
      impls.writeln('        $call');
    }
    impls.writeln('    }');
  } on StateError catch (_) {
    handGetters.add('${c.name}._childEntities');
    impls.writeln();
    impls.writeln(
      "    pub fn child_entities1(&self, ast: Ast<'_>, id: NodeId, entities: &mut ChildEntities1) {",
    );
    impls.writeln('        self.child_entities1_hand(ast, id, entities)');
    impls.writeln('    }');
  }

  // visitChildren
  try {
    List<String> statements;
    if (handV1.containsKey('${c.name}.visitChildren')) {
      statements = [handV1['${c.name}.visitChildren']!];
    } else {
      var found = c.lookupMethod('visitChildren');
      statements = found == null
          ? []
          : V1Translator(c, fields, 'visitChildren').visitChildren(
              found.$1,
              found.$2,
            );
    }
    impls.writeln();
    impls.writeln(
      "    pub fn visit_children1<V: AstVisitor + ?Sized>(&self, ast: Ast<'_>, id: NodeId, visitor: &mut V) {",
    );
    impls.writeln('        let _ = (ast, id, &visitor);');
    for (String s in statements) {
      impls.writeln('        $s');
    }
    impls.writeln('    }');
  } on StateError catch (_) {
    handGetters.add('${c.name}.visitChildren');
    impls.writeln();
    impls.writeln(
      "    pub fn visit_children1<V: AstVisitor + ?Sized>(&self, ast: Ast<'_>, id: NodeId, visitor: &mut V) {",
    );
    impls.writeln('        self.visit_children1_hand(ast, id, visitor)');
    impls.writeln('    }');
  }

  // _childContainingRange and _childContainingRange2
  for (var (String method, String rust, bool v2) in [
    ('_childContainingRange', 'child_containing_range1', false),
    ('_childContainingRange2', 'child_containing_range2', true),
  ]) {
    try {
      List<String> statements;
      if (handV1.containsKey('${c.name}.$method')) {
        statements = [handV1['${c.name}.$method']!];
      } else {
        var found = c.lookupMethod(method);
        statements = found == null
            ? ['NO_NODE']
            : V1Translator(c, fields, method).childContainingRange(
                found.$1,
                found.$2,
                v2: v2,
              );
      }
      impls.writeln();
      impls.writeln(
        "    pub fn $rust(&self, ast: Ast<'_>, id: NodeId, range_offset: i32, range_end: i32) -> NodeId {",
      );
      impls.writeln('        let _ = (ast, id, range_offset, range_end);');
      for (String s in statements) {
        impls.writeln('        $s');
      }
      impls.writeln('    }');
    } on StateError catch (_) {
      handGetters.add('${c.name}.$method');
      impls.writeln();
      impls.writeln(
        "    pub fn $rust(&self, ast: Ast<'_>, id: NodeId, range_offset: i32, range_end: i32) -> NodeId {",
      );
      impls.writeln('        self.${rust}_hand(ast, id, range_offset, range_end)');
      impls.writeln('    }');
    }
  }

  try {
    apiMethods[c.name] = apiOf(c);
  } on StateError catch (e) {
    errors.add(e.message);
  }
  acceptMethods1[c.name] = acceptMethod1(c);
}

final Map<String, String> apiMethods = {};
final Map<String, String?> acceptMethods1 = {};

void writeV1Dispatch(List<ClassInfo> concrete, StringBuffer out) {
  out.writeln('    /// `_astNodeApi`, without the overrides the store keeps.');
  out.writeln(
    "    pub fn ast_node_api(&self, ast: Ast<'_>, id: NodeId) -> AstNodeApi {",
  );
  out.writeln('        let _ = (ast, id);');
  out.writeln('        match self {');
  for (ClassInfo c in concrete) {
    out.writeln(
      '            AstNodeImpl::${c.name}(_) => ${apiMethods[c.name] ?? 'AstNodeApi::shared'},',
    );
  }
  out.writeln('        }');
  out.writeln('    }');
  out.writeln();
  out.writeln('    /// `accept(visitor)`: the V1 visitor\'s method for this class.');
  out.writeln(
    "    pub fn accept1<V: AstVisitor + ?Sized>(&self, ast: Ast<'_>, id: NodeId, visitor: &mut V) -> Option<V::R> {",
  );
  out.writeln('        match self {');
  for (ClassInfo c in concrete) {
    String? visit = acceptMethods1[c.name];
    if (visit == null) {
      String bare = c.name.substring(0, c.name.length - 4);
      out.writeln(
        '            AstNodeImpl::${c.name}(_) => panic!("StateError: $bare is not in the V1 AST view."),',
      );
    } else {
      out.writeln(
        '            AstNodeImpl::${c.name}(_) => visitor.${snakeVisit(visit)}(ast, id),',
      );
    }
  }
  out.writeln('        }');
  out.writeln('    }');
  out.writeln();
  for (var (String rust, String params, String args, String ret) in [
    (
      'visit_children1',
      "<V: AstVisitor + ?Sized>(&self, ast: Ast<'_>, id: NodeId, visitor: &mut V)",
      'ast, id, visitor',
      '',
    ),
    (
      'child_entities1',
      "(&self, ast: Ast<'_>, id: NodeId, entities: &mut ChildEntities1)",
      'ast, id, entities',
      '',
    ),
    (
      'child_containing_range1',
      "(&self, ast: Ast<'_>, id: NodeId, range_offset: i32, range_end: i32)",
      'ast, id, range_offset, range_end',
      ' -> NodeId',
    ),
    (
      'child_containing_range2',
      "(&self, ast: Ast<'_>, id: NodeId, range_offset: i32, range_end: i32)",
      'ast, id, range_offset, range_end',
      ' -> NodeId',
    ),
  ]) {
    out.writeln('    pub fn $rust$params$ret {');
    out.writeln('        match self {');
    for (ClassInfo c in concrete) {
      out.writeln('            AstNodeImpl::${c.name}(n) => n.$rust($args),');
    }
    out.writeln('        }');
    out.writeln('    }');
    out.writeln();
  }
}

// ---------------------------------------------------------------------------
// `replaceChild` and `removeChild`, generated upstream from the same
// annotation: a child slot is replaced through its setter, which makes the
// node the parent of the new child as the constructor does.
// ---------------------------------------------------------------------------

/// The parent helper a setter of [field] in [c] calls: `_becomeParentOf2`,
/// `_becomeParentOf12`, `_becomeParentOf2AndExisting1` or the owned view's.
String setterHelper(ClassInfo c, String setter) {
  for (ClassInfo owner in c.lookupChain) {
    for (ClassMember m in owner.members) {
      if (m is MethodDeclaration && m.isSetter && m.name.lexeme == setter) {
        var body = m.body;
        String source = body.toSource();
        for (String helper in [
          '_becomeParentOf2AndExisting1',
          '_becomeParentOf12',
          '_becomeParentOfOwnedView',
          '_becomeParentOf2',
        ]) {
          if (source.contains('$helper(')) {
            return helper;
          }
        }
        throw StateError('${c.name}.$setter: setter body $source');
      }
    }
  }
  throw StateError('${c.name}.$setter: no setter');
}

/// The method [name] a `super.name(...)` in [owner] calls, for an
/// instance of [c]: the next one after [owner] in [c]'s lookup chain.
(ClassInfo, FunctionBody)? superMethod(ClassInfo c, ClassInfo owner, String name) {
  bool seen = false;
  for (ClassInfo next in c.lookupChain) {
    if (!seen) {
      seen = identical(next, owner);
      continue;
    }
    for (ClassMember m in next.members) {
      if (m is MethodDeclaration &&
          !m.isGetter &&
          !m.isSetter &&
          m.name.lexeme == name &&
          m.body is! EmptyFunctionBody) {
        return (next, m.body);
      }
    }
  }
  return null;
}

/// The Rust of `_attach(child)` (or a setter's helper) with [helper].
String attach(String helper, String parent, String child) {
  return 'self.attach_child("$helper", tokens, $parent, $child);';
}

/// The test of `newNode as T` (or `as T?`).
String castTest(String type, String node) {
  if (type.endsWith('?')) type = type.substring(0, type.length - 1);
  return 'self.node($node).is_${snake(type)}()';
}

class MutationTranslator {
  final ClassInfo c;
  final Map<String, Field> fields;
  final String member;

  new(this.c, this.fields, this.member);

  Never fail(Object what) =>
      throw StateError('${c.name}.$member: cannot translate $what');

  String field(String name) {
    Field? f = resolveField(c, fields, name);
    if (f == null) fail(name);
    return 'self.node(parent).as_${snake(c.name)}().${f.rustName}';
  }

  String fieldMut(String name) {
    Field? f = resolveField(c, fields, name);
    if (f == null) fail(name);
    return 'self.node_mut(parent).as_${snake(c.name)}_mut().${f.rustName}';
  }

  /// The element type and attach helper of the node list [name].
  (String, String) listOf(String name) {
    String bare = name.startsWith('_') ? name.substring(1) : name;
    Field? f = resolveField(c, fields, name);
    if (f == null || f.kind != Kind.nodeList) fail(name);
    String type = f.type;
    String element = type.substring(type.indexOf('<') + 1, type.lastIndexOf('>'));
    // The constructor initializes the list with `_initialize` (the owned
    // view's helper) or `_initializeProjected`.
    String mode = '_becomeParentOfOwnedView';
    for (ClassInfo owner in c.lookupChain) {
      var ctor = owner.unnamedConstructor;
      if (ctor == null) continue;
      String source = ctor.toSource();
      if (source.contains('$bare._initializeProjected') ||
          source.contains('_$bare._initializeProjected')) {
        mode = '_becomeParentOf2AndExisting1';
      }
    }
    return (element, mode);
  }

  List<String> body(ClassInfo owner, FunctionBody body, bool replace) {
    if (body is! BlockFunctionBody) fail(body);
    List<String> out = [];
    for (Statement s in body.block.statements) {
      String source = s.toSource();
      if (s is ExpressionStatement && s.expression is ThrowExpression) {
        out.add(V1Translator(c, fields, member)
            .throwStatement(s.expression as ThrowExpression));
        continue;
      }
      if (s is IfStatement &&
          s.expression.toSource() == '_v1ProjectionOrigin != null') {
        out.add(
          'if parent >= V1_BASE {\n'
          '            panic!("UnsupportedError: A V1 projection cannot be mutated.");\n'
          '        }',
        );
        continue;
      }
      if (s is ExpressionStatement &&
          s.expression is MethodInvocation &&
          (s.expression as MethodInvocation).target is SuperExpression) {
        var found = superMethod(c, owner, member);
        if (found == null) fail(source);
        out.addAll(this.body(found.$1, found.$2, replace));
        continue;
      }
      if (s is! IfStatement) fail(source);
      var cond = s.expression;
      Statement then = s.thenStatement;
      List<Statement> thens = then is Block ? then.statements : [then];
      if (cond is MethodInvocation &&
          cond.methodName.name == 'identical' &&
          cond.argumentList.arguments.length == 2) {
        String a = cond.argumentList.arguments[0].toSource();
        String b = cond.argumentList.arguments[1].toSource();
        if (a == 'oldNode' && b == 'newNode') {
          out.add('if old == new_ {\n            return;\n        }');
          continue;
        }
        if (b != 'oldNode') fail(source);
        String x = a;
        var first = thens.first;
        if (first is ExpressionStatement && first.expression is ThrowExpression) {
          out.add(
            'if ${field(x)} == old {\n'
            '            ${V1Translator(c, fields, member).throwStatement(first.expression as ThrowExpression)}\n'
            '        }',
          );
          continue;
        }
        if (first is ExpressionStatement &&
            first.expression is AssignmentExpression) {
          var assignment = first.expression as AssignmentExpression;
          String setter = assignment.leftHandSide.toSource();
          var value = assignment.rightHandSide;
          String helper = setterHelper(c, setter);
          String extra = switch (setter) {
            'constructorSelector' =>
              '\n            self.set_api_override(new_, AstNodeApi::v2);',
            'delimitedFormalParameters' =>
              '\n            for p in self.node(new_).as_delimited_formal_parameters_impl().formal_parameters.clone() {\n'
                  '                self.set_parent1(p, parent);\n'
                  '            }',
            _ => '',
          };
          if (value is NullLiteral) {
            out.add(
              'if ${field(x)} == old {\n'
              '            ${fieldMut(x)} = NO_NODE;\n'
              '            return;\n'
              '        }',
            );
            continue;
          }
          if (value is AsExpression) {
            String type = value.type.toSource();
            out.add(
              'if ${field(x)} == old {\n'
              '            if !${castTest(type, 'new_')} {\n'
              '                panic!("TypeError");\n'
              '            }\n'
              '            ${fieldMut(x)} = new_;\n'
              '            ${attach(helper, 'parent', 'new_')}$extra\n'
              '            return;\n'
              '        }',
            );
            continue;
          }
        }
        fail(source);
      }
      if (cond is MethodInvocation &&
          cond.target is SimpleIdentifier &&
          (cond.methodName.name == 'containsChild' ||
              cond.methodName.name == 'replaceChild')) {
        String list = (cond.target as SimpleIdentifier).name;
        Field? f = resolveField(c, fields, list);
        if (f == null) fail(source);
        String read = 'self.node(parent).as_${snake(c.name)}().${f.rustName}';
        if (cond.methodName.name == 'containsChild') {
          var first = thens.first as ExpressionStatement;
          out.add(
            'if $read.contains(&old) {\n'
            '            ${V1Translator(c, fields, member).throwStatement(first.expression as ThrowExpression)}\n'
            '        }',
          );
          continue;
        }
        var (element, mode) = listOf(list);
        out.add(
          'if let Some(i) = $read.iter().position(|&e| e == old) {\n'
          '            if !${castTest(element, 'new_')} {\n'
          '                panic!("TypeError");\n'
          '            }\n'
          '            self.node_mut(parent).as_${snake(c.name)}_mut().${f.rustName}[i] = new_;\n'
          '            ${attach(mode, 'parent', 'new_')}\n'
          '            return;\n'
          '        }',
        );
        continue;
      }
      fail(source);
    }
    return out;
  }
}

/// Hand translations of mutations, keyed by `Class.member`.
const Map<String, String> handMutations = {
  // A projection object is mutated through the slots of the store
  // (`AstStore::set_named_type_child`); one with an origin throws.
  'NamedTypeImpl.replaceChild': '''
let ast = Ast::new(self, tokens);
        let n = self.node(parent).as_named_type_impl();
        let import_prefix = if parent >= V1_BASE { n.import_prefix(ast, parent) } else { n.import_prefix };
        if import_prefix == old {
            if !self.node(new_).is_import_prefix_reference_impl() {
                panic!("TypeError");
            }
            self.set_named_type_child(tokens, parent, true, new_);
            return;
        }
        let ast = Ast::new(self, tokens);
        let n = self.node(parent).as_named_type_impl();
        let type_arguments = if parent >= V1_BASE { n.type_arguments(ast, parent) } else { n.type_arguments };
        if type_arguments == old {
            if !self.node(new_).is_type_argument_list_impl() {
                panic!("TypeError");
            }
            self.set_named_type_child(tokens, parent, false, new_);
            return;
        }
        panic!("ArgumentError: The old node is not a child of this node.");''',
  'NamedTypeImpl.removeChild': '''
let ast = Ast::new(self, tokens);
        let n = self.node(parent).as_named_type_impl();
        let import_prefix = if parent >= V1_BASE { n.import_prefix(ast, parent) } else { n.import_prefix };
        if import_prefix == old {
            self.set_named_type_child(tokens, parent, true, NO_NODE);
            return;
        }
        let ast = Ast::new(self, tokens);
        let n = self.node(parent).as_named_type_impl();
        let type_arguments = if parent >= V1_BASE { n.type_arguments(ast, parent) } else { n.type_arguments };
        if type_arguments == old {
            self.set_named_type_child(tokens, parent, false, NO_NODE);
            return;
        }
        panic!("ArgumentError: The old node is not a child of this node.");''',
  // Upstream throws first for a V1 projection (an origin), else mutates
  // the slots as generated.
  'CascadeSectionImpl.replaceChild': '''
if self.node(parent).as_cascade_section_impl().body == old {
            if !self.node(new_).is_expression_impl() {
                panic!("TypeError");
            }
            self.node_mut(parent).as_cascade_section_impl_mut().body = new_;
            self.attach_child("_becomeParentOf2", tokens, parent, new_);
            // if (parent2 case CascadeExpressionImpl cascade) cascade._becomeParentOf1(V1Projection._existingNode(body));
            let cascade = self.parents[parent as usize];
            if cascade != NO_NODE && matches!(self.node(cascade), AstNodeImpl::CascadeExpressionImpl(_)) {
                let ast = Ast::new(self, tokens);
                let existing = ast.existing_node(new_);
                ast.become_parent_of1(cascade, existing);
            }
            return;
        }
        panic!("ArgumentError: The old node is not a child of this node.");''',
};

void writeMutations(List<ClassInfo> concrete, StringBuffer out, List<String> errors) {
  StringBuffer methods = StringBuffer();
  out.writeln('impl AstStore {');
  for (var (String member, String rust, String params, String args) in [
    ('replaceChild', 'replace_child', 'old: NodeId, new_: NodeId', 'old, new_'),
    ('removeChild', 'remove_child', 'old: NodeId', 'old'),
  ]) {
    out.writeln('    /// `parent.$member($args)`.');
    out.writeln(
      '    pub fn $rust(&mut self, tokens: &TokenStore, parent: NodeId, $params) {',
    );
    out.writeln('        match self.node(parent) {');
    for (ClassInfo c in concrete) {
      String fn = '${rust}_${snake(c.name)}';
      out.writeln(
        '            AstNodeImpl::${c.name}(_) => self.$fn(tokens, parent, $args),',
      );
      List<String> statements;
      String? hand = handMutations['${c.name}.$member'];
      if (isV1Only(c)) {
        statements = ['panic!("UnsupportedError: A V1 projection cannot be mutated.");'];
      } else if (hand != null) {
        statements = [hand];
      } else {
        var found = c.lookupMethod(member);
        Map<String, Field> fields = {
          for (Field f in fieldsOf(c)) f.dartName: f,
        };
        try {
          statements = found == null
              ? ['panic!("ArgumentError: The old node is not a child of this node.");']
              : MutationTranslator(c, fields, member).body(found.$1, found.$2, member == 'replaceChild');
        } on StateError catch (e) {
          errors.add(e.message);
          statements = ['todo!()'];
        }
      }
      methods.writeln();
      methods.writeln('    /// `${c.name}.$member`.');
      methods.writeln(
        '    fn $fn(&mut self, tokens: &TokenStore, parent: NodeId, $params) {',
      );
      methods.writeln('        let _ = tokens;');
      for (String s in statements) {
        methods.writeln('        $s');
      }
      methods.writeln('    }');
    }
    out.writeln('        }');
    out.writeln('    }');
    out.writeln();
  }
  out.write(methods);
  out.writeln('}');
  out.writeln();
}
