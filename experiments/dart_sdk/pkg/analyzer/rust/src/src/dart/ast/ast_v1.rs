// Port of lib/src/dart/ast/ast.dart: the V1 view of the tree, the members
// upstream writes by hand (`V1Projection`, the projection constructors and
// getters of the V2 classes, and the members of the V1-only classes that
// the generator does not translate; see ast.rs).
//
// Upstream builds the V2 nodes and projects the V1 ones from them when the
// V1 view is read: a V2 node caches its projection (`_v1Projection ??=
// X.v1Projection(this)`), whose constructor makes it the V1 parent
// (`_becomeParentOf1`) of its children, projecting them in turn. A projection
// object here is a node in the store's V1 arena (`AstStore::add_v1`), a cache
// is a slot of the store's V1 state (`v1_cached`), and a V1 parent is set
// with `Ast::become_parent_of1`; each runs where upstream's does, so that the
// V1 parents, which depend on the order the view is read in, are upstream's.
//
// Members that read resolution results (elements, types) are not ported:
// parsing leaves them null.

use fe_analyzer_shared::scanner::token::{NO_TOKEN, TokenId};
use fe_analyzer_shared::scanner::token_constants::*;

use crate::src::dart::ast::ast::*;
use crate::src::dart::ast::ast_g::AstVisitor;
use crate::src::dart::ast::ast_store::{
    Ast, AstNodeApi, ChildEntities1, NO_NODE, NodeId, V1_BASE,
};

/// The slots of the caches a node keeps for the V1 view.
pub mod slot {
    /// `_v1Projection`, `_binaryExpression`, `_methodInvocation`, ...: the
    /// V1 projection of a V2 node.
    pub const PROJECTION: u8 = 0;
    /// `_v1StatementProjection`.
    pub const STATEMENT: u8 = 1;
    /// `_v1VariableList`.
    pub const VARIABLE_LIST: u8 = 2;
    /// `_v1Body` of a projected declaration.
    pub const BODY: u8 = 3;
    /// `_v1TypeName` of a projected constructor declaration.
    pub const TYPE_NAME: u8 = 4;
    /// `constructorName` of a constructor reference (`late final`).
    pub const CONSTRUCTOR_NAME: u8 = 5;
    /// `namedType` of a constructor type reference (`late final`).
    pub const NAMED_TYPE: u8 = 6;
    /// `_name` of a constructor selector, `_fieldName`, `_prefix`,
    /// `_identifier`, `_expression`: a V1 child a shared node caches.
    pub const CHILD: u8 = 7;
    /// `_constructorTypeReferenceOrigin` of a projected `NamedTypeImpl`,
    /// `_v1ProjectionOrigin` of a projected `FunctionExpressionImpl`.
    pub const ORIGIN: u8 = 8;
    /// `_v1Children` of an annotation: whether they were made, then each.
    pub const ANNOTATION: u8 = 9;
    pub const ANNOTATION_NAME: u8 = 10;
    pub const ANNOTATION_TYPE_ARGUMENTS: u8 = 11;
    pub const ANNOTATION_PERIOD: u8 = 12;
    pub const ANNOTATION_CONSTRUCTOR_NAME: u8 = 13;
    pub const ANNOTATION_ARGUMENTS: u8 = 14;
}

/// `V1Projection.toV1X`, as the `Ast` method that ports it.
pub type Projection<'a> = fn(Ast<'a>, NodeId) -> NodeId;

// ---------------------------------------------------------------------------
// `enum V1Projection` and the members of `AstNodeImpl` for the V1 view.
// ---------------------------------------------------------------------------

impl<'a> Ast<'a> {
    /// The cached value of [node] in [slot], made by [create] if absent:
    /// `_x ??= create()`.
    fn cached_or(self, node: NodeId, slot: u8, create: impl FnOnce() -> NodeId) -> NodeId {
        let cached = self.store.v1_cached(node, slot);
        if cached != NO_NODE {
            return cached;
        }
        let value = create();
        self.store.set_v1_cached(node, slot, value);
        value
    }

    /// `V1Projection.toV1Argument`.
    pub fn to_v1_argument(self, node: NodeId) -> NodeId {
        if self.node(node).is_expression_impl() {
            return self.to_v1_expression(node);
        }
        node
    }

    /// `V1Projection.toV1ClassBody`.
    pub fn to_v1_class_body(self, node: NodeId) -> NodeId {
        match self.node(node) {
            AstNodeImpl::BlockInstanceDeclarationBodyImpl(_) => {
                self.block_instance_declaration_body_v1_projection(node)
            }
            AstNodeImpl::SemicolonInstanceDeclarationBodyImpl(_) => {
                self.semicolon_instance_declaration_body_v1_projection(node)
            }
            _ => panic!("StateError: An enum body has no V1 class body."),
        }
    }

    /// `V1Projection.toV1ClassMember`.
    pub fn to_v1_class_member(self, node: NodeId) -> NodeId {
        match self.node(node) {
            AstNodeImpl::ConstructorDeclaration2Impl(_) => self.constructor_declaration2_v1_projection(node),
            AstNodeImpl::PrimaryConstructorBody2Impl(_) => self.primary_constructor_body2_v1_projection(node),
            AstNodeImpl::FieldsDeclarationImpl(_) => self.fields_declaration_v1_projection(node),
            _ => self.method_declaration_origin_v1_projection(node),
        }
    }

    /// `V1Projection.toV1CollectionElement`.
    pub fn to_v1_collection_element(self, node: NodeId) -> NodeId {
        if self.node(node).is_expression_impl() {
            return self.to_v1_expression(node);
        }
        node
    }

    /// `V1Projection.toV1CombinatorName`.
    pub fn to_v1_combinator_name(self, node: NodeId) -> NodeId {
        self.combinator_name_v1_projection(node)
    }

    /// `V1Projection.toV1CompilationUnitMember`.
    pub fn to_v1_compilation_unit_member(self, node: NodeId) -> NodeId {
        match self.node(node) {
            AstNodeImpl::ClassDeclaration2Impl(_) => self.class_declaration2_v1_projection(node),
            AstNodeImpl::ClassTypeAlias2Impl(_) => self.class_type_alias2_v1_projection(node),
            AstNodeImpl::EnumDeclaration2Impl(_) => self.enum_declaration2_v1_projection(node),
            AstNodeImpl::ExtensionDeclaration2Impl(_) => self.extension_declaration2_v1_projection(node),
            AstNodeImpl::ExtensionTypeDeclaration2Impl(_) => {
                self.extension_type_declaration2_v1_projection(node)
            }
            AstNodeImpl::FunctionTypeAlias2Impl(_) => self.function_type_alias2_v1_projection(node),
            AstNodeImpl::GenericTypeAlias2Impl(_) => self.generic_type_alias2_v1_projection(node),
            AstNodeImpl::MixinDeclaration2Impl(_) => self.mixin_declaration2_v1_projection(node),
            AstNodeImpl::TopLevelFunctionDeclarationImpl(_)
            | AstNodeImpl::TopLevelGetterDeclarationImpl(_)
            | AstNodeImpl::TopLevelSetterDeclarationImpl(_) => {
                self.function_declaration_origin_v1_projection(node)
            }
            AstNodeImpl::TopLevelVariablesDeclarationImpl(_) => {
                self.top_level_variables_declaration_v1_projection(node)
            }
            other => panic!("{} is not a top-level declaration", other.runtime_type()),
        }
    }

    /// `V1Projection.toV1Expression`.
    pub fn to_v1_expression(self, node: NodeId) -> NodeId {
        self.v1_expression(node, true)
    }

    /// `V1Projection.toV1LocalVariables`.
    pub fn to_v1_local_variables(self, node: NodeId) -> NodeId {
        self.local_variables_declaration_v1_variable_list(node)
    }

    /// `V1Projection.toV1NamedReceiver`.
    pub fn to_v1_named_receiver(self, node: NodeId) -> NodeId {
        if let AstNodeImpl::SuperReferenceImpl(_) = self.node(node) {
            return self.super_reference_v1_projection(node);
        }
        self.to_v1_expression(node)
    }

    /// `V1Projection.toV1RecordLiteralField`.
    pub fn to_v1_record_literal_field(self, node: NodeId) -> NodeId {
        if self.node(node).is_expression_impl() {
            return self.to_v1_expression(node);
        }
        node
    }

    /// `V1Projection.toV1Statement`.
    pub fn to_v1_statement(self, node: NodeId) -> NodeId {
        match self.node(node) {
            AstNodeImpl::LocalFunctionDeclarationImpl(_) => {
                self.local_function_declaration_v1_statement_projection(node)
            }
            AstNodeImpl::LocalVariablesDeclarationStatementImpl(_) => {
                self.local_variables_declaration_statement_v1_statement_projection(node)
            }
            _ => node,
        }
    }

    /// `V1Projection._existingNode(node)`: the V1 representation of [node]
    /// if it exists, without creating it.
    pub fn existing_node(self, node: NodeId) -> NodeId {
        let cached = |slot| self.store.v1_cached(node, slot);
        match self.node(node) {
            n if n.is_expression_impl() => self.v1_expression(node, false),
            AstNodeImpl::SuperReferenceImpl(_) => cached(slot::PROJECTION),
            AstNodeImpl::CascadeSectionImpl(n) => self.existing_node(n.body),
            AstNodeImpl::CombinatorNameImpl(_) => cached(slot::PROJECTION),
            AstNodeImpl::LocalFunctionDeclarationImpl(_) => cached(slot::STATEMENT),
            AstNodeImpl::LocalVariablesDeclarationImpl(_) => cached(slot::VARIABLE_LIST),
            AstNodeImpl::LocalVariablesDeclarationStatementImpl(_) => cached(slot::STATEMENT),
            AstNodeImpl::TopLevelFunctionDeclarationImpl(_)
            | AstNodeImpl::TopLevelGetterDeclarationImpl(_)
            | AstNodeImpl::TopLevelSetterDeclarationImpl(_)
            | AstNodeImpl::ConstructorDeclaration2Impl(_)
            | AstNodeImpl::EnumConstantDeclaration2Impl(_)
            | AstNodeImpl::PrimaryConstructorBody2Impl(_)
            | AstNodeImpl::FieldsDeclarationImpl(_)
            | AstNodeImpl::MethodDeclaration2Impl(_)
            | AstNodeImpl::GetterDeclarationImpl(_)
            | AstNodeImpl::SetterDeclarationImpl(_)
            | AstNodeImpl::OperatorDeclarationImpl(_)
            | AstNodeImpl::TopLevelVariablesDeclarationImpl(_)
            | AstNodeImpl::Field2Impl(_)
            | AstNodeImpl::LocalVariableImpl(_)
            | AstNodeImpl::TopLevelVariable2Impl(_)
            | AstNodeImpl::ClassTypeAlias2Impl(_)
            | AstNodeImpl::EnumDeclaration2Impl(_)
            | AstNodeImpl::ExtensionDeclaration2Impl(_)
            | AstNodeImpl::MixinDeclaration2Impl(_)
            | AstNodeImpl::ClassDeclaration2Impl(_)
            | AstNodeImpl::ExtensionTypeDeclaration2Impl(_)
            | AstNodeImpl::BlockInstanceDeclarationBodyImpl(_)
            | AstNodeImpl::SemicolonInstanceDeclarationBodyImpl(_)
            | AstNodeImpl::BlockEnumDeclarationBodyImpl(_)
            | AstNodeImpl::SemicolonEnumDeclarationBodyImpl(_)
            | AstNodeImpl::FunctionTypeAlias2Impl(_)
            | AstNodeImpl::GenericTypeAlias2Impl(_) => cached(slot::PROJECTION),
            _ => {
                if self.api(node) == AstNodeApi::shared {
                    node
                } else {
                    NO_NODE
                }
            }
        }
    }

    /// `V1Projection._isPrefixedIdentifierName(name)`.
    fn is_prefixed_identifier_name(self, name: TokenId) -> bool {
        use fe_analyzer_shared::scanner::token::Keyword;
        if !self.tokens.is_keyword_or_identifier(name) {
            return false;
        }
        match self.tokens.keyword(name) {
            Some(k) => ![
                &Keyword::ASSERT,
                &Keyword::CONST,
                &Keyword::FALSE,
                &Keyword::NULL,
                &Keyword::SUPER,
                &Keyword::SWITCH,
                &Keyword::THIS,
                &Keyword::TRUE,
            ]
            .iter()
            .any(|keyword| std::ptr::eq::<Keyword>(**keyword, k)),
            None => true,
        }
    }

    /// `V1Projection._materializeEnclosingTree(node)`.
    pub fn materialize_enclosing_tree(self, node: NodeId) {
        let mut root = node;
        loop {
            let parent = self.parent2(root);
            if parent == NO_NODE || self.api(parent) != AstNodeApi::v2 {
                break;
            }
            root = parent;
        }
        // The V1 annotation doesn't project its expression; it exposes the
        // legacy name, type arguments, constructor name, and arguments.
        let root_parent = self.parent2(root);
        if root_parent != NO_NODE {
            if let AstNodeImpl::AnnotationImpl(_) = self.node(root_parent) {
                self.annotation_attach_v1_children(root_parent);
                return;
            }
        }
        let projection = match self.node(root) {
            n if n.is_expression_impl() => self.to_v1_expression(root),
            AstNodeImpl::CascadeSectionImpl(n) => self.to_v1_expression(n.body),
            AstNodeImpl::ConstructorReference2Impl(_) => self.constructor_reference2_constructor_name(root),
            AstNodeImpl::ConstructorTypeReferenceImpl(_) => self.constructor_type_reference_named_type(root),
            AstNodeImpl::LocalFunctionDeclarationImpl(_) => {
                self.local_function_declaration_v1_statement_projection(root)
            }
            AstNodeImpl::LocalVariablesDeclarationImpl(_) => {
                self.local_variables_declaration_v1_variable_list(root)
            }
            AstNodeImpl::LocalVariablesDeclarationStatementImpl(_) => {
                self.local_variables_declaration_statement_v1_statement_projection(root)
            }
            AstNodeImpl::TopLevelFunctionDeclarationImpl(_)
            | AstNodeImpl::TopLevelGetterDeclarationImpl(_)
            | AstNodeImpl::TopLevelSetterDeclarationImpl(_) => {
                self.function_declaration_origin_v1_projection(root)
            }
            AstNodeImpl::ConstructorDeclaration2Impl(_) => self.constructor_declaration2_v1_projection(root),
            AstNodeImpl::EnumConstantDeclaration2Impl(_) => self.enum_constant_declaration2_v1_projection(root),
            AstNodeImpl::PrimaryConstructorBody2Impl(_) => self.primary_constructor_body2_v1_projection(root),
            AstNodeImpl::FieldsDeclarationImpl(_) => self.fields_declaration_v1_projection(root),
            AstNodeImpl::MethodDeclaration2Impl(_)
            | AstNodeImpl::GetterDeclarationImpl(_)
            | AstNodeImpl::SetterDeclarationImpl(_)
            | AstNodeImpl::OperatorDeclarationImpl(_) => self.method_declaration_origin_v1_projection(root),
            AstNodeImpl::TopLevelVariablesDeclarationImpl(_) => {
                self.top_level_variables_declaration_v1_projection(root)
            }
            AstNodeImpl::ClassTypeAlias2Impl(_) => self.class_type_alias2_v1_projection(root),
            AstNodeImpl::EnumDeclaration2Impl(_) => self.enum_declaration2_v1_projection(root),
            AstNodeImpl::ExtensionDeclaration2Impl(_) => self.extension_declaration2_v1_projection(root),
            AstNodeImpl::MixinDeclaration2Impl(_) => self.mixin_declaration2_v1_projection(root),
            AstNodeImpl::ClassDeclaration2Impl(_) => self.class_declaration2_v1_projection(root),
            AstNodeImpl::ExtensionTypeDeclaration2Impl(_) => {
                self.extension_type_declaration2_v1_projection(root)
            }
            AstNodeImpl::FunctionTypeAlias2Impl(_) => self.function_type_alias2_v1_projection(root),
            AstNodeImpl::GenericTypeAlias2Impl(_) => self.generic_type_alias2_v1_projection(root),
            n if n.is_assignment_target_impl() => self.assignment_v1_left_hand_side(root),
            AstNodeImpl::SuperReferenceImpl(_) => self.super_reference_v1_projection(root),
            _ => NO_NODE,
        };
        if projection != NO_NODE && projection != root && root_parent != NO_NODE {
            self.become_parent_of1(root_parent, projection);
        }
    }

