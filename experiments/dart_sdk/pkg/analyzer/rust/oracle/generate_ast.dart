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

/// The fields of concrete class [c]: its constructor parameters.
List<Field> fieldsOf(ClassInfo c) {
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
  return getter.$2.toSource().contains('AstNodeApi.v1');
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
          !isV1Only(c) &&
          built.contains(c.name))
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
    for (var (String getter, String rust) in [
      ('beginToken', 'begin_token'),
      ('endToken', 'end_token'),
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
          '    pub fn $rust(&self, ast: &AstStore, tokens: &TokenStore) '
          '-> TokenId {',
        );
        impls.writeln('        $body');
        impls.writeln('    }');
        impls.writeln();
      } on StateError catch (e) {
        errors.add(e.message);
      }
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
    impls.writeln('}');
    impls.writeln();
  }

  out.writeln('/// Every node class, `AstNodeImpl` and its subclasses upstream.');
  out.writeln('#[derive(Clone, Debug)]');
  out.writeln('pub enum AstNodeImpl {');
  for (ClassInfo c in concrete) {
    out.writeln('    ${c.name}(${c.name}),');
  }
  out.writeln('}');
  out.writeln();
  for (ClassInfo c in concrete) {
    out.writeln('impl From<${c.name}> for AstNodeImpl {');
    out.writeln('    fn from(node: ${c.name}) -> AstNodeImpl {');
    out.writeln('        AstNodeImpl::${c.name}(node)');
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
        '            AstNodeImpl::${c.name}(n) => n.$rust(ast, tokens),',
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
      if (c.name.endsWith('Impl') && isAstNode(c) && !isV1Only(c)) c,
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

  if (unknownTypes.isNotEmpty) errors.add("unknown types: $unknownTypes");
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    stderr.writeln('${errors.length} members not translated');
    exitCode = 1;
  }
  File(args[1]).writeAsStringSync(out.toString());
}

const String header = '''
// Port of lib/src/dart/ast/ast.dart, the node classes.
//
// Generated by oracle/generate_ast.dart from ast.dart: do not edit; run the
// generator again when ast.dart changes (see ../../../../README.md).
//
// Every node class the AstBuilder builds is a struct holding its
// constructor's parameters, and `AstNodeImpl` (upstream's base class) is the
// enum of them all. Nodes live in an `AstStore` (ast_store.rs) addressed by
// `NodeId`s, as tokens live in a `TokenStore`; `NO_NODE` is null.
// `beginToken`, `endToken` and `_childEntities2` are translated from
// upstream's bodies; `is XImpl` and `as XImpl` are `is_x_impl` and `as_x_impl`.
// Classes that exist only in the V1 view of the AST, which upstream projects
// from these, are not ported.
#![allow(clippy::all)]
#![allow(non_snake_case, non_camel_case_types, unused_variables)]

use fe_analyzer_shared::scanner::token::{NO_TOKEN, TokenId, TokenStore};

use crate::src::dart::ast::ast_store::{AstStore, ChildEntities, NO_NODE, NodeId, NodeListImpl};
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
