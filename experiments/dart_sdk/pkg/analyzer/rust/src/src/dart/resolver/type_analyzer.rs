// Port of lib/src/dart/resolver/type_analyzer.dart (with the parts of
// binary_expression_resolver.dart and logical_not_resolver.dart that record a
// type): static types for the expressions whose type no other resolution
// decides. The seven context-independent literals (BooleanLiteral,
// DoubleLiteral, NullLiteral, SimpleStringLiteral, AdjacentStrings,
// StringInterpolation, SymbolLiteral); the operator-typed expressions
// IsExpression, LogicalNot, LogicalAnd and LogicalOr (`bool`) and
// ThrowExpression and RethrowExpression (`Never`); and ParenthesizedExpression,
// which takes the type of the expression it encloses when that is known.
// Flow state, diagnostics, rewrites, contextual integer typing, identifiers,
// invocations and all other expression visitors remain unported. Types are
// stored beside the AST by NodeId, as linking's annotation types are, rather
// than changing parsed nodes.
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, ChildValue, NO_NODE, NodeId};
use crate::src::dart::element::element::{ElementStore, FragmentId, UnitId};
use crate::src::dart::element::r#type::TypeImpl;
use crate::src::dart::element::scope::Scopes;
use crate::src::dart::element::type_provider::TypeProviderImpl;
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
}

impl<'a> TypeAnalyzer<'a> {
    pub fn new(type_provider: &'a TypeProviderImpl) -> Self {
        Self {
            type_provider,
            static_types: HashMap::new(),
            declarations: None,
        }
    }

    /// An analyzer that resolves type annotations against [declarations].
    pub fn with_declarations(type_provider: &'a TypeProviderImpl, declarations: Declarations<'a>) -> Self {
        Self {
            type_provider,
            static_types: HashMap::new(),
            declarations: Some(declarations),
        }
    }

    /// Visits a parsed unit, children before their parent, and records the
    /// types of the expressions listed at the top of this file. This is not a
    /// substitute for full body resolution: every other expression is left
    /// without a type rather than given a guessed one.
    pub fn analyze(&mut self, ast: Ast<'_>, node: NodeId) {
        // visitConfiguration: upstream deliberately does not resolve children.
        if matches!(ast.node(node), AstNodeImpl::ConfigurationImpl(_)) {
            return;
        }
        for child in ast.named_child_entities2(node) {
            match child.value {
                ChildValue::Node(id) => self.analyze(ast, id),
                ChildValue::NodeList(ids) => {
                    for &id in ids {
                        self.analyze(ast, id);
                    }
                }
                _ => (),
            }
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