    /// `V1Projection._parsedProperty(origin, operand, operator, name)`.
    fn parsed_property(self, origin: NodeId, operand: NodeId, operator: TokenId, name: TokenId) -> NodeId {
        let identifier = self.simple_identifier_v1(name, NO_NODE);
        if let AstNodeImpl::SimpleIdentifierImpl(_) = self.node(operand) {
            if self.tokens.type_(operator).kind == PERIOD_TOKEN
                && self.is_prefixed_identifier_name(name)
            {
                let origin = if self.node(origin).is_expression_impl() {
                    origin
                } else {
                    NO_NODE
                };
                return self.prefixed_identifier_v1(operand, operator, identifier, origin);
            }
        }
        self.property_access_v1_from_parsed_expression(origin, operand, operator, identifier)
    }

    /// `V1Projection._toV1Expression(node, createIfAbsent: create)`.
    pub fn v1_expression(self, node: NodeId, create: bool) -> NodeId {
        let cached = |slot| self.store.v1_cached(node, slot);
        match self.node(node) {
            AstNodeImpl::InvalidSuperExpressionImpl(n) => {
                return if create {
                    self.super_reference_v1_projection(n.super_reference)
                } else {
                    self.store.v1_cached(n.super_reference, slot::PROJECTION)
                };
            }
            AstNodeImpl::ParsedDotShorthandExpressionImpl(n) => {
                return self.v1_expression(n.expression, create);
            }
            AstNodeImpl::ParsedCascadeNameImpl(_)
            | AstNodeImpl::ParsedDotShorthandNameImpl(_)
            | AstNodeImpl::ParsedNameAccessImpl(_)
            | AstNodeImpl::ParsedTypeArgumentsImpl(_)
            | AstNodeImpl::ParsedUnqualifiedNameImpl(_)
            | AstNodeImpl::ParsedValueArgumentsImpl(_) => {
                return if create {
                    self.parsed_expression_v1_projection(node)
                } else {
                    cached(slot::PROJECTION)
                };
            }
            _ => {}
        }
        // The projections of the classes only resolution builds
        // (`FunctionInstantiationImpl`, `ImplicitCallTearOffImpl`, ...) are
        // not ported: no such node is in the store.
        let projection = match self.node(node) {
            AstNodeImpl::CallInvocationImpl(_) => Some(Self::call_invocation_function_expression_invocation as Projection<'a>),
            AstNodeImpl::DotShorthandConstructorInvocation2Impl(_) => {
                Some(Self::dot_shorthand_constructor_invocation2_projection as Projection<'a>)
            }
            AstNodeImpl::DotShorthandNameExpressionImpl(_) => {
                Some(Self::dot_shorthand_name_expression_projection as Projection<'a>)
            }
            AstNodeImpl::ConstructorInvocationImpl(_) => {
                Some(Self::constructor_invocation_instance_creation_expression as Projection<'a>)
            }
            AstNodeImpl::CompoundAssignmentImpl(_)
            | AstNodeImpl::DirectAssignmentImpl(_)
            | AstNodeImpl::IfNullAssignmentImpl(_) => Some(Self::assignment_expression_projection as Projection<'a>),
            AstNodeImpl::BinaryOperatorInvocationImpl(_)
            | AstNodeImpl::IfNullImpl(_)
            | AstNodeImpl::LogicalAndImpl(_)
            | AstNodeImpl::LogicalOrImpl(_) => Some(Self::binary_expression_projection as Projection<'a>),
            AstNodeImpl::CascadeIndexExpressionImpl(_) | AstNodeImpl::ReceiverIndexExpressionImpl(_) => {
                Some(Self::index_expression2_index_expression as Projection<'a>)
            }
            AstNodeImpl::CascadePropertyExtractionImpl(_) => {
                Some(Self::cascade_property_extraction_property_access as Projection<'a>)
            }
            AstNodeImpl::LogicalNotImpl(_) | AstNodeImpl::UnaryOperatorInvocationImpl(_) => {
                Some(Self::prefix_expression_projection as Projection<'a>)
            }
            AstNodeImpl::NullAssertionExpressionImpl(_) => Some(Self::postfix_expression_projection as Projection<'a>),
            AstNodeImpl::IncrementOrDecrementExpressionImpl(_) => {
                Some(Self::increment_or_decrement_expression_v1_projection as Projection<'a>)
            }
            AstNodeImpl::ReceiverPropertyExtractionImpl(_) => {
                Some(Self::receiver_property_extraction_v1_projection as Projection<'a>)
            }
            _ => None,
        };
        match projection {
            Some(project) => {
                if create {
                    project(self, node)
                } else {
                    cached(slot::PROJECTION)
                }
            }
            None => node,
        }
    }

    /// `V1Projection._usesPrefixedIdentifier(receiver, operator, name,
    /// target)`, without types: parsing leaves the receiver's static type
    /// null, which is not a record type.
    fn uses_prefixed_identifier(self, operator: TokenId, name: TokenId, target: NodeId) -> bool {
        if self.tokens.type_(operator).kind != PERIOD_TOKEN {
            return false;
        }
        if !matches!(self.node(target), AstNodeImpl::SimpleIdentifierImpl(_)) {
            return false;
        }
        self.is_prefixed_identifier_name(name)
    }

    /// `_V1ProjectedNodeListImpl(base, project)` read whole: each element
    /// projected, its V1 parent the owner of the list.
    pub fn v1_projected_list(self, owner: NodeId, base: &[NodeId], project: Projection<'a>) -> Vec<NodeId> {
        base.iter()
            .map(|&element| self.become_parent_of1(owner, project(self, element)))
            .collect()
    }

    /// `_V1ProjectedNodeListImpl._elementContainingRange`: the base's
    /// element, projected.
    pub fn v1_projected_element_containing_range(
        self,
        owner: NodeId,
        base: &[NodeId],
        project: Projection<'a>,
        range_offset: i32,
        range_end: i32,
    ) -> NodeId {
        let result = self.element_containing_range(base, range_offset, range_end);
        if result != NO_NODE {
            return self.become_parent_of1(owner, project(self, result));
        }
        NO_NODE
    }

    /// `_visitCommentAndAnnotations(visitor)` of an annotated node.
    pub fn visit_comment_and_annotations<V: AstVisitor + ?Sized>(
        self,
        documentation_comment: NodeId,
        metadata: &[NodeId],
        visitor: &mut V,
    ) {
        // _commentIsBeforeAnnotations()
        if documentation_comment == NO_NODE
            || metadata.is_empty()
            || self.offset(documentation_comment) < self.offset(metadata[0])
        {
            if documentation_comment != NO_NODE {
                self.accept(documentation_comment, visitor);
            }
            for &annotation in metadata {
                self.accept(annotation, visitor);
            }
        } else {
            let comment = [documentation_comment];
            for node in self.sorted_by_offset(&[&comment, metadata]) {
                self.accept(node, visitor);
            }
        }
    }

    /// `_v1ProjectionSource`: the canonical node a V1 projection was built
    /// from, or `NO_NODE`.
    pub fn v1_projection_source(self, id: NodeId) -> NodeId {
        use AstNodeImpl as N;
        match self.node(id) {
            N::AssignmentExpressionImpl(n) => n.v1_projection_origin,
            N::BinaryExpressionImpl(n) => n.origin,
            N::BlockClassBodyImpl(n) => n.v1_projection_origin,
            N::BlockEnumBodyImpl(n) => n.v1_projection_origin,
            N::ClassDeclarationImpl(n) => n.v1_projection_origin,
            N::ClassTypeAliasImpl(n) => n.v1_projection_origin,
            N::ConstructorDeclarationImpl(n) => n.v1_projection_origin,
            N::ConstructorNameImpl(n) => n.origin,
            N::ConstructorReferenceImpl(n) => n.origin,
            N::DotShorthandConstructorInvocationImpl(n) => n.v1_projection_origin,
            N::DotShorthandInvocationImpl(n) => or(n.v1_projection_origin, n.parsed_expression_origin),
            N::DotShorthandPropertyAccessImpl(n) => or(n.v1_projection_origin, n.parsed_expression_origin),
            N::EmptyClassBodyImpl(n) => n.v1_projection_origin,
            N::EmptyEnumBodyImpl(n) => n.v1_projection_origin,
            N::EnumConstantDeclarationImpl(n) => n.v1_projection_origin,
            N::EnumDeclarationImpl(n) => n.v1_projection_origin,
            N::ExtensionDeclarationImpl(n) => n.v1_projection_origin,
            N::ExtensionOverrideImpl(n) => n.origin,
            N::ExtensionTypeDeclarationImpl(n) => n.v1_projection_origin,
            N::FieldDeclarationImpl(n) => n.v1_projection_origin,
            N::FunctionDeclarationImpl(n) => n.v1_projection_origin,
            N::FunctionDeclarationStatementImpl(n) => n.v1_projection_origin,
            N::FunctionExpressionInvocationImpl(n) => n.origin,
            N::FunctionReferenceImpl(n) => n.v1_projection_origin,
            N::FunctionTypeAliasImpl(n) => n.v1_projection_origin,
            N::GenericTypeAliasImpl(n) => n.v1_projection_origin,
            N::ImplicitCallReferenceImpl(n) => n.v1_projection_origin,
            N::IndexExpressionImpl(n) => n.v1_projection_origin,
            N::InstanceCreationExpressionImpl(n) => or(n.origin, n.parsed_origin),
            N::MethodDeclarationImpl(n) => n.v1_projection_origin,
            N::MethodInvocationImpl(n) => or(n.v1_projection_origin, n.parsed_expression_origin),
            N::MixinDeclarationImpl(n) => n.v1_projection_origin,
            N::PostfixExpressionImpl(n) => n.origin,
            N::PrefixedIdentifierImpl(n) => n.v1_projection_origin,
            N::PrefixExpressionImpl(n) => n.origin,
            N::PrimaryConstructorBodyImpl(n) => n.v1_projection_origin,
            N::PropertyAccessImpl(n) => n.v1_projection_origin,
            N::SimpleIdentifierImpl(n) => n.v1_projection_origin,
            N::SuperExpressionImpl(n) => n.origin,
            N::TopLevelVariableDeclarationImpl(n) => n.v1_projection_origin,
            N::VariableDeclarationImpl(n) => n.v1_projection_origin,
            N::VariableDeclarationListImpl(n) => n.v1_projection_origin,
            N::VariableDeclarationStatementImpl(n) => n.v1_projection_origin,
            N::NamedTypeImpl(_) | N::FunctionExpressionImpl(_) if id >= V1_BASE => {
                self.store.v1_cached(id, slot::ORIGIN)
            }
            _ => NO_NODE,
        }
    }

    /// `_v1CascadeOperator`: the cascade operator that begins this V1
    /// projection, or nothing.
    fn v1_cascade_operator(self, id: NodeId) -> Vec<u16> {
        let token = self.begin_token(id);
        let kind = self.tokens.type_(token).kind;
        if kind == PERIOD_PERIOD_TOKEN || kind == QUESTION_PERIOD_PERIOD_TOKEN {
            return self.tokens.lexeme(token);
        }
        Vec::new()
    }

    /// `node.toSource()` of a node of the V1 view that is not in the V2
    /// view; `None` for a node that prints with the `ToSourceVisitor`.
    pub fn v1_to_source(self, id: NodeId) -> Option<Vec<u16>> {
        use AstNodeImpl as N;
        let lexeme = |token: TokenId| self.tokens.lexeme(token);
        let through = |origin: NodeId| -> Vec<u16> {
            let mut result = self.v1_cascade_operator(id);
            result.extend(self.parsed_expression_to_source_through(origin, self.end_token(id)));
            result
        };
        match self.node(id) {
            N::SimpleIdentifierImpl(n) => return Some(lexeme(n.token)),
            N::SuperExpressionImpl(_) => return Some("super".encode_utf16().collect()),
            N::VariableDeclarationListImpl(n) => {
                let mut parts: Vec<Vec<u16>> = Vec::new();
                for &annotation in &n.metadata {
                    parts.push(self.to_source_units(annotation));
                }
                if n.late_keyword != NO_TOKEN {
                    parts.push(lexeme(n.late_keyword));
                }
                if n.keyword != NO_TOKEN {
                    parts.push(lexeme(n.keyword));
                }
                let type_ = n.type_(self, id);
                if type_ != NO_NODE {
                    parts.push(self.to_source_units(type_));
                }
                let mut variables = Vec::new();
                for (i, &variable) in n.variables.iter().enumerate() {
                    if i > 0 {
                        variables.extend(", ".encode_utf16());
                    }
                    variables.extend(self.to_source_units(variable));
                }
                parts.push(variables);
                return Some(parts.join(&(' ' as u16)));
            }
            N::ConstructorNameImpl(n) => {
                if n.origin != NO_NODE {
                    return Some(self.to_source_units(n.origin));
                }
                let mut result = self.to_source_units(n.type_(self, id));
                result.push('.' as u16);
                result.extend(lexeme(self.node(n.name(self, id)).as_simple_identifier_impl().token));
                return Some(result);
            }
            N::DotShorthandInvocationImpl(n) => {
                if n.v1_projection_origin != NO_NODE {
                    return Some(self.to_source_units(n.v1_projection_origin));
                }
                return Some(self.parsed_expression_to_source_through(
                    n.parsed_expression_origin,
                    self.end_token(id),
                ));
            }
            N::DotShorthandPropertyAccessImpl(n) => {
                if n.v1_projection_origin != NO_NODE {
                    return Some(self.to_source_units(n.v1_projection_origin));
                }
                return Some(self.to_source_units(n.parsed_expression_origin));
            }
            N::FunctionReferenceImpl(n) => {
                let origin = n.v1_projection_origin;
                if self.node(origin).is_parsed_expression_impl() {
                    return Some(through(origin));
                }
                let mut result = self.v1_cascade_operator(id);
                result.extend(self.to_source_units(origin));
                return Some(result);
            }
            N::IndexExpressionImpl(n) => {
                let mut result = self.v1_cascade_operator(id);
                result.extend(self.to_source_units(n.v1_projection_origin));
                return Some(result);
            }
            N::InstanceCreationExpressionImpl(n) => {
                if n.origin != NO_NODE {
                    return Some(self.to_source_units(n.origin));
                }
                return Some(self.parsed_expression_to_source_through(n.parsed_origin, self.end_token(id)));
            }
            N::MethodInvocationImpl(n) => {
                if n.v1_projection_origin != NO_NODE {
                    let mut result = self.v1_cascade_operator(id);
                    result.extend(self.to_source_units(n.v1_projection_origin));
                    return Some(result);
                }
                if n.parsed_expression_origin != NO_NODE {
                    return Some(through(n.parsed_expression_origin));
                }
            }
            N::PropertyAccessImpl(n) => {
                let origin = n.v1_projection_origin;
                match self.node(origin) {
                    N::CascadePropertyAssignmentTargetImpl(o) => {
                        let mut result = lexeme(n.operator_(self, id));
                        result.extend(lexeme(o.name));
                        return Some(result);
                    }
                    N::CascadePropertyExtractionImpl(o) => {
                        let mut result = lexeme(n.operator_(self, id));
                        result.extend(lexeme(o.name));
                        return Some(result);
                    }
                    o if o.is_parsed_expression_impl() => return Some(through(origin)),
                    _ => {
                        let mut result = self.v1_cascade_operator(id);
                        result.extend(self.to_source_units(origin));
                        return Some(result);
                    }
                }
            }
            N::NamedTypeImpl(n) if id >= V1_BASE => {
                let origin = self.store.v1_cached(id, slot::ORIGIN);
                if origin != NO_NODE {
                    return Some(self.to_source_units(origin));
                }
                // `_astNodeApi == AstNodeApi.v1`: a projection object.
                let mut result = Vec::new();
                let prefix = n.import_prefix(self, id);
                if prefix != NO_NODE {
                    result.extend(lexeme(self.node(prefix).as_import_prefix_reference_impl().name));
                    result.push('.' as u16);
                }
                result.extend(lexeme(n.name));
                let type_arguments = n.type_arguments(self, id);
                if type_arguments != NO_NODE {
                    result.extend(self.to_source_units(type_arguments));
                }
                return Some(result);
            }
            _ => {}
        }
        // A V1 projection without a V2 view prints its canonical source node.
        if self.api(id) == AstNodeApi::v1 {
            let source = self.v1_projection_source(id);
            if source != NO_NODE {
                let mut result = self.v1_cascade_operator(id);
                result.extend(self.to_source_units(source));
                return Some(result);
            }
        }
        None
    }

    /// `ParsedExpressionImpl._toSourceThrough(endToken)`.
    fn parsed_expression_to_source_through(self, chain: NodeId, end_token: TokenId) -> Vec<u16> {
        let mut node = chain;
        let end = self.tokens.end(end_token);
        while self.end(node) > end {
            node = match self.node(node) {
                AstNodeImpl::ParsedNameAccessImpl(n) => n.operand,
                AstNodeImpl::ParsedTypeArgumentsImpl(n) => n.operand,
                AstNodeImpl::ParsedValueArgumentsImpl(n) => n.operand,
                _ => panic!("StateError: No parsed prefix ending at the token"),
            };
        }
        self.to_source_units(node)
    }

    /// The V1 parent a parsed node has before anything reads the V1 view:
    /// the one the constructor (or setter) of its V2 parent gave it. The
    /// shared nodes are linked in both views by their shared parents
    /// (`_becomeParentOf12`, `_becomeParentOf2AndExisting1`, a list's
    /// `_initialize`), and in neither by the nodes only in the V2 view
    /// (`_becomeParentOf2`), except that `DelimitedFormalParametersImpl`
    /// links its parameters to the `FormalParameterListImpl` holding it, and
    /// a `CascadeExpressionImpl` links the bodies of its sections.
    pub fn initial_parent1(self, id: NodeId) -> NodeId {
        let parent = self.parent2(id);
        if parent == NO_NODE {
            return NO_NODE;
        }
        match self.node(parent) {
            AstNodeImpl::DelimitedFormalParametersImpl(_) => {
                let list = self.parent2(parent);
                if list != NO_NODE {
                    if let AstNodeImpl::FormalParameterListImpl(_) = self.node(list) {
                        return list;
                    }
                }
                return NO_NODE;
            }
            AstNodeImpl::CascadeSectionImpl(n) if n.body == id => {
                let cascade = self.parent2(parent);
                if cascade != NO_NODE && self.api(id) == AstNodeApi::shared {
                    if let AstNodeImpl::CascadeExpressionImpl(_) = self.node(cascade) {
                        return cascade;
                    }
                }
                return NO_NODE;
            }
            _ => {}
        }
        if self.api(parent) == AstNodeApi::v2 {
            return NO_NODE;
        }
        parent
    }
}

fn or(a: NodeId, b: NodeId) -> NodeId {
    if a != NO_NODE { a } else { b }
}

// ---------------------------------------------------------------------------
// The projections of the V2 nodes: `v1Projection`, `binaryExpression`, ...
// ---------------------------------------------------------------------------

impl<'a> Ast<'a> {
    /// `SimpleIdentifierImpl.v1Projection(token: token, origin: origin)`.
    pub fn simple_identifier_v1(self, token: TokenId, origin: NodeId) -> NodeId {
        self.store.add_v1(SimpleIdentifierImpl {
            token,
            v1_projection_origin: origin,
        })
    }

    /// `PrefixedIdentifierImpl.v1Projection(prefix:, period:, identifier:,
    /// origin:)`.
    pub fn prefixed_identifier_v1(self, prefix: NodeId, period: TokenId, identifier: NodeId, origin: NodeId) -> NodeId {
        let id = self.store.add_v1(PrefixedIdentifierImpl {
            prefix,
            period,
            v1_projection_origin: origin,
            identifier,
        });
        self.become_parent_of1(id, prefix);
        self.become_parent_of1(id, identifier);
        id
    }

    /// `PropertyAccessImpl.v1ProjectionFromParsedExpression(origin, target,
    /// operator, propertyName)` and the other constructors, which differ in
    /// the fields they set.
    fn property_access_v1(self, origin: NodeId, target: NodeId, operator: TokenId, property_name: NodeId) -> NodeId {
        let id = self.store.add_v1(PropertyAccessImpl {
            operator_: operator,
            target2: target,
            property_name,
            v1_projection_origin: origin,
        });
        // _attachV1Children()
        let n = self.node(id).as_property_access_impl();
        self.become_parent_of1(id, n.target(self, id));
        self.become_parent_of1(id, n.property_name(self, id));
        id
    }

    fn property_access_v1_from_parsed_expression(
        self,
        origin: NodeId,
        target: NodeId,
        operator: TokenId,
        property_name: NodeId,
    ) -> NodeId {
        self.property_access_v1(origin, target, operator, property_name)
    }

    /// `ParsedExpressionImpl.v1Projection`.
    fn parsed_expression_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || self.parsed_expression_build(node))
    }

    /// `_ParsedExpressionBuilder(chain).build()`.
    fn parsed_expression_build(self, chain: NodeId) -> NodeId {
        use AstNodeImpl as N;
        let mut node = chain;
        loop {
            node = match self.node(node) {
                N::ParsedNameAccessImpl(n) => n.operand,
                N::ParsedTypeArgumentsImpl(n) => n.operand,
                N::ParsedValueArgumentsImpl(n) => n.operand,
                _ => break,
            };
        }
        let mut parent = self.parent2(node);
        let mut result = match self.node(node) {
            N::ParsedCascadeNameImpl(n) => {
                let section = self.this_or_ancestor_matching2(node, |a| {
                    matches!(self.node(a), N::CascadeSectionImpl(_))
                });
                let operator = self.node(section).as_cascade_section_impl().operator_;
                let identifier = self.simple_identifier_v1(n.name, NO_NODE);
                self.property_access_v1_from_parsed_expression(node, NO_NODE, operator, identifier)
            }
            N::ParsedDotShorthandNameImpl(_) => self.dot_shorthand_property_access_v1_from_parsed_expression(node),
            N::ParsedUnqualifiedNameImpl(n) => self.simple_identifier_v1(n.name, node),
            _ => self.to_v1_named_receiver(node),
        };
        while node != chain {
            node = parent;
            parent = self.parent2(node);
            match self.node(node) {
                N::ParsedNameAccessImpl(n) => {
                    result = self.parsed_property(node, result, n.operator_, n.name);
                }
                N::ParsedTypeArgumentsImpl(n) => {
                    let type_arguments = n.type_arguments;
                    // Adjacent type and value arguments form one application.
                    // Avoid constructing a tear-off for the intermediate parsed
                    // prefix, but preserve that prefix when it is the requested
                    // projection root.
                    if node != chain {
                        if let N::ParsedValueArgumentsImpl(arguments) = self.node(parent) {
                            result = self.parsed_invoke(chain, result, type_arguments, arguments.argument_list);
                            node = parent;
                            parent = self.parent2(node);
                            continue;
                        }
                    }
                    // C<T>.named() is constructor syntax, unlike C.named<T>().
                    // Do not consume parents outside the particular projection
                    // being requested.
                    if node != chain && self.node(result).is_identifier_impl() {
                        if let N::ParsedNameAccessImpl(selector) = self.node(parent) {
                            if parent != chain {
                                let selector_parent = self.parent2(parent);
                                if selector_parent != NO_NODE {
                                    if let N::ParsedValueArgumentsImpl(arguments) = self.node(selector_parent) {
                                        result = self.parsed_constructor(
                                            chain,
                                            result,
                                            type_arguments,
                                            selector.operator_,
                                            selector.name,
                                            arguments.argument_list,
                                        );
                                        node = selector_parent;
                                        parent = self.parent2(node);
                                        continue;
                                    }
                                }
                            }
                        }
                    }
                    result = self.function_reference_v1(chain, result, type_arguments);
                }
                N::ParsedValueArgumentsImpl(n) => {
                    result = self.parsed_invoke(chain, result, NO_NODE, n.argument_list);
                }
                _ => panic!("StateError: A parsed name cannot contain an operand."),
            }
        }
        result
    }

    /// `_ParsedExpressionBuilder._constructor`.
    fn parsed_constructor(
        self,
        chain: NodeId,
        type_name: NodeId,
        type_arguments: NodeId,
        selector_operator: TokenId,
        selector_name: TokenId,
        argument_list: NodeId,
    ) -> NodeId {
        let (name, prefix) = match self.node(type_name) {
            AstNodeImpl::SimpleIdentifierImpl(n) => (n.token, NO_NODE),
            AstNodeImpl::PrefixedIdentifierImpl(n) => {
                let identifier = n.identifier;
                let prefix_token = self.node(n.prefix).as_simple_identifier_impl().token;
                let prefix = self.store.add_v1(ImportPrefixReferenceImpl {
                    name: prefix_token,
                    period: n.period,
                });
                (self.node(identifier).as_simple_identifier_impl().token, prefix)
            }
            _ => panic!("not an identifier"),
        };
        // NamedTypeImpl.v1ProjectionFromParsedExpression
        let named_type = self.store.add_v1(NamedTypeImpl {
            import_prefix: prefix,
            name,
            type_arguments,
            question: NO_TOKEN,
        });
        self.store.set_api_override(named_type, AstNodeApi::v1);
        self.become_parent_of1(named_type, prefix);
        self.become_parent_of1(named_type, type_arguments);
        // ConstructorNameImpl.v1ProjectionFromParsedExpression
        let parsed_name = self.simple_identifier_v1(selector_name, NO_NODE);
        let constructor_name = self.store.add_v1(ConstructorNameImpl {
            origin: NO_NODE,
            parsed_type: named_type,
            parsed_period: selector_operator,
            parsed_name,
        });
        self.become_parent_of1(constructor_name, named_type);
        self.become_parent_of1(constructor_name, parsed_name);
        // InstanceCreationExpressionImpl.v1ProjectionFromParsedExpression
        let id = self.store.add_v1(InstanceCreationExpressionImpl {
            origin: NO_NODE,
            parsed_origin: chain,
            parsed_constructor_name: constructor_name,
            parsed_argument_list: argument_list,
        });
        self.instance_creation_expression_attach(id);
        id
    }

    /// `_ParsedExpressionBuilder._invoke`.
    fn parsed_invoke(self, chain: NodeId, function: NodeId, type_arguments: NodeId, argument_list: NodeId) -> NodeId {
        use AstNodeImpl as N;
        if let N::DotShorthandPropertyAccessImpl(f) = self.node(function) {
            let name = self.node(f.property_name(self, function)).as_simple_identifier_impl().token;
            return self.dot_shorthand_invocation_v1(NO_NODE, chain, f.period, name, type_arguments, argument_list);
        }
        let (target, operator, name) = match self.node(function) {
            N::SimpleIdentifierImpl(n) => (NO_NODE, NO_TOKEN, n.token),
            N::PrefixedIdentifierImpl(n) => (
                n.prefix,
                n.period,
                self.node(n.identifier).as_simple_identifier_impl().token,
            ),
            N::PropertyAccessImpl(n) => (
                n.target2(self, function),
                n.operator_(self, function),
                self.node(n.property_name(self, function))
                    .as_simple_identifier_impl()
                    .token,
            ),
            _ => panic!("StateError: A parsed named invocation must end in a name."),
        };
        // MethodInvocationImpl.v1ProjectionFromParsedExpression
        let method_name = self.simple_identifier_v1(name, NO_NODE);
        let id = self.store.add_v1(MethodInvocationImpl {
            target2: target,
            operator_: operator,
            method_name,
            v1_projection_origin: NO_NODE,
            parsed_expression_origin: chain,
            argument_list,
            type_arguments,
        });
        // InvocationExpressionImpl.v1Projection
        self.become_parent_of1(id, type_arguments);
        self.become_parent_of1(id, argument_list);
        self.become_parent_of1(id, target);
        self.become_parent_of1(id, method_name);
        id
    }

    /// `FunctionReferenceImpl.v1ProjectionFromParsedExpression`.
    fn function_reference_v1(self, origin: NodeId, function: NodeId, type_arguments: NodeId) -> NodeId {
        let id = self.store.add_v1(FunctionReferenceImpl {
            type_arguments,
            function2: function,
            v1_projection_origin: origin,
        });
        let n = self.node(id).as_function_reference_impl();
        self.become_parent_of1(id, n.function(self, id));
        self.become_parent_of1(id, n.type_arguments);
        id
    }

    /// `DotShorthandPropertyAccessImpl.v1ProjectionFromParsedExpression`.
    fn dot_shorthand_property_access_v1_from_parsed_expression(self, origin: NodeId) -> NodeId {
        let n = self.node(origin).as_parsed_dot_shorthand_name_impl();
        let property_name = self.simple_identifier_v1(n.name, NO_NODE);
        let id = self.store.add_v1(DotShorthandPropertyAccessImpl {
            period: n.period,
            property_name,
            v1_projection_origin: NO_NODE,
            parsed_expression_origin: origin,
        });
        self.become_parent_of1(id, property_name);
        id
    }

    /// `DotShorthandNameExpressionImpl.dotShorthandPropertyAccess`.
    fn dot_shorthand_name_expression_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let n = self.node(node).as_dot_shorthand_name_expression_impl();
            let property_name = self.simple_identifier_v1(n.name, NO_NODE);
            let id = self.store.add_v1(DotShorthandPropertyAccessImpl {
                period: n.period,
                property_name,
                v1_projection_origin: node,
                parsed_expression_origin: NO_NODE,
            });
            self.become_parent_of1(id, property_name);
            id
        })
    }

    /// `DotShorthandInvocationImpl.v1ProjectionFromParsedExpression` (and
    /// `v1ProjectionFromMethodInvocation`, for which [origin] is set).
    fn dot_shorthand_invocation_v1(
        self,
        origin: NodeId,
        parsed_origin: NodeId,
        period: TokenId,
        name: TokenId,
        type_arguments: NodeId,
        argument_list: NodeId,
    ) -> NodeId {
        let member_name = self.simple_identifier_v1(name, NO_NODE);
        let id = self.store.add_v1(DotShorthandInvocationImpl {
            period,
            member_name,
            v1_projection_origin: origin,
            parsed_expression_origin: parsed_origin,
            argument_list,
            type_arguments,
        });
        // InvocationExpressionImpl.v1Projection
        self.become_parent_of1(id, type_arguments);
        self.become_parent_of1(id, argument_list);
        // _attachV1Children()
        let n = self.node(id).as_dot_shorthand_invocation_impl();
        self.become_parent_of1(id, n.member_name(self, id));
        self.become_parent_of1(id, n.type_arguments(self, id));
        self.become_parent_of1(id, n.argument_list(self, id));
        id
    }

    /// `DotShorthandConstructorInvocation2Impl.dotShorthandConstructorInvocation`.
    fn dot_shorthand_constructor_invocation2_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let origin = self.node(node).as_dot_shorthand_constructor_invocation2_impl();
            let constructor_name = self.simple_identifier_v1(origin.name, NO_NODE);
            let id = self.store.add_v1(DotShorthandConstructorInvocationImpl {
                period: origin.period,
                constructor_name,
                v1_projection_origin: node,
                argument_list: origin.argument_list,
                type_arguments: origin.type_arguments,
            });
            // InvocationExpressionImpl.v1Projection
            self.become_parent_of1(id, origin.type_arguments);
            self.become_parent_of1(id, origin.argument_list);
            // _attachV1Children()
            let n = self.node(id).as_dot_shorthand_constructor_invocation_impl();
            self.become_parent_of1(id, n.constructor_name(self, id));
            self.become_parent_of1(id, n.type_arguments(self, id));
            self.become_parent_of1(id, n.argument_list(self, id));
            id
        })
    }

    /// `CallInvocationImpl.functionExpressionInvocation`.
    fn call_invocation_function_expression_invocation(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let origin = self.node(node).as_call_invocation_impl();
            let id = self.store.add_v1(FunctionExpressionInvocationImpl {
                origin: node,
                argument_list: origin.argument_list,
                type_arguments: origin.type_arguments,
            });
            // InvocationExpressionImpl.v1Projection
            self.become_parent_of1(id, origin.type_arguments);
            self.become_parent_of1(id, origin.argument_list);
            let n = self.node(id).as_function_expression_invocation_impl();
            self.become_parent_of1(id, n.function(self, id));
            id
        })
    }

    /// `ConstructorInvocationImpl.instanceCreationExpression`.
    fn constructor_invocation_instance_creation_expression(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let id = self.store.add_v1(InstanceCreationExpressionImpl {
                origin: node,
                parsed_origin: NO_NODE,
                parsed_constructor_name: NO_NODE,
                parsed_argument_list: NO_NODE,
            });
            self.instance_creation_expression_attach(id);
            id
        })
    }

