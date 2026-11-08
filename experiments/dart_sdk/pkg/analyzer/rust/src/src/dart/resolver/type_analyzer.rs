// Port of lib/src/dart/resolver/type_analyzer.dart (with the parts of
// binary_expression_resolver.dart and logical_not_resolver.dart that record a
// type): static types for the expressions whose type no other resolution
// decides. The seven context-independent literals (BooleanLiteral,
// DoubleLiteral, NullLiteral, SimpleStringLiteral, AdjacentStrings,
// StringInterpolation, SymbolLiteral); the operator-typed expressions
// IsExpression, LogicalNot, LogicalAnd and LogicalOr (`bool`) and
// ThrowExpression and RethrowExpression (`Never`); ParenthesizedExpression,
// which takes the type of the expression it encloses when that is known; and
// IntegerLiteral (`_recordIntegerLiteralType`) where its context type comes
// from a declared type annotation or there is none (see
// [is_declared_context_integer]), with the part of `TypeNameResolver` that
// decides whether an annotation makes that context `double`; and reads of
// local variables and formal parameters declared with a type that flow
// analysis cannot promote (their declared type), with the local scopes of
// scope_analyzer.dart and scope_context.dart they are resolved in and the
// part of `NamedTypeResolver` that builds a declared type.
// Flow state, diagnostics, rewrites, integer literals in other contexts
// (arguments, operands, inferred declarations), other identifiers,
// invocations and all other expression visitors remain unported. Types are stored beside the
// AST by NodeId, as linking's annotation types are, rather than changing
// parsed nodes.
use crate::src::dart::ast::ast::{
    AssignedVariablePatternImpl as AstAssignedVariablePattern, AstNodeImpl, ForElementImpl as AstForElement,
    ForStatementImpl as AstForStatement, UnqualifiedNameAssignmentTargetImpl as AstUnqualifiedNameAssignmentTarget,
};
use crate::src::dart::ast::ast_store::{Ast, ChildValue, NO_NODE, NodeId};
use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore, FragmentId, NO_ELEMENT, NO_LIBRARY, UnitId};
use crate::src::dart::element::r#type::{FormalParameter, FunctionTypeImpl, RecordTypeImpl, TypeImpl};
use crate::src::dart::element::type_algebra::{Substitution, substitute};
use crate::src::dart::element::type_system::is_non_nullable;
use crate::src::generated::utilities_dart::ParameterKind;
use crate::src::summary2::type_builder::TypeBuilder;
use std::rc::Rc;
use crate::src::dart::element::scope::{ScopeElement, ScopeFeatures, ScopeId, Scopes};
use crate::src::dart::element::type_provider::TypeProviderImpl;
use crate::dart::analysis::features::Feature;
use fe_analyzer_shared::scanner::token::{NO_TOKEN, TokenId};
use std::collections::HashMap;

pub fn is_context_independent_literal(node: &AstNodeImpl) -> bool {
    matches!(
        node,
        AstNodeImpl::BooleanLiteralImpl(_)
            | AstNodeImpl::DoubleLiteralImpl(_)
            | AstNodeImpl::NullLiteralImpl(_)
            | AstNodeImpl::SimpleStringLiteralImpl(_)
            | AstNodeImpl::AdjacentStringsImpl(_)
            | AstNodeImpl::StringInterpolationImpl(_)
            | AstNodeImpl::SymbolLiteralImpl(_)
    )
}

/// What the type annotations of a unit are resolved against: the linked
/// element model of its library, the unit's `LibraryFragmentScope` (and
/// the instance scopes made from it), and the fragment of each declaration
/// node of the unit, which the linker parsed into the same node ids. The
/// store is mutable because type parameters declared in bodies (of local
/// functions, function expressions and generic function types) become
/// elements of it, as linking's synthetic type parameters do.
pub struct Declarations<'a> {
    pub store: &'a mut ElementStore,
    pub scopes: &'a mut Scopes,
    pub fragment_of_node: &'a HashMap<(UnitId, NodeId), FragmentId>,
    pub unit: UnitId,
}

/// The declaration a selected read of a variable finds: its element kind
/// (`LOCAL_VARIABLE` or `PARAMETER`) and the offset of its name.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VariableRead {
    pub kind: &'static str,
    pub name_offset: i32,
}

pub struct TypeAnalyzer<'a> {
    pub type_provider: &'a TypeProviderImpl,
    pub static_types: HashMap<NodeId, TypeImpl>,
    /// The reads of declared variables that flow analysis cannot promote
    /// (see [TypeAnalyzer::analyze]), with the declarations they find; each
    /// also has its declared type in [static_types].
    pub variable_reads: HashMap<NodeId, VariableRead>,
    /// `None` when the unit is analyzed without its library: a context
    /// type that an annotation gives is then unknown, and an integer literal
    /// in it is left without a type; no read of a variable is typed.
    declarations: Option<Declarations<'a>>,
    /// The scope type annotations are resolved in: the unit's
    /// `LibraryFragmentScope`, or the type parameter and instance scopes of
    /// the declaration being visited.
    scope: ScopeId,
    /// The scopes inside executables, innermost last: the `LocalScope`s of
    /// blocks, loops, catch clauses, cases and `if`-`case` statements, the
    /// `FormalParameterScope` of a body, the `ConstructorInitializerScope`
    /// of an initializer list, and the `TypeParameterScope`s of executables
    /// and function types. Each holds its bindings in the order they were
    /// added; the first of a name wins (`_addGetter`'s `??=`).
    locals: Vec<Vec<Binding>>,
    /// The context classification of each type annotation visited.
    annotation_shapes: HashMap<NodeId, Shape>,
    /// `TypeAnnotation.type` of each annotation visited with the library,
    /// and the type of each formal parameter with a function-typed suffix
    /// (keyed by the parameter).
    annotation_types: HashMap<NodeId, TypeImpl>,
    /// The local variables and formal parameters declared in bodies, by the
    /// index [variable_of_node] gives their declaring nodes.
    variables: Vec<Variable>,
    variable_of_node: HashMap<NodeId, usize>,
    /// The element of each type parameter node, and whether it was made
    /// here (and gets its bound from its annotation here).
    type_parameter_of_node: HashMap<NodeId, (ElementId, bool)>,
    /// Every read of a variable: the `ParsedUnqualifiedName` and the
    /// variable it finds.
    reads: Vec<(NodeId, usize)>,
}

/// A name a local scope declares.
#[derive(Clone, Debug)]
struct Binding {
    name: String,
    kind: BindingKind,
}

#[derive(Clone, Copy, Debug)]
enum BindingKind {
    /// A local variable or formal parameter, by its index in
    /// `TypeAnalyzer::variables`.
    Variable(usize),
    TypeParameter(ElementId),
    /// A local function, a catch or pattern variable, or a field or super
    /// formal parameter: never a selected read.
    Other,
}

/// A local variable (`LOCAL_VARIABLE`) or formal parameter (`PARAMETER`).
#[derive(Clone, Debug)]
struct Variable {
    kind: &'static str,
    name_offset: i32,
    declared: Declared,
    /// Assigned, initialized, or a for-in loop variable.
    written: bool,
    /// Read where flow analysis may promote it.
    promotable_read: bool,
}

/// Where a variable's declared type comes from.
#[derive(Clone, Copy, Debug)]
enum Declared {
    /// No annotation: not a declared variable.
    Untyped,
    /// The type `annotation_types` holds for the node: an annotation, or a
    /// formal parameter with a function-typed suffix.
    Node(NodeId),
    /// A formal parameter of a declaration, which linking typed.
    Element(ElementId),
}

/// What an annotation (or a type) is, as far as the context of an integer
/// literal can tell: `double`, `Future<S>` or `FutureOr<S>` of some `S`, any
/// other type, or unknown (the unit is analyzed without its library).
/// Nullability is irrelevant: `double?` and `FutureOr<double>?` make an
/// integer literal `double`, and `futureValueType(S?)` is
/// `futureValueType(S)`.
#[derive(Clone, Debug, PartialEq, Eq)]
enum Shape {
    Unknown,
    Double,
    Future(Box<Shape>),
    FutureOr(Box<Shape>),
    Other,
}

