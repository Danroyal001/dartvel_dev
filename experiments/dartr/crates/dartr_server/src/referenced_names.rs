// Dart source: pkg/analyzer/lib/src/dart/analysis/referenced_names.dart

//! Dart `computeReferencedNames`: the external names a unit references (the
//! `FileState.referencedNames` that a search uses to choose the files it
//! indexes). Names declared in an enclosing scope of the unit (top-level
//! declarations, class members, parameters, type parameters and block
//! locals) and import prefixes are left out, unless qualified.

use std::collections::HashSet;

use dartr_ast::*;
use dartr_resolver::error::support;
use dartr_syntax::TokenId;

/// Dart `computeReferencedNames(unit)` (without the names of analyzer test
/// expectations, which Dart only reads in `/pkg/analyzer/test/`).
pub fn compute_referenced_names(ast: &Ast, unit: Id<CompilationUnit>) -> HashSet<String> {
    let mut c = Computer {
        names: HashSet::new(),
        import_prefix_names: HashSet::new(),
        scopes: Vec::new(),
    };
    ast.accept(unit, &mut c);
    c.names
}

/// Dart `_LocalNameScope`, as a stack of name sets.
struct Computer {
    names: HashSet<String>,
    import_prefix_names: HashSet<String>,
    scopes: Vec<HashSet<String>>,
}

fn lexeme(ast: &Ast, token: TokenId) -> String {
    ast.tokens.lexeme(token).to_string()
}

fn add_variable_names(ast: &Ast, scope: &mut HashSet<String>, list: Id<VariableDeclarationList>) {
    for &v in ast.list_raw(ast[list].variables) {
        if let Some(v) = ast.cast::<VariableDeclaration>(v) {
            scope.insert(lexeme(ast, ast[v].name));
        }
    }
}

fn add_type_parameters(
    ast: &Ast,
    scope: &mut HashSet<String>,
    list: Option<Id<TypeParameterList>>,
) {
    if let Some(list) = list {
        for &p in ast.list_raw(ast[list].type_parameters) {
            if let Some(p) = ast.cast::<TypeParameter>(p) {
                scope.insert(lexeme(ast, ast[p].name));
            }
        }
    }
}

/// Dart `FormalParameter.name`.
fn formal_parameter_name(ast: &Ast, p: NodeId) -> Option<TokenId> {
    if let Some(r) = ast.cast::<RegularFormalParameter>(p) {
        return ast[r].name;
    }
    if let Some(f) = ast.cast::<FieldFormalParameter>(p) {
        return Some(ast[f].name);
    }
    ast.cast::<SuperFormalParameter>(p).map(|s| ast[s].name)
}

fn add_formal_parameters(
    ast: &Ast,
    scope: &mut HashSet<String>,
    list: Option<Id<FormalParameterList>>,
) {
    if let Some(list) = list {
        for &p in ast.list_raw(ast[list].parameters) {
            if let Some(name) = formal_parameter_name(ast, p) {
                scope.insert(lexeme(ast, name));
            }
        }
    }
}

/// `namePart.typeParameters`.
fn name_part_type_parameters(ast: &Ast, part: Id<ClassNamePart>) -> Option<Id<TypeParameterList>> {
    if let Some(p) = ast.cast::<NameWithTypeParameters>(part) {
        return ast[p].type_parameters;
    }
    ast.cast::<PrimaryConstructorDeclaration>(part)
        .and_then(|p| ast[p].type_parameters)
}

/// The fields and methods of a class body (Dart `_LocalNameScope.forClass`
/// and `forExtensionType`).
fn add_members(ast: &Ast, scope: &mut HashSet<String>, body: Id<ClassBody>) {
    let Some(body) = ast.cast::<BlockClassBody>(body) else {
        return;
    };
    for &member in ast.list_raw(ast[body].members) {
        if let Some(f) = ast.cast::<FieldDeclaration>(member) {
            add_variable_names(ast, scope, ast[f].fields);
        } else if let Some(m) = ast.cast::<MethodDeclaration>(member) {
            scope.insert(lexeme(ast, ast[m].name));
        }
    }
}

impl Computer {
    fn contains(&self, name: &str) -> bool {
        self.scopes.iter().any(|s| s.contains(name))
    }

    fn with_scope(&mut self, scope: HashSet<String>, f: impl FnOnce(&mut Self)) {
        self.scopes.push(scope);
        f(self);
        self.scopes.pop();
    }

    /// Dart `_addIfNotShadowed`.
    fn add_if_not_shadowed(&mut self, name: String, has_import_prefix: bool) {
        if self.contains(&name) && !has_import_prefix {
            return;
        }
        if self.import_prefix_names.contains(&name) {
            return;
        }
        self.names.insert(name);
    }
}