    /// `InstanceCreationExpressionImpl._attachV1Children()`.
    fn instance_creation_expression_attach(self, id: NodeId) {
        let n = self.node(id).as_instance_creation_expression_impl();
        self.become_parent_of1(id, n.constructor_name(self, id));
        self.become_parent_of1(id, n.type_arguments(self, id));
        self.become_parent_of1(id, n.argument_list(self, id));
    }

    /// `ConstructorReference2Impl.constructorName` (`late final`).
    pub fn constructor_reference2_constructor_name(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::CONSTRUCTOR_NAME, || {
            // ConstructorNameImpl._(origin)
            let id = self.store.add_v1(ConstructorNameImpl {
                origin: node,
                parsed_type: NO_NODE,
                parsed_period: NO_TOKEN,
                parsed_name: NO_NODE,
            });
            let n = self.node(id).as_constructor_name_impl();
            self.become_parent_of1(id, n.type_(self, id));
            self.become_parent_of1(id, n.name(self, id));
            id
        })
    }

    /// `ConstructorTypeReferenceImpl.namedType` (`late final`):
    /// `NamedTypeImpl.v1Projection(this)`.
    pub fn constructor_type_reference_named_type(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::NAMED_TYPE, || {
            let origin = self.node(node).as_constructor_type_reference_impl();
            let id = self.store.add_v1(NamedTypeImpl {
                import_prefix: origin.import_prefix,
                name: origin.name,
                type_arguments: origin.type_arguments,
                question: NO_TOKEN,
            });
            self.store.set_v1_cached(id, slot::ORIGIN, node);
            self.store.set_api_override(id, AstNodeApi::v1);
            self.become_parent_of1(id, origin.import_prefix);
            self.become_parent_of1(id, origin.type_arguments);
            id
        })
    }

    /// `AssignmentExpressionImpl.v1ProjectionFrom{Compound,Direct,IfNull}`
    /// through the origin's `assignmentExpression`.
    fn assignment_expression_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let operator = match self.node(node) {
                AstNodeImpl::CompoundAssignmentImpl(n) => n.operator_,
                AstNodeImpl::DirectAssignmentImpl(n) => n.operator_,
                AstNodeImpl::IfNullAssignmentImpl(n) => n.operator_,
                _ => unreachable!(),
            };
            let id = self.store.add_v1(AssignmentExpressionImpl {
                operator_: operator,
                v1_projection_origin: node,
            });
            let n = self.node(id).as_assignment_expression_impl();
            self.become_parent_of1(id, n.left_hand_side(self, id));
            self.become_parent_of1(id, n.right_hand_side(self, id));
            id
        })
    }

    /// `AssignmentExpressionImpl._v1LeftHandSide(target)` for the targets
    /// parsing builds.
    pub fn assignment_v1_left_hand_side(self, target: NodeId) -> NodeId {
        use AstNodeImpl as N;
        match self.node(target) {
            N::ParsedNameAccessAssignmentTargetImpl(_) => self.parsed_assignment_target_v1_projection(target),
            N::InvalidSuperAssignmentTargetImpl(n) => self.super_reference_v1_projection(n.super_reference),
            N::CascadePropertyAssignmentTargetImpl(_) => self.cascade_property_assignment_target_property_access(target),
            N::ReceiverPropertyAssignmentTargetImpl(_) => self.receiver_property_assignment_target_v1_projection(target),
            N::CascadeIndexAssignmentTargetImpl(_) | N::ReceiverIndexAssignmentTargetImpl(_) => {
                self.index_assignment_target_index_expression(target)
            }
            N::UnqualifiedNameAssignmentTargetImpl(_) => self.unqualified_name_assignment_target_simple_identifier(target),
            N::InvalidExpressionAssignmentTargetImpl(n) => self.to_v1_expression(n.expression),
            other => panic!("{} is not an assignment target", other.runtime_type()),
        }
    }

    /// `ParsedAssignmentTargetImpl.v1Projection`.
    fn parsed_assignment_target_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let n = self.node(node).as_parsed_name_access_assignment_target_impl();
            let operand = self.parsed_expression_v1_projection(n.operand);
            self.parsed_property(node, operand, n.operator_, n.name)
        })
    }

    /// `UnqualifiedNameAssignmentTargetImpl.simpleIdentifier`.
    fn unqualified_name_assignment_target_simple_identifier(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let name = self.node(node).as_unqualified_name_assignment_target_impl().name;
            self.simple_identifier_v1(name, NO_NODE)
        })
    }

    /// `CascadePropertyAssignmentTargetImpl.propertyAccess`.
    fn cascade_property_assignment_target_property_access(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let name = self.node(node).as_cascade_property_assignment_target_impl().name;
            let property_name = self.simple_identifier_v1(name, NO_NODE);
            self.property_access_v1(node, NO_NODE, NO_TOKEN, property_name)
        })
    }

    /// `CascadePropertyExtractionImpl.propertyAccess`.
    fn cascade_property_extraction_property_access(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let name = self.node(node).as_cascade_property_extraction_impl().name;
            let property_name = self.simple_identifier_v1(name, NO_NODE);
            self.property_access_v1(node, NO_NODE, NO_TOKEN, property_name)
        })
    }

    /// `ReceiverPropertyAssignmentTargetImpl.v1Projection`.
    fn receiver_property_assignment_target_v1_projection(self, node: NodeId) -> NodeId {
        let n = self.node(node).as_receiver_property_assignment_target_impl();
        let target = self.to_v1_named_receiver(n.receiver);
        let previous = self.store.v1_cached(node, slot::PROJECTION);
        let parent = self.parent2(node);
        // Increment targets already used PropertyAccess before parsed chains.
        // Assignments retain the identifier shape for a bare, non-record
        // receiver.
        let assignment = parent != NO_NODE
            && matches!(
                self.node(parent),
                AstNodeImpl::CompoundAssignmentImpl(_)
                    | AstNodeImpl::DirectAssignmentImpl(_)
                    | AstNodeImpl::IfNullAssignmentImpl(_)
            );
        let result;
        if assignment && self.uses_prefixed_identifier(n.operator_, n.name, target) {
            if previous != NO_NODE && matches!(self.node(previous), AstNodeImpl::PrefixedIdentifierImpl(_)) {
                return previous;
            }
            let identifier = self.simple_identifier_v1(n.name, NO_NODE);
            result = self.prefixed_identifier_v1(target, n.operator_, identifier, NO_NODE);
        } else {
            if previous != NO_NODE && matches!(self.node(previous), AstNodeImpl::PropertyAccessImpl(_)) {
                return previous;
            }
            // PropertyAccessImpl.v1ProjectionFromReceiverAssignmentTarget
            let property_name = self.simple_identifier_v1(n.name, NO_NODE);
            result = self.property_access_v1(node, NO_NODE, n.operator_, property_name);
        }
        if previous != NO_NODE {
            self.store.set_parent1(result, self.parent1_now(previous));
            self.store.set_parent1(previous, NO_NODE);
        }
        self.store.set_v1_cached(node, slot::PROJECTION, result);
        result
    }

    /// `ReceiverPropertyExtractionImpl.v1Projection`.
    fn receiver_property_extraction_v1_projection(self, node: NodeId) -> NodeId {
        let n = self.node(node).as_receiver_property_extraction_impl();
        let target = self.to_v1_named_receiver(n.receiver);
        let previous = self.store.v1_cached(node, slot::PROJECTION);
        let result;
        // V1 uses PropertyAccess for record receivers, including
        // record-bounded type parameters, even when the syntax would allow
        // PrefixedIdentifier.
        if self.uses_prefixed_identifier(n.operator_, n.name, target) {
            if previous != NO_NODE && matches!(self.node(previous), AstNodeImpl::PrefixedIdentifierImpl(_)) {
                return previous;
            }
            let identifier = self.simple_identifier_v1(n.name, NO_NODE);
            result = self.prefixed_identifier_v1(target, n.operator_, identifier, node);
        } else {
            if previous != NO_NODE && matches!(self.node(previous), AstNodeImpl::PropertyAccessImpl(_)) {
                return previous;
            }
            // PropertyAccessImpl.v1ProjectionFromReceiverExtraction
            let property_name = self.simple_identifier_v1(n.name, NO_NODE);
            result = self.property_access_v1(node, NO_NODE, n.operator_, property_name);
        }
        // Internal AST construction can attach a projection before the
        // receiver type is known. Preserve that attachment when resolution
        // changes its shape.
        if previous != NO_NODE {
            self.store.set_parent1(result, self.parent1_now(previous));
            self.store.set_parent1(previous, NO_NODE);
        }
        self.store.set_v1_cached(node, slot::PROJECTION, result);
        result
    }

    /// `BinaryOperatorInvocationImpl.binaryExpression` and those of
    /// `IfNullImpl`, `LogicalAndImpl` and `LogicalOrImpl`.
    fn binary_expression_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let id = self.store.add_v1(BinaryExpressionImpl { origin: node });
            let n = self.node(id).as_binary_expression_impl();
            self.become_parent_of1(id, n.left_operand(self, id));
            self.become_parent_of1(id, n.right_operand(self, id));
            id
        })
    }

    /// `LogicalNotImpl.prefixExpression` and
    /// `UnaryOperatorInvocationImpl.prefixExpression`.
    fn prefix_expression_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let id = self.store.add_v1(PrefixExpressionImpl { origin: node });
            let n = self.node(id).as_prefix_expression_impl();
            self.become_parent_of1(id, n.operand(self, id));
            id
        })
    }

    /// `NullAssertionExpressionImpl.postfixExpression`.
    fn postfix_expression_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let id = self.store.add_v1(PostfixExpressionImpl { origin: node });
            let n = self.node(id).as_postfix_expression_impl();
            self.become_parent_of1(id, n.operand(self, id));
            id
        })
    }

    /// `IncrementOrDecrementExpressionImpl.v1Projection`.
    fn increment_or_decrement_expression_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let position = self.node(node).as_increment_or_decrement_expression_impl().position;
            let id = match position {
                IncrementOrDecrementPosition::prefix => self.store.add_v1(PrefixExpressionImpl { origin: node }),
                IncrementOrDecrementPosition::postfix => self.store.add_v1(PostfixExpressionImpl { origin: node }),
            };
            let operand = match self.node(id) {
                AstNodeImpl::PrefixExpressionImpl(n) => n.operand(self, id),
                AstNodeImpl::PostfixExpressionImpl(n) => n.operand(self, id),
                _ => unreachable!(),
            };
            self.become_parent_of1(id, operand);
            id
        })
    }

    /// `IncrementOrDecrementExpressionImpl._legacyOperand`.
    fn increment_or_decrement_legacy_operand(self, node: NodeId) -> NodeId {
        let target = self.node(node).as_increment_or_decrement_expression_impl().target;
        self.assignment_v1_left_hand_side(target)
    }

    /// `IndexExpression2Impl.indexExpression`.
    fn index_expression2_index_expression(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let (question, left_bracket, right_bracket) = match self.node(node) {
                AstNodeImpl::CascadeIndexExpressionImpl(n) => (NO_TOKEN, n.left_bracket, n.right_bracket),
                AstNodeImpl::ReceiverIndexExpressionImpl(n) => (n.question, n.left_bracket, n.right_bracket),
                _ => unreachable!(),
            };
            self.index_expression_v1(node, question, left_bracket, right_bracket)
        })
    }

    /// `IndexAssignmentTargetImpl.indexExpression`.
    fn index_assignment_target_index_expression(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let (question, left_bracket, right_bracket) = match self.node(node) {
                AstNodeImpl::CascadeIndexAssignmentTargetImpl(n) => (NO_TOKEN, n.left_bracket, n.right_bracket),
                AstNodeImpl::ReceiverIndexAssignmentTargetImpl(n) => (n.question, n.left_bracket, n.right_bracket),
                _ => unreachable!(),
            };
            self.index_expression_v1(node, question, left_bracket, right_bracket)
        })
    }

    /// `IndexExpressionImpl.v1ProjectionFrom...(origin)`.
    fn index_expression_v1(self, origin: NodeId, question: TokenId, left_bracket: TokenId, right_bracket: TokenId) -> NodeId {
        let id = self.store.add_v1(IndexExpressionImpl {
            question,
            left_bracket,
            right_bracket,
            v1_projection_origin: origin,
        });
        let n = self.node(id).as_index_expression_impl();
        self.become_parent_of1(id, n.target(self, id));
        self.become_parent_of1(id, n.index(self, id));
        id
    }

    /// `SuperReferenceImpl.v1Projection`.
    fn super_reference_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let super_keyword = self.node(node).as_super_reference_impl().super_keyword;
            self.store.add_v1(SuperExpressionImpl {
                super_keyword,
                origin: node,
            })
        })
    }

    /// `CombinatorNameImpl.v1Projection`.
    fn combinator_name_v1_projection(self, node: NodeId) -> NodeId {
        let result = self.cached_or(node, slot::PROJECTION, || {
            let name = self.node(node).as_combinator_name_impl().name;
            self.simple_identifier_v1(name, NO_NODE)
        });
        let parent = self.parent2(node);
        if parent != NO_NODE {
            self.become_parent_of1(parent, result);
        }
        result
    }

    /// `CommentReferenceComponentImpl.v1Projection`.
    fn comment_reference_component_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let name = self.node(node).as_comment_reference_component_impl().name;
            self.simple_identifier_v1(name, NO_NODE)
        })
    }

    /// `BlockInstanceDeclarationBodyImpl.v1Projection`:
    /// `BlockClassBodyImpl.v1Projection(this)`.
    fn block_instance_declaration_body_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let origin = self.node(node).as_block_instance_declaration_body_impl();
            let members: Vec<NodeId> = origin.members.iter().map(|&m| self.to_v1_class_member(m)).collect();
            let id = self.store.add_v1(BlockClassBodyImpl {
                left_bracket: origin.left_bracket,
                members: members.clone(),
                right_bracket: origin.right_bracket,
                v1_projection_origin: node,
            });
            for member in members {
                self.become_parent_of1(id, member);
            }
            id
        })
    }

    /// `SemicolonInstanceDeclarationBodyImpl.v1Projection`.
    fn semicolon_instance_declaration_body_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let semicolon = self.node(node).as_semicolon_instance_declaration_body_impl().semicolon;
            self.store.add_v1(EmptyClassBodyImpl {
                semicolon,
                v1_projection_origin: node,
            })
        })
    }

    /// `EnumDeclarationBodyImpl.v1Projection`.
    fn enum_declaration_body_v1_projection(self, node: NodeId) -> NodeId {
        match self.node(node) {
            AstNodeImpl::BlockEnumDeclarationBodyImpl(_) => self.cached_or(node, slot::PROJECTION, || {
                let origin = self.node(node).as_block_enum_declaration_body_impl();
                let constants: Vec<NodeId> = origin
                    .constants
                    .iter()
                    .map(|&c| self.enum_constant_declaration2_v1_projection(c))
                    .collect();
                let members: Vec<NodeId> = origin.members.iter().map(|&m| self.to_v1_class_member(m)).collect();
                let id = self.store.add_v1(BlockEnumBodyImpl {
                    left_bracket: origin.left_bracket,
                    constants: constants.clone(),
                    semicolon: origin.members_separator,
                    members: members.clone(),
                    right_bracket: origin.right_bracket,
                    v1_projection_origin: node,
                });
                for constant in constants {
                    self.become_parent_of1(id, constant);
                }
                for member in members {
                    self.become_parent_of1(id, member);
                }
                id
            }),
            _ => self.cached_or(node, slot::PROJECTION, || {
                let semicolon = self.node(node).as_semicolon_enum_declaration_body_impl().semicolon;
                self.store.add_v1(EmptyEnumBodyImpl {
                    semicolon,
                    v1_projection_origin: node,
                })
            }),
        }
    }

    /// The `super(comment: origin.documentationComment, metadata:
    /// origin.metadata.toList())` of a projected declaration:
    /// `_initializeCommentAndAnnotations` in the V1 view.
    fn adopt_comment_and_metadata(self, id: NodeId, comment: NodeId, metadata: &[NodeId]) {
        self.become_parent_of1(id, comment);
        for &annotation in metadata {
            self.become_parent_of1(id, annotation);
        }
    }

    /// `ClassDeclaration2Impl.v1Projection`.
    fn class_declaration2_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let o = self.node(node).as_class_declaration2_impl();
            let id = self.store.add_v1(ClassDeclarationImpl {
                augment_keyword: o.augment_keyword,
                abstract_keyword: o.abstract_keyword,
                sealed_keyword: o.sealed_keyword,
                base_keyword: o.base_keyword,
                interface_keyword: o.interface_keyword,
                final_keyword: o.final_keyword,
                mixin_keyword: o.mixin_keyword,
                class_keyword: o.class_keyword,
                v1_projection_origin: node,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            });
            self.adopt_comment_and_metadata(id, o.documentation_comment, &o.metadata);
            self.become_parent_of1(id, o.name_part);
            self.become_parent_of1(id, o.extends_clause);
            self.become_parent_of1(id, o.with_clause);
            self.become_parent_of1(id, o.implements_clause);
            self.become_parent_of1(id, o.native_clause);
            self.declaration_v1_body(id, o.body);
            id
        })
    }

    /// `late final ClassBodyImpl _v1Body = _becomeParentOf1(
    /// V1Projection.toV1ClassBody(_v1ProjectionOrigin.body))`, and the enum
    /// declaration's, whose body is an enum body.
    fn declaration_v1_body(self, id: NodeId, body: NodeId) -> NodeId {
        self.cached_or(id, slot::BODY, || {
            let projected = match self.node(body) {
                AstNodeImpl::BlockEnumDeclarationBodyImpl(_) | AstNodeImpl::SemicolonEnumDeclarationBodyImpl(_) => {
                    self.enum_declaration_body_v1_projection(body)
                }
                _ => self.to_v1_class_body(body),
            };
            self.become_parent_of1(id, projected)
        })
    }

    /// `ClassTypeAlias2Impl.v1Projection`.
    fn class_type_alias2_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let o = self.node(node).as_class_type_alias2_impl();
            let semicolon = self.node(o.body).as_semicolon_instance_declaration_body_impl().semicolon;
            let id = self.store.add_v1(ClassTypeAliasImpl {
                abstract_keyword: o.abstract_keyword,
                sealed_keyword: o.sealed_keyword,
                base_keyword: o.base_keyword,
                interface_keyword: o.interface_keyword,
                final_keyword: o.final_keyword,
                mixin_keyword: o.mixin_keyword,
                equals: o.equals,
                v1_projection_origin: node,
                augment_keyword: o.augment_keyword,
                typedef_keyword: o.class_keyword,
                name: o.name,
                semicolon,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            });
            self.adopt_comment_and_metadata(id, o.documentation_comment, &o.metadata);
            self.become_parent_of1(id, o.type_parameters);
            self.become_parent_of1(id, o.superclass);
            self.become_parent_of1(id, o.with_clause);
            self.become_parent_of1(id, o.implements_clause);
            id
        })
    }

    /// `EnumDeclaration2Impl.v1Projection`.
    fn enum_declaration2_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let o = self.node(node).as_enum_declaration2_impl();
            let id = self.store.add_v1(EnumDeclarationImpl {
                augment_keyword: o.augment_keyword,
                enum_keyword: o.enum_keyword,
                v1_projection_origin: node,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            });
            self.adopt_comment_and_metadata(id, o.documentation_comment, &o.metadata);
            self.become_parent_of1(id, o.name_part);
            self.become_parent_of1(id, o.with_clause);
            self.become_parent_of1(id, o.implements_clause);
            self.declaration_v1_body(id, o.body);
            id
        })
    }

    /// `EnumConstantDeclaration2Impl.v1Projection`.
    fn enum_constant_declaration2_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let o = self.node(node).as_enum_constant_declaration2_impl();
            let id = self.store.add_v1(EnumConstantDeclarationImpl {
                augment_keyword: o.augment_keyword,
                name: o.name,
                v1_projection_origin: node,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            });
            self.adopt_comment_and_metadata(id, o.documentation_comment, &o.metadata);
            self.become_parent_of1(id, o.arguments);
            id
        })
    }

    /// `ExtensionDeclaration2Impl.v1Projection`.
    fn extension_declaration2_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let o = self.node(node).as_extension_declaration2_impl();
            let id = self.store.add_v1(ExtensionDeclarationImpl {
                augment_keyword: o.augment_keyword,
                extension_keyword: o.extension_keyword,
                type_keyword: o.type_keyword,
                name: o.name,
                v1_projection_origin: node,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            });
            self.adopt_comment_and_metadata(id, o.documentation_comment, &o.metadata);
            self.become_parent_of1(id, o.type_parameters);
            self.become_parent_of1(id, o.on_clause);
            self.declaration_v1_body(id, o.body);
            id
        })
    }

    /// `ExtensionTypeDeclaration2Impl.v1Projection`.
    fn extension_type_declaration2_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let o = self.node(node).as_extension_type_declaration2_impl();
            let id = self.store.add_v1(ExtensionTypeDeclarationImpl {
                augment_keyword: o.augment_keyword,
                extension_keyword: o.extension_keyword,
                type_keyword: o.type_keyword,
                v1_projection_origin: node,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            });
            self.adopt_comment_and_metadata(id, o.documentation_comment, &o.metadata);
            self.become_parent_of1(id, o.name_part);
            self.become_parent_of1(id, o.implements_clause);
            self.declaration_v1_body(id, o.body);
            id
        })
    }

    /// `MixinDeclaration2Impl.v1Projection`.
    fn mixin_declaration2_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let o = self.node(node).as_mixin_declaration2_impl();
            let id = self.store.add_v1(MixinDeclarationImpl {
                augment_keyword: o.augment_keyword,
                base_keyword: o.base_keyword,
                mixin_keyword: o.mixin_keyword,
                name: o.name,
                v1_projection_origin: node,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            });
            self.adopt_comment_and_metadata(id, o.documentation_comment, &o.metadata);
            self.become_parent_of1(id, o.type_parameters);
            self.become_parent_of1(id, o.on_clause);
            self.become_parent_of1(id, o.implements_clause);
            self.declaration_v1_body(id, o.body);
            id
        })
    }

    /// `FunctionTypeAlias2Impl.v1Projection`.
    fn function_type_alias2_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let o = self.node(node).as_function_type_alias2_impl();
            let id = self.store.add_v1(FunctionTypeAliasImpl {
                v1_projection_origin: node,
                augment_keyword: o.augment_keyword,
                typedef_keyword: o.typedef_keyword,
                name: o.name,
                semicolon: o.semicolon,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            });
            self.adopt_comment_and_metadata(id, o.documentation_comment, &o.metadata);
            self.become_parent_of1(id, o.return_type);
            self.become_parent_of1(id, o.type_parameters);
            self.become_parent_of1(id, o.parameters);
            id
        })
    }

    /// `GenericTypeAlias2Impl.v1Projection`.
    fn generic_type_alias2_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let o = self.node(node).as_generic_type_alias2_impl();
            let id = self.store.add_v1(GenericTypeAliasImpl {
                equals: o.equals,
                v1_projection_origin: node,
                augment_keyword: o.augment_keyword,
                typedef_keyword: o.typedef_keyword,
                name: o.name,
                semicolon: o.semicolon,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            });
            self.adopt_comment_and_metadata(id, o.documentation_comment, &o.metadata);
            self.become_parent_of1(id, o.type_parameters);
            self.become_parent_of1(id, o.type_);
            id
        })
    }

    /// `ConstructorDeclaration2Impl.v1Projection`.
    fn constructor_declaration2_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let o = self.node(node).as_constructor_declaration2_impl();
            let id = self.store.add_v1(ConstructorDeclarationImpl {
                augment_keyword: o.augment_keyword,
                external_keyword: o.external_keyword,
                factory_keyword: o.factory_keyword,
                new_keyword: o.new_keyword,
                period: o.period,
                name: o.name,
                separator: o.separator,
                initializers: o.initializers.clone(),
                v1_projection_origin: node,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            });
            self.adopt_comment_and_metadata(id, o.documentation_comment, &o.metadata);
            self.become_parent_of1(id, o.formal_parameters);
            for &initializer in &o.initializers {
                self.become_parent_of1(id, initializer);
            }
            if o.factory_redirection_target != NO_NODE {
                let constructor_name = self.constructor_reference2_constructor_name(o.factory_redirection_target);
                self.become_parent_of1(id, constructor_name);
            }
            self.become_parent_of1(id, o.body);
            id
        })
    }

    /// `PrimaryConstructorBody2Impl.v1Projection`.
    fn primary_constructor_body2_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let o = self.node(node).as_primary_constructor_body2_impl();
            let id = self.store.add_v1(PrimaryConstructorBodyImpl {
                augment_keyword: o.augment_keyword,
                this_keyword: o.this_keyword,
                colon: o.colon,
                initializers: o.initializers.clone(),
                v1_projection_origin: node,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            });
            self.adopt_comment_and_metadata(id, o.documentation_comment, &o.metadata);
            for &initializer in &o.initializers {
                self.become_parent_of1(id, initializer);
            }
            self.become_parent_of1(id, o.body);
            id
        })
    }

    /// `FieldsDeclarationImpl.v1Projection`.
    fn fields_declaration_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let o = self.node(node).as_fields_declaration_impl();
            let fields = self.variable_list_origin_v1_variable_list(node);
            let id = self.store.add_v1(FieldDeclarationImpl {
                augment_keyword: o.augment_keyword,
                external_keyword: o.external_keyword,
                static_keyword: o.static_keyword,
                abstract_keyword: o.abstract_keyword,
                covariant_keyword: o.covariant_keyword,
                fields,
                semicolon: o.semicolon,
                v1_projection_origin: node,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            });
            self.adopt_comment_and_metadata(id, o.documentation_comment, &o.metadata);
            self.become_parent_of1(id, fields);
            id
        })
    }

    /// `TopLevelVariablesDeclarationImpl.v1Projection`.
    fn top_level_variables_declaration_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let o = self.node(node).as_top_level_variables_declaration_impl();
            let variables = self.variable_list_origin_v1_variable_list(node);
            let id = self.store.add_v1(TopLevelVariableDeclarationImpl {
                augment_keyword: o.augment_keyword,
                external_keyword: o.external_keyword,
                abstract_keyword: o.abstract_keyword,
                variables,
                semicolon: o.semicolon,
                v1_projection_origin: node,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            });
            self.adopt_comment_and_metadata(id, o.documentation_comment, &o.metadata);
            self.become_parent_of1(id, variables);
            id
        })
    }

    /// `v1VariableList` of a `VariableDeclarationListV1OriginImpl`
    /// (`FieldsDeclarationImpl`, `TopLevelVariablesDeclarationImpl`,
    /// `LocalVariablesDeclarationImpl`).
    fn variable_list_origin_v1_variable_list(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::VARIABLE_LIST, || {
            let (late_keyword, keyword, type_, variables, comment, metadata) = match self.node(node) {
                AstNodeImpl::FieldsDeclarationImpl(o) => (
                    o.late_keyword,
                    o.const_final_or_var_keyword,
                    o.type_,
                    &o.fields,
                    NO_NODE,
                    &[][..],
                ),
                AstNodeImpl::TopLevelVariablesDeclarationImpl(o) => (
                    o.late_keyword,
                    o.const_final_or_var_keyword,
                    o.type_,
                    &o.variables,
                    NO_NODE,
                    &[][..],
                ),
                AstNodeImpl::LocalVariablesDeclarationImpl(o) => (
                    o.late_keyword,
                    o.const_final_or_var_keyword,
                    o.type_,
                    &o.variables,
                    o.documentation_comment,
                    &o.metadata[..],
                ),
                other => panic!("{} has no V1 variable list", other.runtime_type()),
            };
            // VariableDeclarationListImpl.v1Projection(origin, comment:,
            // metadata:). The variables are projected first, as the node
            // holds them; nothing they link depends on the list.
            let projected: Vec<NodeId> = variables
                .iter()
                .map(|&variable| self.variable_origin_v1_projection(variable))
                .collect();
            let id = self.store.add_v1(VariableDeclarationListImpl {
                late_keyword,
                keyword,
                variables: projected.clone(),
                v1_projection_origin: node,
                documentation_comment: comment,
                metadata: metadata.to_vec(),
            });
            self.adopt_comment_and_metadata(id, comment, metadata);
            self.become_parent_of1(id, type_);
            for &variable in &projected {
                self.become_parent_of1(id, variable);
            }
            id
        })
    }

    /// `LocalVariablesDeclarationImpl.v1VariableList`.
    fn local_variables_declaration_v1_variable_list(self, node: NodeId) -> NodeId {
        self.variable_list_origin_v1_variable_list(node)
    }

    /// `v1Projection` of a `VariableDeclarationV1OriginImpl` (`Field2Impl`,
    /// `LocalVariableImpl`, `TopLevelVariable2Impl`).
    fn variable_origin_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let (name, equals) = match self.node(node) {
                AstNodeImpl::Field2Impl(o) => (o.name, o.equals),
                AstNodeImpl::LocalVariableImpl(o) => (o.name, o.equals),
                AstNodeImpl::TopLevelVariable2Impl(o) => (o.name, o.equals),
                other => panic!("{} is not a variable", other.runtime_type()),
            };
            let id = self.store.add_v1(VariableDeclarationImpl {
                name,
                equals,
                v1_projection_origin: node,
                documentation_comment: NO_NODE,
                metadata: Vec::new(),
            });
            // Link the V1 initializer, so that it can find its V1 parent.
            self.node(id).as_variable_declaration_impl().initializer(self, id);
            id
        })
    }

    /// `LocalVariablesDeclarationStatementImpl.v1StatementProjection`.
    fn local_variables_declaration_statement_v1_statement_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::STATEMENT, || {
            let o = self.node(node).as_local_variables_declaration_statement_impl();
            let variables = self.variable_list_origin_v1_variable_list(o.declaration);
            let id = self.store.add_v1(VariableDeclarationStatementImpl {
                variables,
                semicolon: o.semicolon,
                v1_projection_origin: node,
            });
            self.become_parent_of1(id, variables);
            id
        })
    }

    /// `v1Projection` of a `FunctionDeclarationV1OriginImpl`
    /// (`TopLevelFunctionDeclarationImpl`, `TopLevelGetterDeclarationImpl`,
    /// `TopLevelSetterDeclarationImpl`, `LocalFunctionDeclarationImpl`).
    fn function_declaration_origin_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            use AstNodeImpl as N;
            // (augmentKeyword, externalKeyword, _v1PropertyKeyword, name,
            // returnType, comment, metadata)
            let (augment, external, property, name, return_type, comment, metadata) = match self.node(node) {
                N::TopLevelFunctionDeclarationImpl(o) => (
                    o.augment_keyword,
                    o.external_keyword,
                    NO_TOKEN,
                    o.name,
                    o.return_type,
                    o.documentation_comment,
                    &o.metadata[..],
                ),
                N::TopLevelGetterDeclarationImpl(o) => (
                    o.augment_keyword,
                    o.external_keyword,
                    o.get_keyword,
                    o.name,
                    o.return_type,
                    o.documentation_comment,
                    &o.metadata[..],
                ),
                N::TopLevelSetterDeclarationImpl(o) => (
                    o.augment_keyword,
                    o.external_keyword,
                    o.set_keyword,
                    o.name,
                    o.return_type,
                    o.documentation_comment,
                    &o.metadata[..],
                ),
                N::LocalFunctionDeclarationImpl(o) => (
                    NO_TOKEN,
                    NO_TOKEN,
                    NO_TOKEN,
                    o.name,
                    o.return_type,
                    o.documentation_comment,
                    &o.metadata[..],
                ),
                other => panic!("{} is not a function declaration", other.runtime_type()),
            };
            let function_expression = self.function_expression_v1_from_declaration(node);
            let id = self.store.add_v1(FunctionDeclarationImpl {
                augment_keyword: augment,
                external_keyword: external,
                property_keyword: property,
                name,
                function_expression,
                v1_projection_origin: node,
                documentation_comment: comment,
                metadata: metadata.to_vec(),
            });
            self.adopt_comment_and_metadata(id, comment, metadata);
            self.become_parent_of1(id, return_type);
            self.become_parent_of1(id, function_expression);
            id
        })
    }

    /// `(_v1TypeParameters, _v1Parameters, body)` of a function declaration
    /// origin.
    fn function_declaration_origin_parts(self, node: NodeId) -> (NodeId, NodeId, NodeId) {
        use AstNodeImpl as N;
        match self.node(node) {
            N::TopLevelFunctionDeclarationImpl(o) => (o.type_parameters, o.formal_parameters, o.body),
            N::TopLevelGetterDeclarationImpl(o) => (NO_NODE, o.recovery_formal_parameters, o.body),
            N::TopLevelSetterDeclarationImpl(o) => (NO_NODE, o.formal_parameters, o.body),
            N::LocalFunctionDeclarationImpl(o) => (o.type_parameters, o.formal_parameters, o.body),
            other => panic!("{} is not a function declaration", other.runtime_type()),
        }
    }

    /// `FunctionExpressionImpl.v1ProjectionFromDeclaration(origin)`.
    fn function_expression_v1_from_declaration(self, origin: NodeId) -> NodeId {
        let (type_parameters, parameters, body) = self.function_declaration_origin_parts(origin);
        let id = self.store.add_v1(FunctionExpressionImpl {
            type_parameters,
            parameters,
            body,
        });
        self.store.set_v1_cached(id, slot::ORIGIN, origin);
        // _attachV1Children()
        let n = self.node(id).as_function_expression_impl();
        self.become_parent_of1(id, n.type_parameters(self, id));
        self.become_parent_of1(id, n.parameters(self, id));
        self.become_parent_of1(id, n.body(self, id));
        id
    }

    /// `LocalFunctionDeclarationImpl.v1StatementProjection`.
    fn local_function_declaration_v1_statement_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::STATEMENT, || {
            let function_declaration = self.function_declaration_origin_v1_projection(node);
            let id = self.store.add_v1(FunctionDeclarationStatementImpl {
                function_declaration,
                v1_projection_origin: node,
            });
            self.become_parent_of1(id, function_declaration);
            id
        })
    }

    /// `v1Projection` of a `MethodDeclarationV1OriginImpl`
    /// (`MethodDeclaration2Impl`, `GetterDeclarationImpl`,
    /// `SetterDeclarationImpl`, `OperatorDeclarationImpl`).
    fn method_declaration_origin_v1_projection(self, node: NodeId) -> NodeId {
        self.cached_or(node, slot::PROJECTION, || {
            let p = self.method_origin_parts(node);
            let id = self.store.add_v1(MethodDeclarationImpl {
                augment_keyword: p.augment_keyword,
                external_keyword: p.external_keyword,
                modifier_keyword: p.static_keyword,
                property_keyword: p.property_keyword,
                operator_keyword: p.operator_keyword,
                name: p.name_token,
                v1_projection_origin: node,
                documentation_comment: p.documentation_comment,
                metadata: p.metadata.clone(),
            });
            self.adopt_comment_and_metadata(id, p.documentation_comment, &p.metadata);
            self.become_parent_of1(id, p.return_type);
            self.become_parent_of1(id, p.written_type_parameters);
            self.become_parent_of1(id, p.written_formal_parameters);
            self.become_parent_of1(id, p.body);
            id
        })
    }

    /// The members of a `MethodDeclarationV1OriginImpl` its projection
    /// reads.
    pub(crate) fn method_origin_parts(self, node: NodeId) -> MethodOriginParts {
        use AstNodeImpl as N;
        match self.node(node) {
            N::MethodDeclaration2Impl(o) => MethodOriginParts {
                augment_keyword: o.augment_keyword,
                external_keyword: o.external_keyword,
                static_keyword: o.static_keyword,
                property_keyword: NO_TOKEN,
                operator_keyword: NO_TOKEN,
                name_token: o.name,
                return_type: o.return_type,
                written_type_parameters: o.type_parameters,
                written_formal_parameters: o.formal_parameters,
                body: o.body,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            },
            N::GetterDeclarationImpl(o) => MethodOriginParts {
                augment_keyword: o.augment_keyword,
                external_keyword: o.external_keyword,
                static_keyword: o.static_keyword,
                property_keyword: o.get_keyword,
                operator_keyword: NO_TOKEN,
                name_token: o.name,
                return_type: o.return_type,
                written_type_parameters: NO_NODE,
                written_formal_parameters: o.recovery_formal_parameters,
                body: o.body,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            },
            N::SetterDeclarationImpl(o) => MethodOriginParts {
                augment_keyword: o.augment_keyword,
                external_keyword: o.external_keyword,
                static_keyword: o.static_keyword,
                property_keyword: o.set_keyword,
                operator_keyword: NO_TOKEN,
                name_token: o.name,
                return_type: o.return_type,
                written_type_parameters: NO_NODE,
                written_formal_parameters: o.formal_parameters,
                body: o.body,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            },
            N::OperatorDeclarationImpl(o) => MethodOriginParts {
                augment_keyword: o.augment_keyword,
                external_keyword: o.external_keyword,
                static_keyword: NO_TOKEN,
                property_keyword: NO_TOKEN,
                operator_keyword: o.operator_keyword,
                name_token: o.operator_,
                return_type: o.return_type,
                written_type_parameters: o.recovery_type_parameters,
                written_formal_parameters: o.formal_parameters,
                body: o.body,
                documentation_comment: o.documentation_comment,
                metadata: o.metadata.clone(),
            },
            other => panic!("{} is not a method declaration", other.runtime_type()),
        }
    }

    /// `AnnotationImpl._attachV1Children()`.
    pub fn annotation_attach_v1_children(self, node: NodeId) {
        let n = self.node(node).as_annotation_impl();
        n.name(self, node);
        n.type_arguments(self, node);
        n.constructor_name(self, node);
        n.arguments(self, node);
    }

    /// `AnnotationImpl._v1`: `_v1Children ??= _AnnotationV1Children._of(this)`.
    fn annotation_v1(self, node: NodeId) {
        if self.store.v1_cached(node, slot::ANNOTATION) != NO_NODE {
            return;
        }
        // _AnnotationV1Children._of(annotation)
        let expression = self.node(node).as_annotation_impl().expression;
        let end = self.end_token(expression);
        let token_after = |token: TokenId| -> TokenId {
            if token == end {
                NO_TOKEN
            } else {
                self.tokens.next(token)
            }
        };
        let name_head = self.simple_identifier_v1(self.begin_token(expression), NO_NODE);
        let mut name = name_head;
        let mut cursor = self.begin_token(expression);
        let period = token_after(cursor);
        if period != NO_TOKEN && self.tokens.type_(period).kind == PERIOD_TOKEN {
            let identifier = token_after(period);
            if identifier != NO_TOKEN {
                let name_tail = self.simple_identifier_v1(identifier, NO_NODE);
                name = self.prefixed_identifier_v1(name_head, period, name_tail, NO_NODE);
                cursor = identifier;
            }
        }
        let mut type_arguments = NO_NODE;
        let left_bracket = token_after(cursor);
        if left_bracket != NO_TOKEN && self.tokens.type_(left_bracket).kind == LT_TOKEN {
            type_arguments = self.annotation_find_node(expression, left_bracket, |n| {
                matches!(n, AstNodeImpl::TypeArgumentListImpl(_))
            });
            if type_arguments != NO_NODE {
                cursor = self.end_token(type_arguments);
            }
        }
        let mut period = NO_TOKEN;
        let mut constructor_name = NO_NODE;
        let period_token = token_after(cursor);
        if period_token != NO_TOKEN && self.tokens.type_(period_token).kind == PERIOD_TOKEN {
            let identifier = token_after(period_token);
            if identifier != NO_TOKEN {
                period = period_token;
                constructor_name = self.simple_identifier_v1(identifier, NO_NODE);
                cursor = identifier;
            }
        }
        let mut arguments = NO_NODE;
        let left_parenthesis = token_after(cursor);
        if left_parenthesis != NO_TOKEN && self.tokens.type_(left_parenthesis).kind == OPEN_PAREN_TOKEN {
            arguments = self.annotation_find_node(expression, left_parenthesis, |n| {
                matches!(n, AstNodeImpl::ArgumentListImpl(_))
            });
        }
        self.become_parent_of1(node, name);
        self.become_parent_of1(node, constructor_name);
        self.store.set_v1_cached(node, slot::ANNOTATION_NAME, name);
        self.store.set_v1_cached(node, slot::ANNOTATION_TYPE_ARGUMENTS, type_arguments);
        self.store.set_v1_cached(node, slot::ANNOTATION_PERIOD, period);
        self.store.set_v1_cached(node, slot::ANNOTATION_CONSTRUCTOR_NAME, constructor_name);
        self.store.set_v1_cached(node, slot::ANNOTATION_ARGUMENTS, arguments);
        self.store.set_v1_cached(node, slot::ANNOTATION, 1);
    }

    /// `_AnnotationV1Children._findNode<T>(root, beginToken)`.
    fn annotation_find_node(self, root: NodeId, begin_token: TokenId, is_t: fn(&AstNodeImpl) -> bool) -> NodeId {
        if is_t(self.node(root)) && self.begin_token(root) == begin_token {
            return root;
        }
        for entity in self.named_child_entities2(root) {
            use crate::src::dart::ast::ast_store::ChildValue;
            let children: Vec<NodeId> = match entity.value {
                ChildValue::Node(n) => vec![n],
                ChildValue::NodeList(l) => l.to_vec(),
                _ => Vec::new(),
            };
            for child in children {
                let result = self.annotation_find_node(child, begin_token, is_t);
                if result != NO_NODE {
                    return result;
                }
            }
        }
        NO_NODE
    }
}