impl Shape {
    /// Whether an integer literal in the context [self] is a `double`
    /// (`_recordIntegerLiteralType`: `int` is not assignable to the context
    /// and `double` is). Those are exactly `double` and `FutureOr<S>` for
    /// such an `S`, of any nullability; `None` when unknown.
    fn makes_double(&self) -> Option<bool> {
        match self {
            Shape::Unknown => None,
            Shape::Double => Some(true),
            Shape::FutureOr(s) => s.makes_double(),
            Shape::Future(_) | Shape::Other => Some(false),
        }
    }

    /// [makes_double] of `FutureOr<futureValueType(self)>`, the context of a
    /// returned expression in an `async` body (`BodyInferenceContext`):
    /// `futureValueType` of `Future<S>` and `FutureOr<S>` is `S`, of
    /// `dynamic` and `void` themselves, else `Object?`.
    fn future_value_makes_double(&self) -> Option<bool> {
        match self {
            Shape::Unknown => None,
            Shape::Future(s) | Shape::FutureOr(s) => s.makes_double(),
            Shape::Double | Shape::Other => Some(false),
        }
    }
}

impl<'a> TypeAnalyzer<'a> {
    pub fn new(type_provider: &'a TypeProviderImpl) -> Self {
        Self {
            type_provider,
            static_types: HashMap::new(),
            variable_reads: HashMap::new(),
            declarations: None,
            scope: ScopeId::LibraryFragment(0),
            locals: Vec::new(),
            annotation_shapes: HashMap::new(),
            annotation_types: HashMap::new(),
            variables: Vec::new(),
            variable_of_node: HashMap::new(),
            type_parameter_of_node: HashMap::new(),
            reads: Vec::new(),
        }
    }

    /// An analyzer that resolves type annotations against [declarations].
    pub fn with_declarations(type_provider: &'a TypeProviderImpl, declarations: Declarations<'a>) -> Self {
        let scope = ScopeId::LibraryFragment(declarations.unit);
        Self {
            declarations: Some(declarations),
            scope,
            ..Self::new(type_provider)
        }
    }

    /// Visits a parsed unit, children before their parent, and records the
    /// types of the expressions listed at the top of this file. This is not a
    /// substitute for full body resolution: every other expression is left
    /// without a type rather than given a guessed one.
    ///
    /// With the library, a read of a local variable or formal parameter
    /// declared with a type annotation (or a function-typed suffix) gets its
    /// declared type, unless flow analysis may promote the variable: when a
    /// read of it is in a position that can promote ([can_promote]), or when
    /// it is written or initialized and its declared type is not
    /// non-nullable. Such variables are left out entirely.
    pub fn analyze(&mut self, ast: Ast<'_>, node: NodeId) {
        let features = match ast.node(node) {
            AstNodeImpl::CompilationUnitImpl(unit) => ScopeFeatures {
                wildcard_variables: unit.feature_set.is_enabled(Feature::wildcard_variables),
                records: unit.feature_set.is_enabled(Feature::records),
            },
            _ => ScopeFeatures { wildcard_variables: false, records: false },
        };
        self.visit(ast, node, features);
        self.record_variable_reads();
    }

    fn visit(&mut self, ast: Ast<'_>, node: NodeId, features: ScopeFeatures) {
        // visitConfiguration: upstream deliberately does not resolve children.
        // A documentation comment's references are not reads.
        if matches!(ast.node(node), AstNodeImpl::ConfigurationImpl(_) | AstNodeImpl::CommentImpl(_)) {
            return;
        }
        let outer_scope = self.scope;
        let outer_locals = self.locals.len();
        let body = self.enter_scopes(ast, node, features);
        if let AstNodeImpl::NamedTypeImpl(_)
        | AstNodeImpl::GenericFunctionTypeImpl(_)
        | AstNodeImpl::RecordTypeAnnotationImpl(_) = ast.node(node)
        {
            let shape = self.annotation_shape(ast, node);
            self.annotation_shapes.insert(node, shape);
        }
        for child in ast.named_child_entities2(node) {
            match child.value {
                ChildValue::Node(id) => self.visit_child(ast, node, id, body, features),
                ChildValue::NodeList(ids) => {
                    for &id in ids {
                        self.visit_child(ast, node, id, body, features);
                    }
                }
                _ => (),
            }
        }
        self.exit_scopes(ast, node);
        self.scope = outer_scope;
        self.locals.truncate(outer_locals);
        self.resolve_names(ast, node, features);
        let provider = self.type_provider;
        let type_ = match ast.node(node) {
            // visitBooleanLiteral, visitDoubleLiteral, visitNullLiteral.
            AstNodeImpl::BooleanLiteralImpl(_) => provider.bool_type.clone(),
            AstNodeImpl::DoubleLiteralImpl(_) => provider.double_type.clone(),
            AstNodeImpl::NullLiteralImpl(_) => provider.null_type.clone(),
            // visitSimpleStringLiteral, visitAdjacentStrings,
            // visitStringInterpolation.
            AstNodeImpl::SimpleStringLiteralImpl(_)
            | AstNodeImpl::AdjacentStringsImpl(_)
            | AstNodeImpl::StringInterpolationImpl(_) => provider.string_type.clone(),
            // visitSymbolLiteral.
            AstNodeImpl::SymbolLiteralImpl(_) => provider.symbol_type.clone(),
            // visitIntegerLiteral: `_recordIntegerLiteralType` with the
            // context type the site gives.
            AstNodeImpl::IntegerLiteralImpl(_) => {
                let makes_double = match integer_context_site(ast, node) {
                    None => return,
                    Some(IntegerContextSite::None) => Some(false),
                    Some(IntegerContextSite::Annotation(annotation)) => self.shape_of(annotation).makes_double(),
                    Some(IntegerContextSite::Return { annotation, is_async }) => {
                        let shape = self.shape_of(annotation);
                        if is_async {
                            shape.future_value_makes_double()
                        } else {
                            shape.makes_double()
                        }
                    }
                };
                match makes_double {
                    Some(true) => provider.double_type.clone(),
                    Some(false) => provider.int_type.clone(),
                    None => return,
                }
            }
            // visitIsExpression (`is` and `is!`), LogicalNotResolver, and
            // BinaryExpressionResolver._resolveLogicalExpression (`&&`, `||`):
            // `boolType`, whatever the operands resolve to.
            AstNodeImpl::IsExpressionImpl(_)
            | AstNodeImpl::LogicalNotImpl(_)
            | AstNodeImpl::LogicalAndImpl(_)
            | AstNodeImpl::LogicalOrImpl(_) => provider.bool_type.clone(),
            // visitThrowExpression, visitRethrowExpression: `bottomType`.
            AstNodeImpl::ThrowExpressionImpl(_) | AstNodeImpl::RethrowExpressionImpl(_) => {
                provider.bottom_type.clone()
            }
            // visitParenthesizedExpression: `node.expression2.typeOrThrow`.
            // Upstream always has that type; here it is known only when the
            // enclosed expression is one this file types.
            AstNodeImpl::ParenthesizedExpressionImpl(p) => {
                match self.static_types.get(&p.expression2) {
                    Some(type_) => type_.clone(),
                    None => return,
                }
            }
            _ => return,
        };
        self.static_types.insert(node, type_);
    }