/// Dart `SimpleIdentifier.isQualified`.
fn is_qualified(ast: &Ast, node: Id<SimpleIdentifier>) -> bool {
    let Some(parent) = ast.parent(node) else {
        return false;
    };
    if let Some(p) = ast.cast::<PrefixedIdentifier>(parent) {
        return ast[p].identifier == node;
    }
    if let Some(p) = ast.cast::<PropertyAccess>(parent) {
        return ast[p].property_name == node;
    }
    if let Some(p) = ast.cast::<ConstructorName>(parent) {
        return ast[p].name == Some(node);
    }
    if let Some(p) = ast.cast::<MethodInvocation>(parent) {
        // `realTarget != null`: a target, or the target of the cascade.
        let cascaded = ast[p]
            .operator
            .is_some_and(|o| matches!(ast.tokens.lexeme(o), ".." | "?.."));
        return ast[p].method_name == node && (ast[p].target.is_some() || cascaded);
    }
    false
}

impl AstVisitor for Computer {
    fn visit_block(&mut self, ast: &Ast, node: Id<Block>) {
        let mut scope = HashSet::new();
        for &s in ast.list_raw(ast[node].statements) {
            if let Some(f) = ast.cast::<FunctionDeclarationStatement>(s) {
                let declaration = ast[f].function_declaration;
                scope.insert(lexeme(ast, ast[declaration].name));
            } else if let Some(v) = ast.cast::<VariableDeclarationStatement>(s) {
                add_variable_names(ast, &mut scope, ast[v].variables);
            }
        }
        self.with_scope(scope, |c| ast.visit_children(node, c));
    }

    fn visit_class_declaration(&mut self, ast: &Ast, node: Id<ClassDeclaration>) {
        let mut scope = HashSet::new();
        add_type_parameters(
            ast,
            &mut scope,
            name_part_type_parameters(ast, ast[node].name_part),
        );
        add_members(ast, &mut scope, ast[node].body);
        self.with_scope(scope, |c| ast.visit_children(node, c));
    }

    fn visit_class_type_alias(&mut self, ast: &Ast, node: Id<ClassTypeAlias>) {
        let mut scope = HashSet::new();
        add_type_parameters(ast, &mut scope, ast[node].type_parameters);
        self.with_scope(scope, |c| ast.visit_children(node, c));
    }

    fn visit_compilation_unit(&mut self, ast: &Ast, node: Id<CompilationUnit>) {
        let mut scope = HashSet::new();
        for &d in ast.list_raw(ast[node].declarations) {
            if let Some(c) = ast.cast::<ClassDeclaration>(d) {
                scope.insert(lexeme(
                    ast,
                    support::class_name_token(ast, ast[c].name_part),
                ));
            } else if let Some(e) = ast.cast::<EnumDeclaration>(d) {
                scope.insert(lexeme(
                    ast,
                    support::class_name_token(ast, ast[e].name_part),
                ));
            } else if let Some(e) = ast.cast::<ExtensionDeclaration>(d) {
                if let Some(name) = ast[e].name {
                    scope.insert(lexeme(ast, name));
                }
            } else if let Some(e) = ast.cast::<ExtensionTypeDeclaration>(d) {
                scope.insert(lexeme(
                    ast,
                    support::class_name_token(ast, ast[e].name_part),
                ));
            } else if let Some(f) = ast.cast::<FunctionDeclaration>(d) {
                scope.insert(lexeme(ast, ast[f].name));
            } else if let Some(m) = ast.cast::<MixinDeclaration>(d) {
                scope.insert(lexeme(ast, ast[m].name));
            } else if let Some(v) = ast.cast::<TopLevelVariableDeclaration>(d) {
                add_variable_names(ast, &mut scope, ast[v].variables);
            } else if let Some(t) = ast.cast::<ClassTypeAlias>(d) {
                scope.insert(lexeme(ast, ast[t].name));
            } else if let Some(t) = ast.cast::<FunctionTypeAlias>(d) {
                scope.insert(lexeme(ast, ast[t].name));
            } else if let Some(t) = ast.cast::<GenericTypeAlias>(d) {
                scope.insert(lexeme(ast, ast[t].name));
            }
        }
        // Dart replaces the scope (`localScope = _LocalNameScope.forUnit`).
        self.scopes.clear();
        self.scopes.push(scope);
        ast.visit_children(node, self);
    }

    fn visit_constructor_declaration(&mut self, ast: &Ast, node: Id<ConstructorDeclaration>) {
        let mut scope = HashSet::new();
        add_formal_parameters(ast, &mut scope, Some(ast[node].parameters));
        self.with_scope(scope, |c| ast.visit_children(node, c));
    }

    fn visit_constructor_name(&mut self, ast: &Ast, node: Id<ConstructorName>) {
        if !ast
            .parent(node)
            .is_some_and(|p| ast.is::<ConstructorDeclaration>(p))
        {
            ast.visit_children(node, self);
        }
    }