/// The members of a `MethodDeclarationV1OriginImpl` its projection reads.
pub(crate) struct MethodOriginParts {
    pub augment_keyword: TokenId,
    pub external_keyword: TokenId,
    pub static_keyword: TokenId,
    pub property_keyword: TokenId,
    pub operator_keyword: TokenId,
    pub name_token: TokenId,
    pub return_type: NodeId,
    pub written_type_parameters: NodeId,
    pub written_formal_parameters: NodeId,
    pub body: NodeId,
    pub documentation_comment: NodeId,
    pub metadata: Vec<NodeId>,
}


// ---------------------------------------------------------------------------
// The getters of the V1 view written by hand upstream.
// ---------------------------------------------------------------------------

impl AnnotationImpl {
    pub fn name(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        ast.annotation_v1(id);
        ast.store.v1_cached(id, slot::ANNOTATION_NAME)
    }

    pub fn type_arguments(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        ast.annotation_v1(id);
        ast.become_parent_of1(id, ast.store.v1_cached(id, slot::ANNOTATION_TYPE_ARGUMENTS))
    }

    pub fn period(&self, ast: Ast<'_>, id: NodeId) -> TokenId {
        ast.annotation_v1(id);
        ast.store.v1_cached(id, slot::ANNOTATION_PERIOD)
    }