    /// Visits the child [child] of [parent] in the scopes upstream visits it
    /// in, beyond those [parent] opened for all of its children: the formal
    /// parameters in [body] (`FormalParameterScope`) and in a constructor's
    /// initializers (`ConstructorInitializerScope`), the pattern variables of
    /// an `if`-`case` in its guard and its then branch, those of a switch
    /// case in its guard and of its group in the group's statements, and the
    /// scope of a statement that is a branch or loop body but not a block
    /// (`_visitStatementInScope`).
    fn visit_child(&mut self, ast: Ast<'_>, parent: NodeId, child: NodeId, body: NodeId, features: ScopeFeatures) {
        let mark = self.locals.len();
        if child == body {
            let layer = self.parameter_bindings(ast, parent, false, features);
            self.locals.push(layer);
        }
        let statement_body = match ast.node(parent) {
            AstNodeImpl::ConstructorDeclaration2Impl(d) => {
                if d.initializers.iter().any(|&i| i == child) {
                    let layer = self.parameter_bindings(ast, parent, true, features);
                    self.locals.push(layer);
                }
                false
            }
            AstNodeImpl::IfStatementImpl(s) => {
                if s.case_clause != NO_NODE && (child == s.case_clause || child == s.then_statement2) {
                    let layer = case_clause_bindings(ast, s.case_clause);
                    self.locals.push(layer);
                }
                child == s.then_statement2 || child == s.else_statement2
            }
            AstNodeImpl::IfElementImpl(e) => {
                if e.case_clause != NO_NODE && (child == e.case_clause || child == e.then_element2) {
                    let layer = case_clause_bindings(ast, e.case_clause);
                    self.locals.push(layer);
                }
                false
            }
            AstNodeImpl::WhileStatementImpl(s) => child == s.body2,
            AstNodeImpl::DoStatementImpl(s) => child == s.body2,
            AstNodeImpl::ForStatementImpl(s) => child == s.body2,
            AstNodeImpl::SwitchPatternCaseImpl(_) | AstNodeImpl::SwitchCaseImpl(_) | AstNodeImpl::SwitchDefaultImpl(_) => {
                let (guarded_pattern, statements) = switch_member_parts(ast, parent);
                if child == guarded_pattern {
                    let mut layer = Vec::new();
                    pattern_bindings(ast, guarded_pattern, &mut layer);
                    self.locals.push(layer);
                } else if statements.contains(&child) {
                    // The group's statements: its joined pattern variables and
                    // the locals of its statements.
                    let mut layer = self.define_local_elements(ast, &statements, features);
                    let switch = ast.parent2(parent);
                    for member in switch_group(ast, switch, parent) {
                        let (guarded_pattern, _) = switch_member_parts(ast, member);
                        if guarded_pattern != NO_NODE {
                            pattern_bindings(ast, guarded_pattern, &mut layer);
                        }
                    }
                    self.locals.push(layer);
                }
                false
            }
            _ => false,
        };
        if statement_body && !matches!(ast.node(child), AstNodeImpl::BlockImpl(_)) {
            let layer = self.define_local_elements(ast, &[child], features);
            self.locals.push(layer);
        }
        self.visit(ast, child, features);
        self.locals.truncate(mark);
    }

    /// The shape recorded for the annotation [node]: unknown if it was not
    /// visited.
    fn shape_of(&self, node: NodeId) -> Shape {
        self.annotation_shapes.get(&node).cloned().unwrap_or(Shape::Unknown)
    }

    /// Enters the scopes [node] opens for its children, as `ScopeAnalyzer`
    /// and `ScopeContext` do, and returns the child in which its formal
    /// parameters are in scope (its body), or `NO_NODE`.
    fn enter_scopes(&mut self, ast: Ast<'_>, node: NodeId, features: ScopeFeatures) -> NodeId {
        let (type_parameters, body) = match ast.node(node) {
            AstNodeImpl::ClassDeclaration2Impl(_)
            | AstNodeImpl::MixinDeclaration2Impl(_)
            | AstNodeImpl::EnumDeclaration2Impl(_)
            | AstNodeImpl::ExtensionTypeDeclaration2Impl(_) => {
                self.enter_instance(node, true, features);
                return NO_NODE;
            }
            AstNodeImpl::ExtensionDeclaration2Impl(_) => {
                self.enter_instance(node, false, features);
                return NO_NODE;
            }
            AstNodeImpl::TopLevelFunctionDeclarationImpl(d) => (d.type_parameters, d.body),
            AstNodeImpl::MethodDeclaration2Impl(d) => (d.type_parameters, d.body),
            AstNodeImpl::LocalFunctionDeclarationImpl(d) => (d.type_parameters, d.body),
            AstNodeImpl::FunctionExpressionImpl(d) => (d.type_parameters, d.body),
            AstNodeImpl::SetterDeclarationImpl(d) => (NO_NODE, d.body),
            AstNodeImpl::TopLevelSetterDeclarationImpl(d) => (NO_NODE, d.body),
            AstNodeImpl::OperatorDeclarationImpl(d) => (NO_NODE, d.body),
            AstNodeImpl::ConstructorDeclaration2Impl(d) => (NO_NODE, d.body),
            // withTypeParameterList of a function type, and of a formal
            // parameter's function-typed suffix (around its return type).
            AstNodeImpl::GenericFunctionTypeImpl(g) => (g.type_parameters, NO_NODE),
            AstNodeImpl::RegularFormalParameterImpl(p) if p.function_typed_suffix != NO_NODE => {
                let suffix = ast.node(p.function_typed_suffix).as_function_typed_formal_parameter_suffix_impl();
                (suffix.type_parameters, NO_NODE)
            }
            AstNodeImpl::BlockImpl(b) => {
                let statements: Vec<NodeId> = b.statements2.iter().copied().collect();
                let layer = self.define_local_elements(ast, &statements, features);
                self.locals.push(layer);
                return NO_NODE;
            }
            AstNodeImpl::ForStatementImpl(AstForStatement { for_loop_parts, .. })
            | AstNodeImpl::ForElementImpl(AstForElement { for_loop_parts, .. }) => {
                // `_visitForLoopParts`: declared variables are in scope in
                // the whole loop; a for-in variable is added once its
                // iterable is visited (see [exit_scopes]).
                let mut layer = Vec::new();
                match ast.node(*for_loop_parts) {
                    AstNodeImpl::ForPartsWithDeclarationsImpl(p) => {
                        let declaration = p.variables2;
                        self.declare_variables(ast, declaration, features, &mut layer);
                    }
                    AstNodeImpl::ForPartsWithPatternImpl(p) => {
                        let pattern = ast.node(p.variables).as_pattern_variable_declaration_impl().pattern;
                        pattern_bindings(ast, pattern, &mut layer);
                    }
                    _ => (),
                }
                self.locals.push(layer);
                return NO_NODE;
            }
            AstNodeImpl::CatchClauseImpl(c) => {
                let mut layer = Vec::new();
                for parameter in [c.exception_parameter, c.stack_trace_parameter] {
                    if parameter != NO_NODE {
                        let name = ast.node(parameter).as_catch_clause_parameter_impl().name;
                        layer.push(Binding { name: ast.tokens.lexeme_string(name), kind: BindingKind::Other });
                    }
                }
                self.locals.push(layer);
                return NO_NODE;
            }
            AstNodeImpl::SwitchExpressionCaseImpl(c) => {
                let mut layer = Vec::new();
                pattern_bindings(ast, c.guarded_pattern, &mut layer);
                self.locals.push(layer);
                return NO_NODE;
            }
            _ => return NO_NODE,
        };
        let layer = self.type_parameter_bindings(ast, type_parameters, features);
        self.locals.push(layer);
        body
    }

    /// What [node] does once its children are visited, in its own scopes:
    /// the type of an annotation, the bound of a type parameter declared in
    /// a body, the type of a formal parameter with a function-typed suffix,
    /// and the binding of a for-in loop variable in the loop's scope.
    fn exit_scopes(&mut self, ast: Ast<'_>, node: NodeId) {
        if self.declarations.is_none() {
            return;
        }
        match ast.node(node) {
            AstNodeImpl::NamedTypeImpl(_)
            | AstNodeImpl::GenericFunctionTypeImpl(_)
            | AstNodeImpl::RecordTypeAnnotationImpl(_) => {
                let type_ = self.annotation_type(ast, node);
                self.annotation_types.insert(node, type_);
            }
            AstNodeImpl::TypeParameterImpl(p) => {
                if let Some(&(element, true)) = self.type_parameter_of_node.get(&node) {
                    if p.bound != NO_NODE {
                        let bound = self.annotation_types.get(&p.bound).cloned();
                        let store = &mut *self.declarations.as_mut().unwrap().store;
                        store.elements[element as usize].type_ = bound;
                    }
                }
            }
            AstNodeImpl::RegularFormalParameterImpl(p) if p.function_typed_suffix != NO_NODE => {
                let suffix = ast.node(p.function_typed_suffix).as_function_typed_formal_parameter_suffix_impl();
                let type_ = self.function_type(ast, suffix.type_parameters, suffix.formal_parameters, p.type_, suffix.question);
                self.annotation_types.insert(node, type_);
            }
            _ => (),
        }
    }

