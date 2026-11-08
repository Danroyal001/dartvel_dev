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
// decides whether an annotation makes that context `double`.
// Flow state, diagnostics, rewrites, integer literals in other contexts
// (arguments, operands, inferred declarations), identifiers, invocations and
// all other expression visitors remain unported. Types are stored beside the
// AST by NodeId, as linking's annotation types are, rather than changing
// parsed nodes.
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, ChildValue, NO_NODE, NodeId};
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore, FragmentId, NO_LIBRARY, UnitId};
use crate::src::dart::element::r#type::TypeImpl;
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
/// node of the unit, which the linker parsed into the same node ids.
pub struct Declarations<'a> {
    pub store: &'a ElementStore,
    pub scopes: &'a mut Scopes,
    pub fragment_of_node: &'a HashMap<(UnitId, NodeId), FragmentId>,
    pub unit: UnitId,
}

pub struct TypeAnalyzer<'a> {
    pub type_provider: &'a TypeProviderImpl,
    pub static_types: HashMap<NodeId, TypeImpl>,
    /// `None` when the unit is analyzed without its library: a context
    /// type that an annotation gives is then unknown, and an integer literal
    /// in it is left without a type.
    declarations: Option<Declarations<'a>>,
    /// The scope type annotations are resolved in: the unit's
    /// `LibraryFragmentScope`, or the type parameter and instance scopes of
    /// the declaration being visited.
    scope: ScopeId,
    /// The names declared inside executables, innermost last: type
    /// parameters, formal parameters (in the body), local variables and
    /// functions, catch parameters. A type annotation whose name one of them
    /// declares names no type.
    locals: Vec<Vec<String>>,
    /// The context classification of each type annotation visited.
    annotation_shapes: HashMap<NodeId, Shape>,
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
            declarations: None,
            scope: ScopeId::LibraryFragment(0),
            locals: Vec::new(),
            annotation_shapes: HashMap::new(),
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
    pub fn analyze(&mut self, ast: Ast<'_>, node: NodeId) {
        let features = match ast.node(node) {
            AstNodeImpl::CompilationUnitImpl(unit) => ScopeFeatures {
                wildcard_variables: unit.feature_set.is_enabled(Feature::wildcard_variables),
                records: unit.feature_set.is_enabled(Feature::records),
            },
            _ => ScopeFeatures { wildcard_variables: false, records: false },
        };
        self.visit(ast, node, features);
    }

    fn visit(&mut self, ast: Ast<'_>, node: NodeId, features: ScopeFeatures) {
        // visitConfiguration: upstream deliberately does not resolve children.
        if matches!(ast.node(node), AstNodeImpl::ConfigurationImpl(_)) {
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
                ChildValue::Node(id) => {
                    if id == body {
                        // The formal parameters are in scope in the body.
                        self.locals.push(parameter_names(ast, node));
                    }
                    self.visit(ast, id, features);
                }
                ChildValue::NodeList(ids) => {
                    for &id in ids {
                        self.visit(ast, id, features);
                    }
                }
                _ => (),
            }
        }
        self.scope = outer_scope;
        self.locals.truncate(outer_locals);
        if let AstNodeImpl::LocalVariableImpl(v) = ast.node(node) {
            // In scope after its own initializer.
            self.declare_local(ast, v.name);
        }
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

    /// The shape recorded for the annotation [node]: unknown if it was not
    /// visited.
    fn shape_of(&self, node: NodeId) -> Shape {
        self.annotation_shapes.get(&node).cloned().unwrap_or(Shape::Unknown)
    }

    /// Enters the scopes [node] opens for its children, as `ScopeResolverVisitor`
    /// and `ReferenceResolver` do, and returns the child in which its formal
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
            AstNodeImpl::LocalFunctionDeclarationImpl(d) => {
                // A local function is in scope in its block, and its body.
                self.declare_local(ast, d.name);
                (d.type_parameters, d.body)
            }
            AstNodeImpl::FunctionExpressionImpl(d) => (d.type_parameters, d.body),
            AstNodeImpl::SetterDeclarationImpl(d) => (NO_NODE, d.body),
            AstNodeImpl::TopLevelSetterDeclarationImpl(d) => (NO_NODE, d.body),
            AstNodeImpl::OperatorDeclarationImpl(d) => (NO_NODE, d.body),
            AstNodeImpl::ConstructorDeclaration2Impl(d) => (NO_NODE, d.body),
            AstNodeImpl::BlockImpl(_) | AstNodeImpl::ForStatementImpl(_) | AstNodeImpl::ForElementImpl(_) => {
                self.locals.push(Vec::new());
                return NO_NODE;
            }
            AstNodeImpl::CatchClauseImpl(c) => {
                let mut names = Vec::new();
                for parameter in [c.exception_parameter, c.stack_trace_parameter] {
                    if parameter != NO_NODE {
                        let name = ast.node(parameter).as_catch_clause_parameter_impl().name;
                        names.push(ast.tokens.lexeme_string(name));
                    }
                }
                self.locals.push(names);
                return NO_NODE;
            }
            _ => return NO_NODE,
        };
        let mut names = Vec::new();
        if type_parameters != NO_NODE {
            for &parameter in ast.node(type_parameters).as_type_parameter_list_impl().type_parameters.iter() {
                let name = ast.node(parameter).as_type_parameter_impl().name;
                names.push(ast.tokens.lexeme_string(name));
            }
        }
        self.locals.push(names);
        body
    }

    /// Enters the `TypeParameterScope` and `InstanceScope` (or, when
    /// [instance] is false, `ExtensionScope`) of the declaration [node].
    fn enter_instance(&mut self, node: NodeId, instance: bool, features: ScopeFeatures) {
        let scope = self.scope;
        let Some(declarations) = self.declarations.as_mut() else {
            return;
        };
        let store = declarations.store;
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

    /// Declares the local [name] in the innermost scope of locals.
    fn declare_local(&mut self, ast: Ast<'_>, name: TokenId) {
        if name == NO_TOKEN {
            return;
        }
        if let Some(innermost) = self.locals.last_mut() {
            innermost.push(ast.tokens.lexeme_string(name));
        }
    }

    /// `Scope.lookup(name).getter`, past the locals; `None` when a local
    /// declares [name] or nothing does.
    fn lookup(&self, name: &str) -> Option<ScopeElement> {
        if self.locals.iter().any(|layer| layer.iter().any(|local| local == name)) {
            return None;
        }
        let declarations = self.declarations.as_ref()?;
        declarations.scopes.lookup(declarations.store, self.scope, name).getter
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
        let name = ast.tokens.lexeme_string(n.name);
        let element = if n.import_prefix != NO_NODE {
            let prefix = ast.node(n.import_prefix).as_import_prefix_reference_impl().name;
            match self.lookup(&ast.tokens.lexeme_string(prefix)) {
                Some(ScopeElement::Prefix(p)) => declarations.scopes.lookup_prefix(p, &name).getter,
                _ => None,
            }
        } else {
            self.lookup(&name)
        };
        let Some(ScopeElement::Element(element)) = element else {
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
}

/// The names of the formal parameters of the executable [node].
fn parameter_names(ast: Ast<'_>, node: NodeId) -> Vec<String> {
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
    let mut names = Vec::new();
    if list == NO_NODE {
        return names;
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
    for parameter in parameters {
        let name = match ast.node(parameter) {
            AstNodeImpl::RegularFormalParameterImpl(p) => p.name,
            AstNodeImpl::FieldFormalParameterImpl(p) => p.name,
            AstNodeImpl::SuperFormalParameterImpl(p) => p.name,
            _ => NO_TOKEN,
        };
        if name != NO_TOKEN {
            names.push(ast.tokens.lexeme_string(name));
        }
    }
    names
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