    pub fn constructor_name(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        ast.annotation_v1(id);
        ast.store.v1_cached(id, slot::ANNOTATION_CONSTRUCTOR_NAME)
    }

    pub fn arguments(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        ast.annotation_v1(id);
        ast.become_parent_of1(id, ast.store.v1_cached(id, slot::ANNOTATION_ARGUMENTS))
    }
}

impl AssignmentExpressionImpl {
    pub fn begin_token1_hand(&self, ast: Ast<'_>, id: NodeId) -> TokenId {
        ast.begin_token(self.left_hand_side(ast, id))
    }

    pub fn left_hand_side(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        ast.to_v1_expression(self.left_hand_side2(ast))
    }

    /// `leftHandSide2`: `_v1LeftHandSide(_v1ProjectionOrigin.target)`.
    pub fn left_hand_side2(&self, ast: Ast<'_>) -> NodeId {
        let target = match ast.node(self.v1_projection_origin) {
            AstNodeImpl::CompoundAssignmentImpl(o) => o.target,
            AstNodeImpl::DirectAssignmentImpl(o) => o.target,
            AstNodeImpl::IfNullAssignmentImpl(o) => o.target,
            _ => unreachable!(),
        };
        ast.assignment_v1_left_hand_side(target)
    }

    pub fn right_hand_side(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        let value = match ast.node(self.v1_projection_origin) {
            AstNodeImpl::CompoundAssignmentImpl(o) => o.value,
            AstNodeImpl::DirectAssignmentImpl(o) => o.value,
            AstNodeImpl::IfNullAssignmentImpl(o) => o.value,
            _ => unreachable!(),
        };
        ast.to_v1_expression(value)
    }
}