    /// Resolves the names [node] reads, writes or declares in the scopes it
    /// is in: reads (`ParsedUnqualifiedName`), writes (assignment targets,
    /// assigned variable patterns, initializers), and for-in variables, which
    /// the enclosing loop's scope gets once the iterable is visited.
    fn resolve_names(&mut self, ast: Ast<'_>, node: NodeId, features: ScopeFeatures) {
        match ast.node(node) {
            AstNodeImpl::ParsedUnqualifiedNameImpl(n) => {
                if let Some(BindingKind::Variable(id)) = self.lookup_binding(&ast.tokens.lexeme_string(n.name)) {
                    self.reads.push((node, id));
                    if can_promote(ast, node) {
                        self.variables[id].promotable_read = true;
                    }
                }
            }
            AstNodeImpl::UnqualifiedNameAssignmentTargetImpl(AstUnqualifiedNameAssignmentTarget { name })
            | AstNodeImpl::AssignedVariablePatternImpl(AstAssignedVariablePattern { name }) => {
                if let Some(BindingKind::Variable(id)) = self.lookup_binding(&ast.tokens.lexeme_string(*name)) {
                    self.variables[id].written = true;
                }
            }
            AstNodeImpl::LocalVariableImpl(v) => {
                // Initialization promotes as an assignment does.
                if v.initializer != NO_NODE {
                    if let Some(&id) = self.variable_of_node.get(&node) {
                        self.variables[id].written = true;
                    }
                }
            }
            AstNodeImpl::ForEachPartsWithDeclarationImpl(p) => {
                let variable = p.loop_variable;
                let d = ast.node(variable).as_declared_identifier_impl();
                let declared = if d.type_ != NO_NODE { Declared::Node(d.type_) } else { Declared::Untyped };
                if let Some(binding) = self.variable_binding(ast, variable, d.name, "LOCAL_VARIABLE", declared, features) {
                    if let BindingKind::Variable(id) = binding.kind {
                        self.variables[id].written = true;
                    }
                    if let Some(layer) = self.locals.last_mut() {
                        layer.push(binding);
                    }
                }
            }
            AstNodeImpl::ForEachPartsWithPatternImpl(p) => {
                let mut bindings = Vec::new();
                pattern_bindings(ast, p.pattern, &mut bindings);
                if let Some(layer) = self.locals.last_mut() {
                    layer.extend(bindings);
                }
            }
            _ => (),
        }
    }

    /// Records the declared type of each read of a variable that flow
    /// analysis cannot promote.
    fn record_variable_reads(&mut self) {
        let Some(declarations) = self.declarations.as_ref() else {
            return;
        };
        let store = &*declarations.store;
        for &(node, id) in &self.reads {
            let variable = &self.variables[id];
            if variable.promotable_read {
                continue;
            }
            let type_ = match variable.declared {
                Declared::Untyped => continue,
                Declared::Node(n) => match self.annotation_types.get(&n) {
                    Some(type_) => type_.clone(),
                    None => continue,
                },
                Declared::Element(e) => match &store.element(e).type_ {
                    Some(type_) => built(store, type_),
                    None => continue,
                },
            };
            if variable.written && !is_non_nullable(store, &type_) {
                continue;
            }
            self.static_types.insert(node, type_);
            self.variable_reads.insert(node, VariableRead { kind: variable.kind, name_offset: variable.name_offset });
        }
    }

    /// Enters the `TypeParameterScope` and `InstanceScope` (or, when
    /// [instance] is false, `ExtensionScope`) of the declaration [node].
    fn enter_instance(&mut self, node: NodeId, instance: bool, features: ScopeFeatures) {
        let scope = self.scope;
        let Some(declarations) = self.declarations.as_mut() else {
            return;
        };
        let store = &*declarations.store;
        let Some(&fragment) = declarations.fragment_of_node.get(&(declarations.unit, node)) else {
            panic!("no declared fragment for node {node}");
        };
        let element = store.fragment(fragment).element;
        let type_parameters: Vec<ElementId> = store
            .fragment(store.element(element).first_fragment)
            .type_parameters
            .iter()
            .map(|&f| store.fragment(f).element)
            .collect();
        let scope = declarations.scopes.type_parameter_scope(store, scope, &type_parameters, features);
        self.scope = declarations.scopes.instance_scope(store, scope, element, instance);
    }

    /// `_defineLocalElements`: the local functions, variables and pattern
    /// variables [statements] declare (past their labels), which are in
    /// scope in the whole block.
    fn define_local_elements(&mut self, ast: Ast<'_>, statements: &[NodeId], features: ScopeFeatures) -> Vec<Binding> {
        let mut layer = Vec::new();
        for &statement in statements {
            let mut statement = statement;
            while let AstNodeImpl::LabeledStatementImpl(l) = ast.node(statement) {
                statement = l.statement2;
            }
            match ast.node(statement) {
                AstNodeImpl::LocalFunctionDeclarationImpl(d) => {
                    if !(features.wildcard_variables && ast.tokens.lexeme_equals(d.name, "_")) {
                        layer.push(Binding { name: ast.tokens.lexeme_string(d.name), kind: BindingKind::Other });
                    }
                }
                AstNodeImpl::PatternVariableDeclarationStatementImpl(s) => {
                    let pattern = ast.node(s.declaration).as_pattern_variable_declaration_impl().pattern;
                    pattern_bindings(ast, pattern, &mut layer);
                }
                AstNodeImpl::LocalVariablesDeclarationStatementImpl(s) => {
                    self.declare_variables(ast, s.declaration, features, &mut layer);
                }
                _ => (),
            }
        }
        layer
    }

    /// Adds the variables of the `LocalVariablesDeclaration` [declaration]
    /// to [layer].
    fn declare_variables(&mut self, ast: Ast<'_>, declaration: NodeId, features: ScopeFeatures, layer: &mut Vec<Binding>) {
        let d = ast.node(declaration).as_local_variables_declaration_impl();
        let declared = if d.type_ != NO_NODE { Declared::Node(d.type_) } else { Declared::Untyped };
        for &variable in d.variables.iter() {
            let name = ast.node(variable).as_local_variable_impl().name;
            if let Some(binding) = self.variable_binding(ast, variable, name, "LOCAL_VARIABLE", declared, features) {
                layer.push(binding);
            }
        }
    }

    /// The binding of the variable [node] declares (made once per node), or
    /// `None` for a wildcard (`LocalScope.add`).
    fn variable_binding(
        &mut self,
        ast: Ast<'_>,
        node: NodeId,
        name: TokenId,
        kind: &'static str,
        declared: Declared,
        features: ScopeFeatures,
    ) -> Option<Binding> {
        if name == NO_TOKEN {
            return None;
        }
        let name_string = ast.tokens.lexeme_string(name);
        if features.wildcard_variables && name_string == "_" {
            return None;
        }
        let id = *self.variable_of_node.entry(node).or_insert_with(|| {
            self.variables.push(Variable {
                kind,
                name_offset: ast.tokens.offset(name),
                declared,
                written: false,
                promotable_read: false,
            });
            self.variables.len() - 1
        });
        Some(Binding { name: name_string, kind: BindingKind::Variable(id) })
    }