    fn visit_extension_type_declaration(&mut self, ast: &Ast, node: Id<ExtensionTypeDeclaration>) {
        let mut scope = HashSet::new();
        add_type_parameters(
            ast,
            &mut scope,
            name_part_type_parameters(ast, ast[node].name_part),
        );
        add_members(ast, &mut scope, ast[node].body);
        self.with_scope(scope, |c| ast.visit_children(node, c));
    }

    fn visit_function_declaration(&mut self, ast: &Ast, node: Id<FunctionDeclaration>) {
        let mut scope = HashSet::new();
        let function = ast[node].function_expression;
        add_type_parameters(ast, &mut scope, ast[function].type_parameters);
        add_formal_parameters(ast, &mut scope, ast[function].parameters);
        self.with_scope(scope, |c| ast.visit_children(node, c));
    }

    fn visit_function_type_alias(&mut self, ast: &Ast, node: Id<FunctionTypeAlias>) {
        let mut scope = HashSet::new();
        add_type_parameters(ast, &mut scope, ast[node].type_parameters);
        self.with_scope(scope, |c| ast.visit_children(node, c));
    }

    fn visit_import_directive(&mut self, ast: &Ast, node: Id<ImportDirective>) {
        if let Some(prefix) = ast[node].prefix {
            self.import_prefix_names
                .insert(lexeme(ast, ast[prefix].token));
        }
        ast.visit_children(node, self);
    }

    fn visit_method_declaration(&mut self, ast: &Ast, node: Id<MethodDeclaration>) {
        let mut scope = HashSet::new();
        add_type_parameters(ast, &mut scope, ast[node].type_parameters);
        add_formal_parameters(ast, &mut scope, ast[node].parameters);
        self.with_scope(scope, |c| ast.visit_children(node, c));
    }

    fn visit_named_argument(&mut self, ast: &Ast, node: Id<NamedArgument>) {
        self.names.insert(lexeme(ast, ast[node].name));
        ast.visit_children(node, self);
    }

    fn visit_named_type(&mut self, ast: &Ast, node: Id<NamedType>) {
        let import_prefix = ast[node].import_prefix;
        if let Some(prefix) = import_prefix {
            // Dart: the parser cannot tell an import prefix from a
            // qualified name, so the prefix is added too.
            self.add_if_not_shadowed(lexeme(ast, ast[prefix].name), false);
        }
        self.add_if_not_shadowed(lexeme(ast, ast[node].name), import_prefix.is_some());
        ast.visit_children(node, self);
    }

    fn visit_simple_identifier(&mut self, ast: &Ast, node: Id<SimpleIdentifier>) {
        if support::in_declaration_context(ast, node) {
            return;
        }
        if let Some(parent) = ast.parent(node)
            && let Some(c) = ast.cast::<ConstructorDeclaration>(parent)
            && ast[c].type_name == Some(node)
        {
            return;
        }
        let name = lexeme(ast, ast[node].token);
        if !is_qualified(ast, node)
            && (self.contains(&name) || self.import_prefix_names.contains(&name))
        {
            return;
        }
        self.names.insert(name);
    }

    fn visit_super_formal_parameter(&mut self, ast: &Ast, node: Id<SuperFormalParameter>) {
        self.names.insert(lexeme(ast, ast[node].name));
        ast.visit_children(node, self);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The names that `computeReferencedNames` of Dart 3.13.3 gives for
    /// this unit (printed by `package:analyzer` of the SDK at 3.13.3):
    /// comments and declarations are not references, local names hide
    /// unqualified references, and the type parameters of a generic
    /// typedef are not a scope.
    #[test]
    fn referenced_names_match_dart() {
        let source = r#"
import 'dart:async' as async;
import 'dart:math';

/// A comment that mentions Hidden and Entrypoint.
typedef Fn<T> = T Function(Unknown1);
typedef void Old<U>(U u, Other1 o);
class Base<T> extends Parent with Mix1 implements Iface1 {
  final int field = top;
  Base(this.x, int p) : super(p, named: q);
  Base.named({super.key});
  int x;
  T method<M>(M m, int arg) {
    var local = arg + m.length + x + field;
    void inner() => local + other;
    inner();
    return async.Future.value(max(local, 1)) as T;
  }
  void cascade() => list..add(1)..remove(2);
}
mixin Mix1 on Object { void mm() => notShadowed; }
enum E1 { a, b }
extension Ext on String { int get size => length; }
extension type ET(int v) { int get w => v + outside; }
var top = Base<String>.named(key: 1);
void f(Base b) { b.method(1, 2); Base.named(); E1.a; Ext('x').size; const p.C(); 'interp $inStr'; }
"#;
        let parsed = dartr_ast_builder::parse_file(source, "/sample.dart", (3, 13), &[]);
        let mut names: Vec<String> = compute_referenced_names(&parsed.ast, parsed.unit)
            .into_iter()
            .collect();
        names.sort();
        assert_eq!(
            names.join(" "),
            "C Future Iface1 Object Other1 Parent String T Unknown1 a add inStr int key length \
             list max method named notShadowed other outside p q remove size v value void"
        );
    }
}