impl BinaryExpressionImpl {
    pub fn left_operand(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        let left = match ast.node(self.origin) {
            AstNodeImpl::BinaryOperatorInvocationImpl(o) => ast.to_v1_named_receiver(o.left_operand),
            AstNodeImpl::IfNullImpl(o) => o.left_operand,
            AstNodeImpl::LogicalAndImpl(o) => o.left_operand,
            AstNodeImpl::LogicalOrImpl(o) => o.left_operand,
            _ => panic!("StateError: Unexpected binary expression"),
        };
        ast.to_v1_expression(left)
    }

    pub fn operator_(&self, ast: Ast<'_>, _id: NodeId) -> TokenId {
        match ast.node(self.origin) {
            AstNodeImpl::BinaryOperatorInvocationImpl(o) => o.operator_,
            AstNodeImpl::IfNullImpl(o) => o.operator_,
            AstNodeImpl::LogicalAndImpl(o) => o.operator_,
            AstNodeImpl::LogicalOrImpl(o) => o.operator_,
            _ => panic!("StateError: Unexpected binary expression"),
        }
    }

    pub fn right_operand(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        let right = match ast.node(self.origin) {
            AstNodeImpl::BinaryOperatorInvocationImpl(o) => o.right_operand,
            AstNodeImpl::IfNullImpl(o) => o.right_operand,
            AstNodeImpl::LogicalAndImpl(o) => o.right_operand,
            AstNodeImpl::LogicalOrImpl(o) => o.right_operand,
            _ => panic!("StateError: Unexpected binary expression"),
        };
        ast.to_v1_expression(right)
    }
}

impl CascadeExpressionImpl {
    /// `cascadeSections`: each section's body, projected.
    pub fn cascade_sections(&self, ast: Ast<'_>, id: NodeId) -> Vec<NodeId> {
        self.sections
            .iter()
            .map(|&section| {
                let body = ast.node(section).as_cascade_section_impl().body;
                ast.become_parent_of1(id, ast.to_v1_expression(body))
            })
            .collect()
    }

    pub fn cascade_sections_element_containing_range(
        &self,
        ast: Ast<'_>,
        id: NodeId,
        range_offset: i32,
        range_end: i32,
    ) -> NodeId {
        let result = ast.element_containing_range(&self.sections, range_offset, range_end);
        if result != NO_NODE {
            let body = ast.node(result).as_cascade_section_impl().body;
            return ast.become_parent_of1(id, ast.to_v1_expression(body));
        }
        NO_NODE
    }
}

macro_rules! origin_getters {
    ($class:ident, $origin:ident, { $($getter:ident => $field:ident),* $(,)? }) => {
        impl $class {
            $(
                pub fn $getter(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
                    ast.node(self.v1_projection_origin).$origin().$field
                }
            )*
        }
    };
}

origin_getters!(ClassDeclarationImpl, as_class_declaration2_impl, {
    extends_clause => extends_clause,
    implements_clause => implements_clause,
    name_part => name_part,
    native_clause => native_clause,
    with_clause => with_clause,
});

impl ClassDeclarationImpl {
    pub fn body(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        let body = ast.node(self.v1_projection_origin).as_class_declaration2_impl().body;
        ast.declaration_v1_body(id, body)
    }
}

origin_getters!(ClassTypeAliasImpl, as_class_type_alias2_impl, {
    implements_clause => implements_clause,
    superclass => superclass,
    type_parameters => type_parameters,
    with_clause => with_clause,
});

origin_getters!(EnumDeclarationImpl, as_enum_declaration2_impl, {
    implements_clause => implements_clause,
    name_part => name_part,
    with_clause => with_clause,
});

impl EnumDeclarationImpl {
    pub fn body(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        let body = ast.node(self.v1_projection_origin).as_enum_declaration2_impl().body;
        ast.declaration_v1_body(id, body)
    }
}

origin_getters!(EnumConstantDeclarationImpl, as_enum_constant_declaration2_impl, {
    arguments => arguments,
});

origin_getters!(ExtensionDeclarationImpl, as_extension_declaration2_impl, {
    on_clause => on_clause,
    type_parameters => type_parameters,
});

impl ExtensionDeclarationImpl {
    pub fn body(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        let body = ast.node(self.v1_projection_origin).as_extension_declaration2_impl().body;
        ast.declaration_v1_body(id, body)
    }
}