    /// The formal parameters of the executable [node] as its body sees them
    /// (`FormalParameterScope`: not field or super formal parameters), or,
    /// when [initializers], as its initializer list does
    /// (`ConstructorInitializerScope`: all of them).
    fn parameter_bindings(&mut self, ast: Ast<'_>, node: NodeId, initializers: bool, features: ScopeFeatures) -> Vec<Binding> {
        let list = match ast.node(node) {
            AstNodeImpl::TopLevelFunctionDeclarationImpl(d) => d.formal_parameters,
            AstNodeImpl::MethodDeclaration2Impl(d) => d.formal_parameters,
            AstNodeImpl::LocalFunctionDeclarationImpl(d) => d.formal_parameters,
            AstNodeImpl::FunctionExpressionImpl(d) => d.parameters,
            AstNodeImpl::SetterDeclarationImpl(d) => d.formal_parameters,
            AstNodeImpl::TopLevelSetterDeclarationImpl(d) => d.formal_parameters,
            AstNodeImpl::OperatorDeclarationImpl(d) => d.formal_parameters,
            AstNodeImpl::ConstructorDeclaration2Impl(d) => d.formal_parameters,
            _ => NO_NODE,
        };
        // Linking typed the formal parameters of declarations.
        let linked = matches!(
            ast.node(node),
            AstNodeImpl::TopLevelFunctionDeclarationImpl(_)
                | AstNodeImpl::MethodDeclaration2Impl(_)
                | AstNodeImpl::SetterDeclarationImpl(_)
                | AstNodeImpl::TopLevelSetterDeclarationImpl(_)
                | AstNodeImpl::OperatorDeclarationImpl(_)
                | AstNodeImpl::ConstructorDeclaration2Impl(_)
        );
        let mut layer = Vec::new();
        for parameter in all_formal_parameters(ast, list) {
            match ast.node(parameter) {
                AstNodeImpl::RegularFormalParameterImpl(p) => {
                    let declared = if p.type_ == NO_NODE && p.function_typed_suffix == NO_NODE {
                        Declared::Untyped
                    } else if let Some(element) = self.linked_element(parameter).filter(|_| linked) {
                        Declared::Element(element)
                    } else if p.function_typed_suffix != NO_NODE {
                        Declared::Node(parameter)
                    } else {
                        Declared::Node(p.type_)
                    };
                    if let Some(binding) = self.variable_binding(ast, parameter, p.name, "PARAMETER", declared, features) {
                        add_first(&mut layer, binding);
                    }
                }
                AstNodeImpl::FieldFormalParameterImpl(_) | AstNodeImpl::SuperFormalParameterImpl(_) if initializers => {
                    let name = match ast.node(parameter) {
                        AstNodeImpl::FieldFormalParameterImpl(p) => p.name,
                        AstNodeImpl::SuperFormalParameterImpl(p) => p.name,
                        _ => unreachable!(),
                    };
                    let name = ast.tokens.lexeme_string(name);
                    if !(features.wildcard_variables && name == "_") {
                        add_first(&mut layer, Binding { name, kind: BindingKind::Other });
                    }
                }
                _ => (),
            }
        }
        layer
    }

    /// The element linking made for the declaration [node], if any.
    fn linked_element(&self, node: NodeId) -> Option<ElementId> {
        let declarations = self.declarations.as_ref()?;
        let &fragment = declarations.fragment_of_node.get(&(declarations.unit, node))?;
        Some(declarations.store.fragment(fragment).element)
    }

    /// The `TypeParameterScope` of the type parameter list [list]: the
    /// elements linking made for a declaration's, and new elements for those
    /// of local functions, function expressions and function types.
    fn type_parameter_bindings(&mut self, ast: Ast<'_>, list: NodeId, features: ScopeFeatures) -> Vec<Binding> {
        let mut layer = Vec::new();
        if list == NO_NODE {
            return layer;
        }
        for &parameter in ast.node(list).as_type_parameter_list_impl().type_parameters.iter() {
            let name = ast.tokens.lexeme_string(ast.node(parameter).as_type_parameter_impl().name);
            let element = match self.type_parameter_of_node.get(&parameter) {
                Some(&(element, _)) => element,
                None => {
                    let (element, made) = match self.linked_element(parameter) {
                        Some(element) => (element, false),
                        None => match self.declarations.as_mut() {
                            Some(declarations) => {
                                (declarations.store.add_synthetic_type_parameter(Some(Rc::from(name.as_str())), NO_LIBRARY), true)
                            }
                            None => (NO_ELEMENT, false),
                        },
                    };
                    self.type_parameter_of_node.insert(parameter, (element, made));
                    element
                }
            };
            if !(features.wildcard_variables && name == "_") {
                add_first(&mut layer, Binding { name, kind: BindingKind::TypeParameter(element) });
            }
        }
        layer
    }

    /// The innermost local binding of [name].
    fn lookup_binding(&self, name: &str) -> Option<BindingKind> {
        self.locals
            .iter()
            .rev()
            .find_map(|layer| layer.iter().find(|binding| binding.name == name).map(|binding| binding.kind))
    }

    /// `Scope.lookup(name).getter`: a local type parameter, nothing for any
    /// other local, else what the declarations' scopes find.
    fn lookup(&self, name: &str) -> Option<ScopeElement> {
        match self.lookup_binding(name) {
            Some(BindingKind::TypeParameter(element)) if element != NO_ELEMENT => {
                return Some(ScopeElement::Element(element));
            }
            Some(_) => return None,
            None => (),
        }
        let declarations = self.declarations.as_ref()?;
        declarations.scopes.lookup(declarations.store, self.scope, name).getter
    }

    /// What the name (or prefixed name) of the `NamedType` [node] finds.
    fn named_type_element(&self, ast: Ast<'_>, node: NodeId) -> Option<ScopeElement> {
        let declarations = self.declarations.as_ref()?;
        let n = ast.node(node).as_named_type_impl();
        let name = ast.tokens.lexeme_string(n.name);
        if n.import_prefix != NO_NODE {
            let prefix = ast.node(n.import_prefix).as_import_prefix_reference_impl().name;
            match self.lookup(&ast.tokens.lexeme_string(prefix)) {
                Some(ScopeElement::Prefix(p)) => declarations.scopes.lookup_prefix(p, &name).getter,
                _ => None,
            }
        } else {
            self.lookup(&name)
        }
    }

    /// The shape of the type the annotation [node] names, as
    /// `TypeNameResolver` resolves it: the element its name (or prefixed
    /// name) finds, with its type arguments; an alias is expanded with them
    /// (or with the defaults of its type parameters when there are none).
    fn annotation_shape(&self, ast: Ast<'_>, node: NodeId) -> Shape {
        let Some(declarations) = self.declarations.as_ref() else {
            return Shape::Unknown;
        };
        let AstNodeImpl::NamedTypeImpl(n) = ast.node(node) else {
            // A function or record type.
            return Shape::Other;
        };
        let Some(ScopeElement::Element(element)) = self.named_type_element(ast, node) else {
            // Unresolved, ambiguous, or not a type: `InvalidType`.
            return Shape::Other;
        };
        let arguments: Vec<Shape> = if n.type_arguments != NO_NODE {
            ast.node(n.type_arguments)
                .as_type_argument_list_impl()
                .arguments
                .iter()
                .map(|&argument| self.annotation_shape(ast, argument))
                .collect()
        } else {
            Vec::new()
        };
        element_shape(declarations.store, element, arguments)
    }

