// Port of lib/src/summary2/type_builder.dart, with the state of its three
// subclasses: NamedTypeBuilder (named_type_builder.dart), FunctionTypeBuilder
// (function_type_builder.dart) and RecordTypeBuilder (record_type_builder.dart).
//
// A builder lives in `ElementStore::type_builders` and is named by its id
// from `TypeImpl::Builder`. `build` is ported with the rest of the linker's
// type resolution; this file holds the builders' data and the members a
// `TypeImpl` forwards to them (`nullabilitySuffix`, `withNullability`).

use std::rc::Rc;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::ast::ast_store::NodeId;
use crate::src::dart::element::element::{ElementId, ElementStore};
use crate::src::dart::element::r#type::{BuilderId, FormalParameter, TypeImpl};

/// `TypeBuilder` and its subclasses.
#[derive(Clone, Debug)]
pub enum TypeBuilder {
    Named(NamedTypeBuilder),
    Function(FunctionTypeBuilder),
    Record(RecordTypeBuilder),
}

/// `NamedTypeBuilder`.
#[derive(Clone, Debug)]
pub struct NamedTypeBuilder {
    pub element: ElementId,
    pub arguments: Vec<TypeImpl>,
    pub nullability_suffix: NullabilitySuffix,
    /// The `NamedType` this builder is for; `None` once detached.
    pub node: Option<NodeId>,
    /// `_type`: the built type, once `build` has run.
    pub type_: Option<TypeImpl>,
}

/// `FunctionTypeBuilder`.
#[derive(Clone, Debug)]
pub struct FunctionTypeBuilder {
    pub type_parameters: Vec<ElementId>,
    pub formal_parameters: Vec<FormalParameter>,
    pub return_type: TypeImpl,
    pub nullability_suffix: NullabilitySuffix,
    /// The `GenericFunctionType` or function-typed formal parameter.
    pub node: Option<NodeId>,
    pub type_: Option<TypeImpl>,
}

/// `RecordTypeBuilder`.
#[derive(Clone, Debug)]
pub struct RecordTypeBuilder {
    pub node: NodeId,
    /// `fieldTypes`: first the positional fields, then the named ones.
    pub field_types: Vec<TypeImpl>,
    /// The names of the named fields, in the order of `field_types`' tail.
    pub field_names: Vec<Rc<str>>,
    pub nullability_suffix: NullabilitySuffix,
    /// `_isBuilding`.
    pub is_building: bool,
    pub type_: Option<TypeImpl>,
}

impl TypeBuilder {
    /// `TypeBuilder.nullabilitySuffix`.
    pub fn nullability_suffix(&self) -> NullabilitySuffix {
        match self {
            TypeBuilder::Named(b) => b.nullability_suffix,
            TypeBuilder::Function(b) => b.nullability_suffix,
            TypeBuilder::Record(b) => b.nullability_suffix,
        }
    }
}

/// `withNullability` of the three builders: the same builder when the
/// nullability is unchanged, otherwise a copy with the new nullability.
/// `RecordTypeBuilder` has no `withNullability` of its own, so the call
/// reaches `TypeBuilder.noSuchMethod` and throws.
pub fn with_nullability(store: &mut ElementStore, id: BuilderId, nullability_suffix: NullabilitySuffix) -> TypeImpl {
    let builder = &store.type_builders[id as usize];
    if builder.nullability_suffix() == nullability_suffix {
        return TypeImpl::Builder(id);
    }
    let copy = match builder {
        TypeBuilder::Named(b) => TypeBuilder::Named(NamedTypeBuilder {
            element: b.element,
            arguments: b.arguments.clone(),
            nullability_suffix,
            node: b.node,
            type_: None,
        }),
        TypeBuilder::Function(b) => TypeBuilder::Function(FunctionTypeBuilder {
            type_parameters: b.type_parameters.clone(),
            formal_parameters: b.formal_parameters.clone(),
            return_type: b.return_type.clone(),
            nullability_suffix,
            node: b.node,
            type_: None,
        }),
        TypeBuilder::Record(_) => panic!("NoSuchMethodError: RecordTypeBuilder.withNullability"),
    };
    let new_id = store.type_builders.len() as BuilderId;
    store.type_builders.push(copy);
    TypeImpl::Builder(new_id)
}