origin_getters!(ExtensionTypeDeclarationImpl, as_extension_type_declaration2_impl, {
    implements_clause => implements_clause,
    name_part => name_part,
});

impl ExtensionTypeDeclarationImpl {
    pub fn body(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        let body = ast.node(self.v1_projection_origin).as_extension_type_declaration2_impl().body;
        ast.declaration_v1_body(id, body)
    }
}

origin_getters!(MixinDeclarationImpl, as_mixin_declaration2_impl, {
    implements_clause => implements_clause,
    on_clause => on_clause,
    type_parameters => type_parameters,
});

impl MixinDeclarationImpl {
    pub fn body(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        let body = ast.node(self.v1_projection_origin).as_mixin_declaration2_impl().body;
        ast.declaration_v1_body(id, body)
    }
}

origin_getters!(FunctionTypeAliasImpl, as_function_type_alias2_impl, {
    parameters => parameters,
    return_type => return_type,
    type_parameters => type_parameters,
});

origin_getters!(GenericTypeAliasImpl, as_generic_type_alias2_impl, {
    type_ => type_,
    type_parameters => type_parameters,
});

origin_getters!(PrimaryConstructorBodyImpl, as_primary_constructor_body2_impl, {
    body => body,
});

impl ConstructorDeclarationImpl {
    pub fn body(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        ast.node(self.v1_projection_origin).as_constructor_declaration2_impl().body
    }

    pub fn const_keyword(&self, ast: Ast<'_>, _id: NodeId) -> TokenId {
        ast.node(self.v1_projection_origin).as_constructor_declaration2_impl().const_keyword
    }

    pub fn first_token_after_comment_and_metadata_hand(&self, ast: Ast<'_>) -> TokenId {
        let o = ast.node(self.v1_projection_origin).as_constructor_declaration2_impl();
        for token in [
            self.augment_keyword,
            self.external_keyword,
            o.const_keyword,
            self.factory_keyword,
            self.new_keyword,
        ] {
            if token != NO_TOKEN {
                return token;
            }
        }
        // typeName
        if o.type_name != NO_TOKEN {
            return o.type_name;
        }
        if self.period != NO_TOKEN {
            return self.period;
        }
        if self.name != NO_TOKEN {
            return self.name;
        }
        ast.begin_token(o.formal_parameters)
    }

    pub fn parameters(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        ast.node(self.v1_projection_origin).as_constructor_declaration2_impl().formal_parameters
    }

    pub fn redirected_constructor(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        let target = ast
            .node(self.v1_projection_origin)
            .as_constructor_declaration2_impl()
            .factory_redirection_target;
        if target == NO_NODE {
            return NO_NODE;
        }
        ast.become_parent_of1(id, ast.constructor_reference2_constructor_name(target))
    }

    pub fn type_name(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        // late final SimpleIdentifierImpl? _v1TypeName
        let cached = ast.store.v1_cached(id, slot::TYPE_NAME);
        if cached != NO_NODE {
            return if cached == u32::MAX - 2 { NO_NODE } else { cached };
        }
        let type_name = ast.node(self.v1_projection_origin).as_constructor_declaration2_impl().type_name;
        let result = if type_name != NO_TOKEN {
            ast.become_parent_of1(id, ast.simple_identifier_v1(type_name, NO_NODE))
        } else {
            NO_NODE
        };
        ast.store.set_v1_cached(id, slot::TYPE_NAME, if result == NO_NODE { u32::MAX - 2 } else { result });
        result
    }
}

impl CommentReferenceImpl {
    pub fn expression(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        let cached = ast.store.v1_cached(id, slot::CHILD);
        if cached != NO_NODE {
            return cached;
        }
        let first = ast.comment_reference_component_v1_projection(self.components[0]);
        let mut result = first;
        if self.components.len() >= 2 {
            let period = ast.node(self.components[1]).as_comment_reference_component_impl().period;
            let identifier = ast.comment_reference_component_v1_projection(self.components[1]);
            result = ast.prefixed_identifier_v1(first, period, identifier, NO_NODE);
        }
        if self.components.len() == 3 {
            // PropertyAccessImpl.v1ProjectionFromCommentReference(this, result)
            let last = self.components[self.components.len() - 1];
            let operator = ast.node(last).as_comment_reference_component_impl().period;
            let property_name = ast.comment_reference_component_v1_projection(last);
            result = ast.property_access_v1(id, result, operator, property_name);
        }
        ast.become_parent_of1(id, result);
        ast.store.set_v1_cached(id, slot::CHILD, result);
        result
    }
}

impl CompilationUnitImpl {
    pub fn declarations(&self, ast: Ast<'_>, id: NodeId) -> Vec<NodeId> {
        ast.v1_projected_list(id, &self.declarations2, Ast::to_v1_compilation_unit_member)
    }

    pub fn visit_children1_hand<V: AstVisitor + ?Sized>(&self, ast: Ast<'_>, id: NodeId, visitor: &mut V) {
        if self.script_tag != NO_NODE {
            ast.accept(self.script_tag, visitor);
        }
        let declarations = self.declarations(ast, id);
        // _directivesAreBeforeDeclarations
        if self.directives.is_empty()
            || self.declarations2.is_empty()
            || ast.offset(self.directives[self.directives.len() - 1]) < ast.offset(self.declarations2[0])
        {
            for &directive in &self.directives {
                ast.accept(directive, visitor);
            }
            for declaration in declarations {
                ast.accept(declaration, visitor);
            }
        } else {
            for child in ast.sorted_by_offset(&[&self.directives[..], &declarations[..]]) {
                ast.accept(child, visitor);
            }
        }
    }

    pub fn child_containing_range1_hand(&self, ast: Ast<'_>, id: NodeId, range_offset: i32, range_end: i32) -> NodeId {
        if self.script_tag != NO_NODE && ast.contains_offset(self.script_tag, range_offset, range_end) {
            return self.script_tag;
        }
        let result = ast.element_containing_range(&self.directives, range_offset, range_end);
        if result != NO_NODE {
            return result;
        }
        ast.v1_projected_element_containing_range(
            id,
            &self.declarations2,
            Ast::to_v1_compilation_unit_member,
            range_offset,
            range_end,
        )
    }

    pub fn child_containing_range2_hand(&self, ast: Ast<'_>, _id: NodeId, range_offset: i32, range_end: i32) -> NodeId {
        if self.script_tag != NO_NODE && ast.contains_offset(self.script_tag, range_offset, range_end) {
            return self.script_tag;
        }
        let result = ast.element_containing_range(&self.directives, range_offset, range_end);
        if result != NO_NODE {
            return result;
        }
        ast.element_containing_range(&self.declarations2, range_offset, range_end)
    }
}

impl ConstructorFieldInitializerImpl {
    pub fn field_name(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        let cached = ast.store.v1_cached(id, slot::CHILD);
        if cached != NO_NODE {
            return cached;
        }
        let result = ast.become_parent_of1(id, ast.simple_identifier_v1(self.field_name2, NO_NODE));
        ast.store.set_v1_cached(id, slot::CHILD, result);
        result
    }
}

impl ConstructorNameImpl {
    pub fn begin_token1_hand(&self, ast: Ast<'_>, id: NodeId) -> TokenId {
        ast.begin_token(self.type_(ast, id))
    }

    pub fn end_token1_hand(&self, ast: Ast<'_>, id: NodeId) -> TokenId {
        let name = self.name(ast, id);
        if name != NO_NODE {
            return ast.end_token(name);
        }
        let period = self.period(ast, id);
        if period != NO_TOKEN {
            return period;
        }
        ast.end_token(self.type_(ast, id))
    }

    /// The `selector` of `_origin` (a `ConstructorReference2Impl`).
    fn selector(&self, ast: Ast<'_>) -> NodeId {
        if self.origin == NO_NODE {
            return NO_NODE;
        }
        ast.node(self.origin).as_constructor_reference2_impl().selector
    }

    pub fn name(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        let selector = self.selector(ast);
        let result = if selector != NO_NODE {
            ast.constructor_selector_name(selector)
        } else {
            self.parsed_name
        };
        if result != NO_NODE {
            ast.become_parent_of1(id, result);
        }
        result
    }

    pub fn period(&self, ast: Ast<'_>, _id: NodeId) -> TokenId {
        let selector = self.selector(ast);
        if selector != NO_NODE {
            return ast.node(selector).as_constructor_selector_impl().period;
        }
        self.parsed_period
    }

    pub fn type_(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        let result = if self.origin != NO_NODE {
            let type_reference = ast.node(self.origin).as_constructor_reference2_impl().type_reference;
            ast.constructor_type_reference_named_type(type_reference)
        } else {
            self.parsed_type
        };
        ast.become_parent_of1(id, result)
    }
}

impl<'a> Ast<'a> {
    /// `ConstructorSelectorImpl.name`.
    pub fn constructor_selector_name(self, node: NodeId) -> NodeId {
        let cached = self.store.v1_cached(node, slot::CHILD);
        if cached != NO_NODE {
            return cached;
        }
        let name2 = self.node(node).as_constructor_selector_impl().name2;
        let result = self.become_parent_of1(node, self.simple_identifier_v1(name2, NO_NODE));
        self.store.set_v1_cached(node, slot::CHILD, result);
        result
    }
}

impl ConstructorSelectorImpl {
    pub fn name(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        ast.constructor_selector_name(id)
    }
}

impl ConstructorReferenceImpl {
    pub fn constructor_name(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        let _ = (ast, self.origin);
        unreachable!("ConstructorTearOffImpl is only made by resolution")
    }
}

impl DotShorthandConstructorInvocationImpl {
    pub fn argument_list(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        ast.node(self.v1_projection_origin)
            .as_dot_shorthand_constructor_invocation2_impl()
            .argument_list
    }

    pub fn begin_token1_hand(&self, ast: Ast<'_>, id: NodeId) -> TokenId {
        let const_keyword = self.const_keyword(ast, id);
        if const_keyword != NO_TOKEN {
            return const_keyword;
        }
        self.period
    }

    pub fn const_keyword(&self, ast: Ast<'_>, _id: NodeId) -> TokenId {
        ast.node(self.v1_projection_origin)
            .as_dot_shorthand_constructor_invocation2_impl()
            .const_keyword
    }

    pub fn constructor_name(&self, _ast: Ast<'_>, _id: NodeId) -> NodeId {
        self.constructor_name
    }

    pub fn type_arguments(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        ast.node(self.v1_projection_origin)
            .as_dot_shorthand_constructor_invocation2_impl()
            .type_arguments
    }
}

impl DotShorthandInvocationImpl {
    pub fn argument_list(&self, _ast: Ast<'_>, _id: NodeId) -> NodeId {
        // `_v1ProjectionOrigin?.argumentList ?? super.argumentList`: the
        // origin's is the one the constructor stored.
        self.argument_list
    }

    pub fn member_name(&self, _ast: Ast<'_>, _id: NodeId) -> NodeId {
        self.member_name
    }

    pub fn type_arguments(&self, _ast: Ast<'_>, _id: NodeId) -> NodeId {
        self.type_arguments
    }
}

impl DotShorthandPropertyAccessImpl {
    pub fn property_name(&self, _ast: Ast<'_>, _id: NodeId) -> NodeId {
        self.property_name
    }
}

impl ExtensionOverrideImpl {
    pub fn argument_list(&self, _ast: Ast<'_>, _id: NodeId) -> NodeId {
        unreachable!("ExtensionOverride2Impl is not built by parsing")
    }

    pub fn begin_token1_hand(&self, _ast: Ast<'_>, _id: NodeId) -> TokenId {
        unreachable!("ExtensionOverride2Impl is not built by parsing")
    }

    pub fn import_prefix(&self, _ast: Ast<'_>, _id: NodeId) -> NodeId {
        unreachable!("ExtensionOverride2Impl is not built by parsing")
    }

    pub fn name(&self, _ast: Ast<'_>, _id: NodeId) -> TokenId {
        unreachable!("ExtensionOverride2Impl is not built by parsing")
    }

    pub fn type_arguments(&self, _ast: Ast<'_>, _id: NodeId) -> NodeId {
        unreachable!("ExtensionOverride2Impl is not built by parsing")
    }
}

impl FieldFormalParameterImpl {
    pub fn function_typed_suffix(&self, _ast: Ast<'_>, _id: NodeId) -> NodeId {
        self.function_typed_suffix
    }

    pub fn name(&self, _ast: Ast<'_>, _id: NodeId) -> TokenId {
        self.name
    }
}

impl SuperFormalParameterImpl {
    pub fn function_typed_suffix(&self, _ast: Ast<'_>, _id: NodeId) -> NodeId {
        self.function_typed_suffix
    }

    pub fn name(&self, _ast: Ast<'_>, _id: NodeId) -> TokenId {
        self.name
    }
}

impl RegularFormalParameterImpl {
    pub fn function_typed_suffix(&self, _ast: Ast<'_>, _id: NodeId) -> NodeId {
        self.function_typed_suffix
    }
}

impl ForEachPartsWithIdentifierImpl {
    pub fn identifier(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        let cached = ast.store.v1_cached(id, slot::CHILD);
        if cached != NO_NODE {
            return cached;
        }
        let name = ast.node(self.target).as_unqualified_name_assignment_target_impl().name;
        let result = ast.become_parent_of1(id, ast.simple_identifier_v1(name, NO_NODE));
        ast.store.set_v1_cached(id, slot::CHILD, result);
        result
    }
}

impl FormalParameterListImpl {
    pub fn child_entities1_hand(&self, ast: Ast<'_>, _id: NodeId, entities: &mut ChildEntities1) {
        entities.add_token("leftParenthesis", self.left_parenthesis);
        for &parameter in &self.required_positional_formal_parameters {
            entities.add_node("parameter", parameter);
        }
        if self.delimited_formal_parameters != NO_NODE {
            let delimited = ast
                .node(self.delimited_formal_parameters)
                .as_delimited_formal_parameters_impl();
            entities.add_token("leftDelimiter", delimited.left_delimiter);
            for &parameter in &delimited.formal_parameters {
                entities.add_node("parameter", parameter);
            }
            entities.add_token("rightDelimiter", delimited.right_delimiter);
        }
        entities.add_token("rightParenthesis", self.right_parenthesis);
    }

    pub fn parameters(&self, ast: Ast<'_>, id: NodeId) -> Vec<NodeId> {
        ast.store.all_formal_parameters(id)
    }

    pub fn parameters_element_containing_range(
        &self,
        ast: Ast<'_>,
        _id: NodeId,
        range_offset: i32,
        range_end: i32,
    ) -> NodeId {
        let result = ast.element_containing_range(&self.required_positional_formal_parameters, range_offset, range_end);
        if result != NO_NODE {
            return result;
        }
        if self.delimited_formal_parameters == NO_NODE {
            return NO_NODE;
        }
        let delimited = ast
            .node(self.delimited_formal_parameters)
            .as_delimited_formal_parameters_impl();
        ast.element_containing_range(&delimited.formal_parameters, range_offset, range_end)
    }
}

impl FunctionDeclarationImpl {
    pub fn first_token_after_comment_and_metadata_hand(&self, ast: Ast<'_>) -> TokenId {
        if self.augment_keyword != NO_TOKEN {
            return self.augment_keyword;
        }
        if self.external_keyword != NO_TOKEN {
            return self.external_keyword;
        }
        let return_type = self.return_type(ast, NO_NODE);
        if return_type != NO_NODE {
            return ast.begin_token(return_type);
        }
        if self.property_keyword != NO_TOKEN {
            return self.property_keyword;
        }
        self.name
    }

    pub fn return_type(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        use AstNodeImpl as N;
        match ast.node(self.v1_projection_origin) {
            N::TopLevelFunctionDeclarationImpl(o) => o.return_type,
            N::TopLevelGetterDeclarationImpl(o) => o.return_type,
            N::TopLevelSetterDeclarationImpl(o) => o.return_type,
            N::LocalFunctionDeclarationImpl(o) => o.return_type,
            _ => unreachable!(),
        }
    }
}

impl FunctionExpressionImpl {
    /// The origin of a projection object, or `NO_NODE`.
    fn v1_origin(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        if id >= V1_BASE {
            ast.store.v1_cached(id, slot::ORIGIN)
        } else {
            NO_NODE
        }
    }

    pub fn body(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        let origin = self.v1_origin(ast, id);
        if origin != NO_NODE {
            return ast.function_declaration_origin_parts(origin).2;
        }
        self.body
    }