    /// `TypeAnnotation.type` of [node], whose children have their types:
    /// `NamedTypeResolver` (an interface type with its type arguments, or
    /// the defaults of its type parameters when there are none, or `dynamic`
    /// for each when their number is wrong; an alias instantiated; a type
    /// parameter, `dynamic`, `Never` or `void`; else `InvalidType`), and the
    /// function and record types their annotations describe.
    fn annotation_type(&mut self, ast: Ast<'_>, node: NodeId) -> TypeImpl {
        match ast.node(node) {
            AstNodeImpl::NamedTypeImpl(n) => {
                let suffix = nullability(n.question);
                if n.import_prefix == NO_NODE && ast.tokens.lexeme_equals(n.name, "void") {
                    return TypeImpl::Void;
                }
                let Some(ScopeElement::Element(element)) = self.named_type_element(ast, node) else {
                    return TypeImpl::Invalid;
                };
                let arguments: Vec<TypeImpl> = if n.type_arguments != NO_NODE {
                    ast.node(n.type_arguments)
                        .as_type_argument_list_impl()
                        .arguments
                        .iter()
                        .map(|argument| self.annotation_types.get(argument).cloned().unwrap_or(TypeImpl::Dynamic))
                        .collect()
                } else {
                    Vec::new()
                };
                let store = &mut *self.declarations.as_mut().unwrap().store;
                named_element_type(store, element, arguments, suffix)
            }
            AstNodeImpl::GenericFunctionTypeImpl(g) => {
                let (type_parameters, parameters, return_type, question) =
                    (g.type_parameters, g.parameters, g.return_type, g.question);
                self.function_type(ast, type_parameters, parameters, return_type, question)
            }
            AstNodeImpl::RecordTypeAnnotationImpl(r) => {
                let field_type = |this: &Self, type_: NodeId| this.annotation_types.get(&type_).cloned().unwrap_or(TypeImpl::Dynamic);
                let positional = r
                    .positional_fields
                    .iter()
                    .map(|&f| field_type(self, ast.node(f).as_record_type_annotation_positional_field_impl().type_))
                    .collect();
                let mut named = Vec::new();
                if r.named_fields != NO_NODE {
                    for &f in ast.node(r.named_fields).as_record_type_annotation_named_fields_impl().fields.iter() {
                        let field = ast.node(f).as_record_type_annotation_named_field_impl();
                        named.push((Rc::from(ast.tokens.lexeme_string(field.name).as_str()), field_type(self, field.type_)));
                    }
                }
                TypeImpl::Record(Rc::new(RecordTypeImpl::new(positional, named, nullability(r.question))))
            }
            _ => TypeImpl::Invalid,
        }
    }

    /// The function type with the type parameters [type_parameters], the
    /// formal parameters [parameters] and the return type [return_type]
    /// (`dynamic` when there is none), as `FunctionTypeBuilder.of` builds it.
    fn function_type(
        &self,
        ast: Ast<'_>,
        type_parameters: NodeId,
        parameters: NodeId,
        return_type: NodeId,
        question: TokenId,
    ) -> TypeImpl {
        let type_parameters: Vec<ElementId> = if type_parameters == NO_NODE {
            Vec::new()
        } else {
            ast.node(type_parameters)
                .as_type_parameter_list_impl()
                .type_parameters
                .iter()
                .map(|p| self.type_parameter_of_node.get(p).map(|&(e, _)| e).unwrap_or(NO_ELEMENT))
                .collect()
        };
        let formal_parameters = all_formal_parameters(ast, parameters)
            .into_iter()
            .map(|p| {
                let (name, kind, type_, suffix) = match ast.node(p) {
                    AstNodeImpl::RegularFormalParameterImpl(f) => (f.name, f.kind, f.type_, f.function_typed_suffix),
                    AstNodeImpl::FieldFormalParameterImpl(f) => (f.name, f.kind, f.type_, f.function_typed_suffix),
                    AstNodeImpl::SuperFormalParameterImpl(f) => (f.name, f.kind, f.type_, f.function_typed_suffix),
                    _ => (NO_TOKEN, ParameterKind::REQUIRED, NO_NODE, NO_NODE),
                };
                let key = if suffix != NO_NODE { p } else { type_ };
                let name = if name == NO_TOKEN { None } else { Some(Rc::from(ast.tokens.lexeme_string(name).as_str())) };
                FormalParameter {
                    name,
                    type_: self.annotation_types.get(&key).cloned().unwrap_or(TypeImpl::Dynamic),
                    kind,
                }
            })
            .collect();
        let return_type = self.annotation_types.get(&return_type).cloned().unwrap_or(TypeImpl::Dynamic);
        TypeImpl::Function(Rc::new(FunctionTypeImpl::new(type_parameters, formal_parameters, return_type, nullability(question))))
    }
}

/// Adds [binding] unless [layer] already binds its name (`??=`).
fn add_first(layer: &mut Vec<Binding>, binding: Binding) {
    if !layer.iter().any(|b| b.name == binding.name) {
        layer.push(binding);
    }
}

/// `_getNullabilitySuffix`.
fn nullability(question: TokenId) -> NullabilitySuffix {
    if question != NO_TOKEN { NullabilitySuffix::question } else { NullabilitySuffix::none }
}

/// [type_], or the type its builder built.
fn built(store: &ElementStore, type_: &TypeImpl) -> TypeImpl {
    match type_ {
        TypeImpl::Builder(id) => match &store.type_builders[*id as usize] {
            TypeBuilder::Named(b) => b.type_.clone(),
            TypeBuilder::Function(b) => b.type_.clone(),
            TypeBuilder::Record(b) => b.type_.clone(),
        }
        .unwrap_or(TypeImpl::Dynamic),
        other => other.clone(),
    }
}

/// The type the element [element] names with [arguments] and [suffix]
/// (`NamedTypeBuilder.build` on linked elements).
fn named_element_type(store: &mut ElementStore, element: ElementId, arguments: Vec<TypeImpl>, suffix: NullabilitySuffix) -> TypeImpl {
    let kind = store.element(element).kind;
    let parameters: Vec<ElementId> = {
        let first = store.element(element).first_fragment;
        if first == crate::src::dart::element::element::NO_FRAGMENT {
            Vec::new()
        } else {
            store.fragment(first).type_parameters.iter().map(|&f| store.fragment(f).element).collect()
        }
    };
    let arguments_for = |store: &mut ElementStore| -> Vec<TypeImpl> {
        if parameters.is_empty() {
            Vec::new()
        } else if !arguments.is_empty() {
            if arguments.len() == parameters.len() {
                arguments.clone()
            } else {
                vec![TypeImpl::Dynamic; parameters.len()]
            }
        } else {
            parameters
                .iter()
                .map(|&p| match store.types(p).and_then(|t| t.default_type.clone()) {
                    Some(default) => built(store, &default),
                    None => TypeImpl::Dynamic,
                })
                .collect()
        }
    };
    match kind {
        ElementKind::CLASS | ElementKind::ENUM | ElementKind::MIXIN | ElementKind::EXTENSION_TYPE => {
            let arguments = arguments_for(store);
            TypeImpl::interface(element, arguments, suffix)
        }
        ElementKind::TYPE_ALIAS => {
            if store.types(element).is_some_and(|t| t.has_self_reference) {
                return TypeImpl::Dynamic;
            }
            let arguments = arguments_for(store);
            let aliased = match &store.element(element).type_ {
                Some(t) => built(store, t),
                None => TypeImpl::Dynamic,
            };
            let substitution = Substitution::from_pairs(parameters.clone(), arguments);
            let type_ = substitute(store, &substitution, &aliased);
            let result = if type_.nullability_suffix(store) == NullabilitySuffix::question {
                NullabilitySuffix::question
            } else {
                suffix
            };
            type_.with_nullability(store, result)
        }
        ElementKind::NEVER => TypeImpl::Never(suffix),
        ElementKind::TYPE_PARAMETER => TypeImpl::type_parameter(element, suffix),
        ElementKind::DYNAMIC => TypeImpl::Dynamic,
        _ => TypeImpl::Invalid,
    }
}

/// The formal parameters of the list [list], positional then delimited.
fn all_formal_parameters(ast: Ast<'_>, list: NodeId) -> Vec<NodeId> {
    if list == NO_NODE {
        return Vec::new();
    }
    let list = ast.node(list).as_formal_parameter_list_impl();
    let mut parameters: Vec<NodeId> = list.required_positional_formal_parameters.iter().copied().collect();
    if list.delimited_formal_parameters != NO_NODE {
        parameters.extend(
            ast.node(list.delimited_formal_parameters)
                .as_delimited_formal_parameters_impl()
                .formal_parameters
                .iter()
                .copied(),
        );
    }
    parameters
}

/// The variables the patterns under [node] declare (`_` declares none),
/// added to [layer]; they are never selected reads.
fn pattern_bindings(ast: Ast<'_>, node: NodeId, layer: &mut Vec<Binding>) {
    if node == NO_NODE {
        return;
    }
    if let AstNodeImpl::DeclaredVariablePatternImpl(p) = ast.node(node) {
        let name = ast.tokens.lexeme_string(p.name);
        if name != "_" {
            add_first(layer, Binding { name, kind: BindingKind::Other });
        }
    }
    // A guard's expression declares nothing.
    if matches!(ast.node(node), AstNodeImpl::WhenClauseImpl(_)) {
        return;
    }
    for child in ast.named_child_entities2(node) {
        match child.value {
            ChildValue::Node(id) => pattern_bindings(ast, id, layer),
            ChildValue::NodeList(ids) => {
                for &id in ids {
                    pattern_bindings(ast, id, layer);
                }
            }
            _ => (),
        }
    }
}

/// The pattern variables of the case clause [clause].
fn case_clause_bindings(ast: Ast<'_>, clause: NodeId) -> Vec<Binding> {
    let mut layer = Vec::new();
    pattern_bindings(ast, ast.node(clause).as_case_clause_impl().guarded_pattern, &mut layer);
    layer
}

/// The guarded pattern (`NO_NODE` for a constant case or `default`) and the
/// statements of the switch member [member].
fn switch_member_parts(ast: Ast<'_>, member: NodeId) -> (NodeId, Vec<NodeId>) {
    match ast.node(member) {
        AstNodeImpl::SwitchPatternCaseImpl(m) => (m.guarded_pattern, m.statements2.iter().copied().collect()),
        AstNodeImpl::SwitchCaseImpl(m) => (NO_NODE, m.statements2.iter().copied().collect()),
        AstNodeImpl::SwitchDefaultImpl(m) => (NO_NODE, m.statements2.iter().copied().collect()),
        _ => (NO_NODE, Vec::new()),
    }
}

/// The members of the group of [member] in the switch statement [switch]
/// (`_computeMemberGroups`: members up to one with statements).
fn switch_group(ast: Ast<'_>, switch: NodeId, member: NodeId) -> Vec<NodeId> {
    let AstNodeImpl::SwitchStatementImpl(s) = ast.node(switch) else {
        return vec![member];
    };
    let mut group = Vec::new();
    for &m in s.members.iter() {
        group.push(m);
        if !switch_member_parts(ast, m).1.is_empty() {
            if group.contains(&member) {
                return group;
            }
            group.clear();
        }
    }
    group
}

/// Whether flow analysis may promote the variable the read [read] reads at
/// it, decided as the oracle's `_canPromote` does: past enclosing
/// parentheses, the token after is `!`, `?.`, `?..`, `is`, `as`, `==` or
/// `!=`, or `?` followed by `[`; or the token before is `==` or `!=`; or the
/// read is the scrutinee of a switch statement or expression, of an
/// `if`-`case`, or the initializer of a pattern variable declaration or
/// pattern assignment.
fn can_promote(ast: Ast<'_>, read: NodeId) -> bool {
    let mut node = read;
    while let AstNodeImpl::ParenthesizedExpressionImpl(_) = ast.node(ast.parent2(node)) {
        node = ast.parent2(node);
    }
    let lexeme = |token: TokenId| if token == NO_TOKEN { String::new() } else { ast.tokens.lexeme_string(token) };
    let after = ast.tokens.next(ast.end_token(node));
    let after_lexeme = lexeme(after);
    if ["!", "?.", "?..", "is", "as", "==", "!="].contains(&after_lexeme.as_str())
        || (after_lexeme == "?" && lexeme(ast.tokens.next(after)) == "[")
    {
        return true;
    }
    let before = ast.tokens.previous(ast.begin_token(node));
    if ["==", "!="].contains(&lexeme(before).as_str()) {
        return true;
    }
    match ast.node(ast.parent2(node)) {
        AstNodeImpl::SwitchStatementImpl(s) => s.expression2 == node,
        AstNodeImpl::SwitchExpressionImpl(s) => s.expression2 == node,
        AstNodeImpl::PatternVariableDeclarationImpl(d) => d.expression2 == node,
        AstNodeImpl::PatternAssignmentImpl(a) => a.expression2 == node,
        AstNodeImpl::IfStatementImpl(s) => s.case_clause != NO_NODE && s.expression2 == node,
        AstNodeImpl::IfElementImpl(e) => e.case_clause != NO_NODE && e.expression2 == node,
        _ => false,
    }
}

/// The shape of the type [element] with the type arguments [arguments]
/// names: `double` of `dart:core`, `Future` and `FutureOr` of `dart:async`
/// (with `dynamic` for a missing or wrong number of arguments), or a type
/// alias expanded.
fn element_shape(store: &ElementStore, element: ElementId, arguments: Vec<Shape>) -> Shape {
    let e = store.element(element);
    match e.kind {
        ElementKind::CLASS => {
            if e.library == NO_LIBRARY {
                return Shape::Other;
            }
            let uri = &*store.libraries[e.library as usize].uri;
            let argument = || match <[Shape; 1]>::try_from(arguments.clone()) {
                Ok([argument]) => Box::new(argument),
                Err(_) => Box::new(Shape::Other),
            };
            match (uri, e.name.as_deref()) {
                ("dart:core", Some("double")) => Shape::Double,
                ("dart:async", Some("Future")) => Shape::Future(argument()),
                ("dart:async", Some("FutureOr")) => Shape::FutureOr(argument()),
                _ => Shape::Other,
            }
        }
        ElementKind::TYPE_ALIAS => {
            if e.types.as_ref().is_some_and(|t| t.has_self_reference) {
                return Shape::Other;
            }
            let Some(aliased) = &e.type_ else {
                return Shape::Other;
            };
            let parameters: Vec<ElementId> = store
                .fragment(e.first_fragment)
                .type_parameters
                .iter()
                .map(|&f| store.fragment(f).element)
                .collect();
            let arguments: Vec<Shape> = if arguments.len() == parameters.len() {
                arguments
            } else if arguments.is_empty() {
                // Instantiated to bounds: the default type of each parameter.
                parameters
                    .iter()
                    .map(|&p| match store.element(p).types.as_ref().and_then(|t| t.default_type.as_ref()) {
                        Some(default) => type_shape(store, default, &HashMap::new()),
                        None => Shape::Other,
                    })
                    .collect()
            } else {
                vec![Shape::Other; parameters.len()]
            };
            let environment: HashMap<ElementId, Shape> = parameters.into_iter().zip(arguments).collect();
            type_shape(store, aliased, &environment)
        }
        _ => Shape::Other,
    }
}

/// The shape of the linked type [type_], with the type parameters in
/// [environment] standing for those shapes.
fn type_shape(store: &ElementStore, type_: &TypeImpl, environment: &HashMap<ElementId, Shape>) -> Shape {
    match type_ {
        TypeImpl::Interface(t) => {
            let arguments = t.type_arguments.iter().map(|a| type_shape(store, a, environment)).collect();
            element_shape(store, t.element, arguments)
        }
        TypeImpl::TypeParameter(t) => environment.get(&t.element).cloned().unwrap_or(Shape::Other),
        TypeImpl::Builder(_) | TypeImpl::Unknown => Shape::Unknown,
        _ => Shape::Other,
    }
}

/// Whether the oracle's `--integers` selects the integer literal [literal]:
/// its context type is taken from a declared type annotation, or it has
/// none. Past a `-` whose operand it is (which passes its context on, as
/// `UnaryOperatorInvocationResolver.resolve` does) and parentheses, the
/// literal is
/// - an expression statement or an interpolation (no context);
/// - the initializer of a variable whose declaration has a type annotation;
/// - the default value of an optional formal parameter with a type
///   annotation and no function-typed suffix, of a function, method,
///   constructor, local function or function expression;
/// - a returned expression (`return` or `=>`) of a function, method, getter,
///   operator or local function with a return type that is not a generator;
/// - an element of a list or set literal with one type argument, or a key or
///   value of a map literal with two, possibly inside `if` and `for`
///   elements.
pub fn is_declared_context_integer(ast: Ast<'_>, literal: NodeId) -> bool {
    integer_context_site(ast, literal).is_some()
}