    pub fn parameters(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        let origin = self.v1_origin(ast, id);
        if origin != NO_NODE {
            return ast.function_declaration_origin_parts(origin).1;
        }
        self.parameters
    }

    pub fn type_parameters(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        let origin = self.v1_origin(ast, id);
        if origin != NO_NODE {
            return ast.function_declaration_origin_parts(origin).0;
        }
        self.type_parameters
    }
}

impl FunctionExpressionInvocationImpl {
    pub fn argument_list(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        ast.node(self.origin).as_call_invocation_impl().argument_list
    }

    pub fn function(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        ast.to_v1_named_receiver(ast.node(self.origin).as_call_invocation_impl().receiver)
    }

    pub fn type_arguments(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        ast.node(self.origin).as_call_invocation_impl().type_arguments
    }
}

impl FunctionReferenceImpl {
    pub fn begin_token1_hand(&self, ast: Ast<'_>, id: NodeId) -> TokenId {
        ast.begin_token(self.function(ast, id))
    }

    pub fn end_token1_hand(&self, ast: Ast<'_>, _id: NodeId) -> TokenId {
        if self.type_arguments != NO_NODE {
            return ast.end_token(self.type_arguments);
        }
        ast.end_token(self.function2)
    }

    pub fn function(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        ast.become_parent_of1(id, ast.to_v1_expression(self.function2))
    }
}

impl ImplicitCallReferenceImpl {
    pub fn begin_token1_hand(&self, _ast: Ast<'_>, _id: NodeId) -> TokenId {
        unreachable!("ImplicitCallReferenceImpl is only made by resolution")
    }

    pub fn end_token1_hand(&self, _ast: Ast<'_>, _id: NodeId) -> TokenId {
        unreachable!("ImplicitCallReferenceImpl is only made by resolution")
    }
}

impl ImportDirectiveImpl {
    pub fn prefix(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        // _prefix ??= switch (prefixName) {...}: a null result is not
        // cached.
        let cached = ast.store.v1_cached(id, slot::CHILD);
        if cached != NO_NODE {
            return cached;
        }
        if self.prefix_name == NO_TOKEN {
            return NO_NODE;
        }
        let result = ast.become_parent_of1(id, ast.simple_identifier_v1(self.prefix_name, NO_NODE));
        ast.store.set_v1_cached(id, slot::CHILD, result);
        result
    }
}

impl IndexExpressionImpl {
    pub fn begin_token1_hand(&self, ast: Ast<'_>, id: NodeId) -> TokenId {
        let target = self.target(ast, id);
        if target != NO_NODE {
            return ast.begin_token(target);
        }
        let period = self.period(ast, id);
        if period != NO_TOKEN {
            return period;
        }
        self.left_bracket
    }

    pub fn index(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        // index => toV1Expression(index2), index2 => toV1Expression(origin.index)
        let index = match ast.node(self.v1_projection_origin) {
            AstNodeImpl::CascadeIndexAssignmentTargetImpl(o) => o.index,
            AstNodeImpl::ReceiverIndexAssignmentTargetImpl(o) => o.index,
            AstNodeImpl::CascadeIndexExpressionImpl(o) => o.index,
            AstNodeImpl::ReceiverIndexExpressionImpl(o) => o.index,
            _ => panic!("StateError: Unexpected index projection origin."),
        };
        ast.to_v1_expression(ast.to_v1_expression(index))
    }

    pub fn period(&self, ast: Ast<'_>, _id: NodeId) -> TokenId {
        match ast.node(self.v1_projection_origin) {
            AstNodeImpl::CascadeIndexAssignmentTargetImpl(_) | AstNodeImpl::CascadeIndexExpressionImpl(_) => {
                let section = ast.this_or_ancestor_matching2(ast.parent2(self.v1_projection_origin), |a| {
                    matches!(ast.node(a), AstNodeImpl::CascadeSectionImpl(_))
                });
                if section == NO_NODE {
                    panic!("StateError: Cascade index operation has no CascadeSection.");
                }
                ast.node(section).as_cascade_section_impl().operator_
            }
            _ => NO_TOKEN,
        }
    }

    pub fn target(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        let target2 = match ast.node(self.v1_projection_origin) {
            AstNodeImpl::ReceiverIndexAssignmentTargetImpl(o) => ast.to_v1_named_receiver(o.receiver),
            AstNodeImpl::ReceiverIndexExpressionImpl(o) => ast.to_v1_named_receiver(o.receiver),
            _ => NO_NODE,
        };
        if target2 == NO_NODE {
            return NO_NODE;
        }
        ast.to_v1_expression(target2)
    }
}

impl InstanceCreationExpressionImpl {
    pub fn argument_list(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        if self.origin != NO_NODE {
            return ast.node(self.origin).as_constructor_invocation_impl().argument_list;
        }
        self.parsed_argument_list
    }

    pub fn begin_token1_hand(&self, ast: Ast<'_>, id: NodeId) -> TokenId {
        if self.origin != NO_NODE {
            return ast.begin_token(self.origin);
        }
        ast.begin_token(self.constructor_name(ast, id))
    }

    pub fn constructor_name(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        if self.origin != NO_NODE {
            let reference = ast.node(self.origin).as_constructor_invocation_impl().constructor_reference;
            return ast.constructor_reference2_constructor_name(reference);
        }
        self.parsed_constructor_name
    }

    pub fn end_token1_hand(&self, ast: Ast<'_>, id: NodeId) -> TokenId {
        ast.end_token(self.argument_list(ast, id))
    }

    pub fn keyword(&self, ast: Ast<'_>, _id: NodeId) -> TokenId {
        if self.origin != NO_NODE {
            return ast.node(self.origin).as_constructor_invocation_impl().keyword;
        }
        NO_TOKEN
    }

    pub fn type_arguments(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        if self.origin != NO_NODE {
            return ast.node(self.origin).as_constructor_invocation_impl().type_arguments;
        }
        NO_NODE
    }
}

impl MethodDeclarationImpl {
    pub fn body(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        ast.method_origin_parts(self.v1_projection_origin).body
    }

    pub fn first_token_after_comment_and_metadata_hand(&self, ast: Ast<'_>) -> TokenId {
        for token in [self.augment_keyword, self.external_keyword, self.modifier_keyword] {
            if token != NO_TOKEN {
                return token;
            }
        }
        let return_type = self.return_type(ast, NO_NODE);
        if return_type != NO_NODE {
            return ast.begin_token(return_type);
        }
        for token in [self.property_keyword, self.operator_keyword] {
            if token != NO_TOKEN {
                return token;
            }
        }
        self.name
    }

    pub fn parameters(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        ast.method_origin_parts(self.v1_projection_origin).written_formal_parameters
    }

    pub fn return_type(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        ast.method_origin_parts(self.v1_projection_origin).return_type
    }

    pub fn type_parameters(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        ast.method_origin_parts(self.v1_projection_origin).written_type_parameters
    }
}

impl MethodInvocationImpl {
    pub fn argument_list(&self, _ast: Ast<'_>, _id: NodeId) -> NodeId {
        // `_v1ProjectionOrigin?.argumentList ?? super.argumentList`: the
        // projections made by parsing have no origin.
        self.argument_list
    }

    pub fn method_name(&self, _ast: Ast<'_>, _id: NodeId) -> NodeId {
        self.method_name
    }

    pub fn operator_(&self, _ast: Ast<'_>, _id: NodeId) -> TokenId {
        self.operator_
    }

    pub fn type_arguments(&self, _ast: Ast<'_>, _id: NodeId) -> NodeId {
        self.type_arguments
    }

    pub fn begin_token1_hand(&self, ast: Ast<'_>, id: NodeId) -> TokenId {
        if self.target2 != NO_NODE {
            return ast.begin_token(self.target2);
        }
        let operator = self.operator_(ast, id);
        if operator != NO_TOKEN {
            return operator;
        }
        ast.begin_token(self.method_name)
    }
}

impl NamedTypeImpl {
    pub fn import_prefix(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        if ast.api(id) != AstNodeApi::v1 {
            return self.import_prefix;
        }
        let origin = ast.store.v1_cached(id, slot::ORIGIN);
        let result = if origin != NO_NODE {
            ast.node(origin).as_constructor_type_reference_impl().import_prefix
        } else {
            self.import_prefix
        };
        ast.become_parent_of1(id, result)
    }

    pub fn type_arguments(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        if ast.api(id) != AstNodeApi::v1 {
            return self.type_arguments;
        }
        let origin = ast.store.v1_cached(id, slot::ORIGIN);
        let result = if origin != NO_NODE {
            ast.node(origin).as_constructor_type_reference_impl().type_arguments
        } else {
            self.type_arguments
        };
        ast.become_parent_of1(id, result)
    }
}

impl PostfixExpressionImpl {
    pub fn operand(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        match ast.node(self.origin) {
            AstNodeImpl::IncrementOrDecrementExpressionImpl(_) => ast.increment_or_decrement_legacy_operand(self.origin),
            AstNodeImpl::NullAssertionExpressionImpl(o) => ast.to_v1_expression(o.operand),
            _ => panic!("StateError: Unexpected PostfixExpression origin"),
        }
    }

    pub fn operator_(&self, ast: Ast<'_>, _id: NodeId) -> TokenId {
        match ast.node(self.origin) {
            AstNodeImpl::IncrementOrDecrementExpressionImpl(o) => o.operator_,
            AstNodeImpl::NullAssertionExpressionImpl(o) => o.operator_,
            _ => panic!("StateError: Unexpected PostfixExpression origin"),
        }
    }
}

impl PrefixExpressionImpl {
    pub fn operand(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        match ast.node(self.origin) {
            AstNodeImpl::IncrementOrDecrementExpressionImpl(_) => ast.increment_or_decrement_legacy_operand(self.origin),
            AstNodeImpl::LogicalNotImpl(o) => ast.to_v1_expression(o.operand),
            AstNodeImpl::UnaryOperatorInvocationImpl(o) => ast.to_v1_named_receiver(o.operand),
            _ => panic!("StateError: Unexpected PrefixExpression origin"),
        }
    }

    pub fn operator_(&self, ast: Ast<'_>, _id: NodeId) -> TokenId {
        match ast.node(self.origin) {
            AstNodeImpl::IncrementOrDecrementExpressionImpl(o) => o.operator_,
            AstNodeImpl::LogicalNotImpl(o) => o.operator_,
            AstNodeImpl::UnaryOperatorInvocationImpl(o) => o.operator_,
            _ => panic!("StateError: Unexpected PrefixExpression origin"),
        }
    }
}

impl PrefixedIdentifierImpl {
    pub fn identifier(&self, _ast: Ast<'_>, _id: NodeId) -> NodeId {
        self.identifier
    }
}

impl PropertyAccessImpl {
    pub fn begin_token1_hand(&self, ast: Ast<'_>, id: NodeId) -> TokenId {
        let target = self.target(ast, id);
        if target != NO_NODE {
            return ast.begin_token(target);
        }
        self.operator_(ast, id)
    }

    pub fn operator_(&self, ast: Ast<'_>, _id: NodeId) -> TokenId {
        match ast.node(self.v1_projection_origin) {
            AstNodeImpl::CascadePropertyAssignmentTargetImpl(_) | AstNodeImpl::CascadePropertyExtractionImpl(_) => {
                let section = ast.this_or_ancestor_matching2(ast.parent2(self.v1_projection_origin), |a| {
                    matches!(ast.node(a), AstNodeImpl::CascadeSectionImpl(_))
                });
                if section == NO_NODE {
                    panic!("StateError: Cascade property operation has no CascadeSection.");
                }
                ast.node(section).as_cascade_section_impl().operator_
            }
            _ => self.operator_,
        }
    }

    pub fn property_name(&self, _ast: Ast<'_>, _id: NodeId) -> NodeId {
        self.property_name
    }

    /// `target2`.
    pub fn target2(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        match ast.node(self.v1_projection_origin) {
            AstNodeImpl::ReceiverPropertyAssignmentTargetImpl(o) => ast.to_v1_named_receiver(o.receiver),
            AstNodeImpl::ReceiverPropertyExtractionImpl(o) => ast.to_v1_named_receiver(o.receiver),
            _ => self.target2,
        }
    }

    pub fn target(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        let target2 = self.target2(ast, id);
        if target2 == NO_NODE {
            return NO_NODE;
        }
        ast.to_v1_expression(target2)
    }
}

impl RedirectingConstructorInvocationImpl {
    pub fn constructor_name(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        if self.constructor_selector == NO_NODE {
            return NO_NODE;
        }
        ast.become_parent_of1(id, ast.constructor_selector_name(self.constructor_selector))
    }

    pub fn period(&self, ast: Ast<'_>, _id: NodeId) -> TokenId {
        if self.constructor_selector == NO_NODE {
            return NO_TOKEN;
        }
        ast.node(self.constructor_selector).as_constructor_selector_impl().period
    }
}

impl SuperConstructorInvocationImpl {
    pub fn constructor_name(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        if self.constructor_selector == NO_NODE {
            return NO_NODE;
        }
        ast.become_parent_of1(id, ast.constructor_selector_name(self.constructor_selector))
    }

    pub fn period(&self, ast: Ast<'_>, _id: NodeId) -> TokenId {
        if self.constructor_selector == NO_NODE {
            return NO_TOKEN;
        }
        ast.node(self.constructor_selector).as_constructor_selector_impl().period
    }
}

macro_rules! switch_member_statements {
    ($class:ident) => {
        impl $class {
            pub fn statements(&self, ast: Ast<'_>, id: NodeId) -> Vec<NodeId> {
                ast.v1_projected_list(id, &self.statements2, Ast::to_v1_statement)
            }

            pub fn statements_element_containing_range(
                &self,
                ast: Ast<'_>,
                id: NodeId,
                range_offset: i32,
                range_end: i32,
            ) -> NodeId {
                ast.v1_projected_element_containing_range(
                    id,
                    &self.statements2,
                    Ast::to_v1_statement,
                    range_offset,
                    range_end,
                )
            }
        }
    };
}

switch_member_statements!(SwitchCaseImpl);
switch_member_statements!(SwitchDefaultImpl);
switch_member_statements!(SwitchPatternCaseImpl);

impl VariableDeclarationImpl {
    pub fn initializer(&self, ast: Ast<'_>, id: NodeId) -> NodeId {
        let initializer2 = match ast.node(self.v1_projection_origin) {
            AstNodeImpl::Field2Impl(o) => o.initializer,
            AstNodeImpl::LocalVariableImpl(o) => o.initializer,
            AstNodeImpl::TopLevelVariable2Impl(o) => o.initializer,
            _ => unreachable!(),
        };
        if initializer2 == NO_NODE {
            return NO_NODE;
        }
        ast.become_parent_of1(id, ast.to_v1_expression(initializer2))
    }
}

impl VariableDeclarationListImpl {
    pub fn type_(&self, ast: Ast<'_>, _id: NodeId) -> NodeId {
        match ast.node(self.v1_projection_origin) {
            AstNodeImpl::FieldsDeclarationImpl(o) => o.type_,
            AstNodeImpl::TopLevelVariablesDeclarationImpl(o) => o.type_,
            AstNodeImpl::LocalVariablesDeclarationImpl(o) => o.type_,
            _ => unreachable!(),
        }
    }

    pub fn end_token1_hand(&self, ast: Ast<'_>, id: NodeId) -> TokenId {
        let result = ast.store.node_list_end_token(&self.variables, ast.tokens);
        if result != NO_TOKEN {
            return result;
        }
        let type_ = self.type_(ast, id);
        if type_ != NO_NODE {
            return ast.end_token(type_);
        }
        if self.keyword != NO_TOKEN {
            return self.keyword;
        }
        if self.late_keyword != NO_TOKEN {
            return self.late_keyword;
        }
        panic!("StateError: Expected at least one non-null");
    }

    pub fn first_token_after_comment_and_metadata_hand(&self, ast: Ast<'_>) -> TokenId {
        if self.late_keyword != NO_TOKEN {
            return self.late_keyword;
        }
        if self.keyword != NO_TOKEN {
            return self.keyword;
        }
        let type_ = self.type_(ast, NO_NODE);
        if type_ != NO_NODE {
            return ast.begin_token(type_);
        }
        let result = ast.store.node_list_begin_token(&self.variables, ast.tokens);
        if result != NO_TOKEN {
            return result;
        }
        panic!("StateError: Expected at least one non-null");
    }
}