/// Where the context type of a selected integer literal comes from.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum IntegerContextSite {
    /// No context: an expression statement or an interpolation.
    None,
    /// The type annotation [0] is the context.
    Annotation(NodeId),
    /// A returned expression of a function whose return type is the
    /// annotation; [is_async] when the body is `async`, which makes the
    /// context `FutureOr<futureValueType(R)>` (`BodyInferenceContext`).
    Return { annotation: NodeId, is_async: bool },
}

/// The site [is_declared_context_integer] describes, or `None` when the
/// literal is not selected.
pub fn integer_context_site(ast: Ast<'_>, literal: NodeId) -> Option<IntegerContextSite> {
    use fe_analyzer_shared::scanner::token::TokenType;
    let mut node = literal;
    let mut parent = ast.parent2(node);
    if let AstNodeImpl::UnaryOperatorInvocationImpl(u) = ast.node(parent) {
        if u.operand == node && ast.tokens.type_(u.operator_) == TokenType::MINUS {
            node = parent;
            parent = ast.parent2(node);
        }
    }
    while let AstNodeImpl::ParenthesizedExpressionImpl(_) = ast.node(parent) {
        node = parent;
        parent = ast.parent2(node);
    }
    let annotated = |annotation: NodeId| (annotation != NO_NODE).then_some(IntegerContextSite::Annotation(annotation));
    match ast.node(parent) {
        AstNodeImpl::ExpressionStatementImpl(_) | AstNodeImpl::InterpolationExpressionImpl(_) => {
            Some(IntegerContextSite::None)
        }
        AstNodeImpl::TopLevelVariable2Impl(_) => {
            annotated(ast.node(ast.parent2(parent)).as_top_level_variables_declaration_impl().type_)
        }
        AstNodeImpl::Field2Impl(_) => annotated(ast.node(ast.parent2(parent)).as_fields_declaration_impl().type_),
        AstNodeImpl::LocalVariableImpl(_) => {
            annotated(ast.node(ast.parent2(parent)).as_local_variables_declaration_impl().type_)
        }
        AstNodeImpl::FormalParameterDefaultClauseImpl(_) => {
            let parameter = ast.parent2(parent);
            let AstNodeImpl::RegularFormalParameterImpl(p) = ast.node(parameter) else {
                return None;
            };
            if p.type_ == NO_NODE || p.function_typed_suffix != NO_NODE {
                return None;
            }
            let delimited = ast.parent2(parameter);
            if !matches!(ast.node(delimited), AstNodeImpl::DelimitedFormalParametersImpl(_)) {
                return None;
            }
            let executable = ast.parent2(ast.parent2(delimited));
            match ast.node(executable) {
                AstNodeImpl::TopLevelFunctionDeclarationImpl(_)
                | AstNodeImpl::MethodDeclaration2Impl(_)
                | AstNodeImpl::ConstructorDeclaration2Impl(_)
                | AstNodeImpl::LocalFunctionDeclarationImpl(_)
                | AstNodeImpl::FunctionExpressionImpl(_) => annotated(p.type_),
                _ => None,
            }
        }
        AstNodeImpl::ReturnStatementImpl(_) => {
            let mut body = ast.parent2(parent);
            while body != NO_NODE && !is_function_body(ast.node(body)) {
                body = ast.parent2(body);
            }
            if body == NO_NODE || !matches!(ast.node(body), AstNodeImpl::BlockFunctionBodyImpl(_)) {
                return None;
            }
            return_site(ast, body)
        }
        AstNodeImpl::ExpressionFunctionBodyImpl(_) => return_site(ast, parent),
        AstNodeImpl::ListLiteralImpl(_)
        | AstNodeImpl::SetOrMapLiteralImpl(_)
        | AstNodeImpl::MapLiteralEntryImpl(_)
        | AstNodeImpl::IfElementImpl(_)
        | AstNodeImpl::ForElementImpl(_) => {
            element_type_site(ast, node, parent)
        }
        _ => None,
    }
}

/// `node is FunctionBodyImpl || node is AnonymousMethodBodyImpl`: what a
/// `return` returns from.
fn is_function_body(node: &AstNodeImpl) -> bool {
    matches!(
        node,
        AstNodeImpl::AnonymousBlockBodyImpl(_)
            | AstNodeImpl::AnonymousExpressionBodyImpl(_)
            | AstNodeImpl::BlockFunctionBodyImpl(_)
            | AstNodeImpl::ExpressionFunctionBodyImpl(_)
            | AstNodeImpl::EmptyFunctionBodyImpl(_)
            | AstNodeImpl::NativeFunctionBodyImpl(_)
    )
}

/// The return site of [body] when it belongs to a declaration with a return
/// type, other than a constructor or setter, and is not a generator.
fn return_site(ast: Ast<'_>, body: NodeId) -> Option<IntegerContextSite> {
    use fe_analyzer_shared::scanner::token::NO_TOKEN;
    let (keyword, star) = match ast.node(body) {
        AstNodeImpl::BlockFunctionBodyImpl(b) => (b.keyword, b.star),
        AstNodeImpl::ExpressionFunctionBodyImpl(b) => (b.keyword, b.star),
        _ => return None,
    };
    if star != NO_TOKEN {
        return None;
    }
    let annotation = match ast.node(ast.parent2(body)) {
        AstNodeImpl::TopLevelFunctionDeclarationImpl(d) => d.return_type,
        AstNodeImpl::MethodDeclaration2Impl(d) => d.return_type,
        AstNodeImpl::LocalFunctionDeclarationImpl(d) => d.return_type,
        AstNodeImpl::GetterDeclarationImpl(d) => d.return_type,
        AstNodeImpl::TopLevelGetterDeclarationImpl(d) => d.return_type,
        AstNodeImpl::OperatorDeclarationImpl(d) => d.return_type,
        _ => NO_NODE,
    };
    if annotation == NO_NODE {
        return None;
    }
    // `isAsynchronous`: `keyword?.lexeme == 'async'`.
    let is_async = keyword != NO_TOKEN && ast.tokens.lexeme_equals(keyword, "async");
    Some(IntegerContextSite::Return { annotation, is_async })
}

/// The site of the collection element [element] of [parent] when explicit
/// type arguments of the enclosing literal give its context.
fn element_type_site(ast: Ast<'_>, mut element: NodeId, mut parent: NodeId) -> Option<IntegerContextSite> {
    // Which type argument: the element type, or a map's key or value type.
    let mut argument: Option<usize> = None;
    loop {
        match ast.node(parent) {
            AstNodeImpl::IfElementImpl(e) => {
                if e.then_element2 != element && e.else_element2 != element {
                    return None;
                }
            }
            AstNodeImpl::ForElementImpl(e) => {
                if e.body2 != element {
                    return None;
                }
            }
            AstNodeImpl::MapLiteralEntryImpl(e) => {
                if argument.is_some() {
                    return None;
                }
                argument = Some(if e.key2 == element { 0 } else { 1 });
            }
            AstNodeImpl::ListLiteralImpl(l) => {
                return match argument {
                    None => type_argument(ast, l.type_arguments, 1, 0),
                    Some(_) => None,
                };
            }
            AstNodeImpl::SetOrMapLiteralImpl(l) => {
                return match argument {
                    None => type_argument(ast, l.type_arguments, 1, 0),
                    Some(index) => type_argument(ast, l.type_arguments, 2, index),
                };
            }
            _ => return None,
        }
        element = parent;
        parent = ast.parent2(element);
    }
}

/// The site of type argument [index] of [list] when it has [count].
fn type_argument(ast: Ast<'_>, list: NodeId, count: usize, index: usize) -> Option<IntegerContextSite> {
    if list == NO_NODE {
        return None;
    }
    let arguments = &ast.node(list).as_type_argument_list_impl().arguments;
    (arguments.len() == count).then(|| IntegerContextSite::Annotation(arguments[index]))
}
