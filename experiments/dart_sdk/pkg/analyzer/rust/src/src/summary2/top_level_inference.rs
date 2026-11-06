// Port of lib/src/summary2/top_level_inference.dart: `TopLevelInference` and
// `_InitializerInference`, which give the variables and fields that have no
// type of their own a type inference (`_addVariableNode`), and then ask each
// of them for its type (`perform`).
//
// `_PropertyInducingElementTypeInference.perform` is decided here from the
// variable's linking node, once, and kept on the element as a
// `PropertyInducingElementTypeInference`; `ElementStore::property_inducing_
// type` (the `type` getter) runs it:
//
// - a declaring formal parameter (`FormalParameterImpl`) with no default
//   value and no function-typed suffix gets `Object?`;
// - a variable with no initializer, or no linking node, gets `dynamic`;
// - a variable whose type comes from its initializer, or a declaring formal
//   parameter from its default value, needs `AstResolver`, which is not
//   ported: its type is left unset. So are the dependency cycles found
//   while resolving initializers (`TopLevelInferenceErrorDependencyCycle`),
//   which only that resolution can find, and `_refineType`.
//
// Not ported either: `ConstantInitializersResolver`, and the override
// inference `_performOverrideInference` runs (`InstanceMemberInferrer`).
// The latter never sets the type of an extension type's field: the
// interface of an extension type overrides nothing
// (`_getInterfaceExtensionType` builds it with `overridden: const {}`), so
// the representation types `buildExtensionTypes` reads next do not wait for
// it.
//
// Upstream finds a field's linking node with `getLinkingNode`; a declaring
// formal parameter's field was given the formal parameter's node
// (`setFragmentNode(fieldFragment, formalParameter)`). The port's fragments
// keep one node, used to map nodes back to fragments, so a declaring field
// keeps none and its node is that of the formal parameter fragment it was
// built with ([LibraryFragments::declaring_fields]). An enum constant's
// field is linked upstream to a variable with a synthetic initializer (the
// constructor invocation), so its inference is from an initializer.

use std::collections::HashMap;

use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, NO_NODE};
use crate::src::dart::element::element::{
    ElementId, ElementStore, FragmentFlag, FragmentId, PropertyInducingElementTypeInference, UnitId,
};
use crate::src::summary2::library_builder::LibraryBuilder;

/// `TopLevelInference.infer`, for [builders], the libraries being linked.
pub fn infer(store: &mut ElementStore, builders: &[LibraryBuilder]) {
    let to_infer = create_nodes(store, builders);
    // `_performOverrideInference`: not ported (see above).
    perform(store, &to_infer);
}

/// `_InitializerInference.createNodes`: the fields of every interface,
/// enum, extension, extension type and mixin, then the top-level variables,
/// of each library.
fn create_nodes(store: &mut ElementStore, builders: &[LibraryBuilder]) -> Vec<ElementId> {
    let mut asts: HashMap<UnitId, Ast<'_>> = HashMap::new();
    let mut declaring_formal: HashMap<FragmentId, FragmentId> = HashMap::new();
    for builder in builders {
        for unit in &builder.units {
            if let Some(parsed) = &unit.parsed {
                asts.insert(unit.fragment, Ast::new(&parsed.ast, &parsed.tokens));
            }
        }
        declaring_formal.extend(builder.fragments.declaring_fields.iter().copied());
    }

    let mut to_infer = Vec::new();
    for builder in builders {
        let library = &store.libraries[builder.element as usize];
        let mut variables: Vec<ElementId> = Vec::new();
        for list in [&library.classes, &library.enums, &library.extensions, &library.extension_types, &library.mixins] {
            for &instance_element in list {
                variables.extend(store.element(instance_element).members().fields.iter().copied());
            }
        }
        variables.extend(library.top_level_variables.iter().copied());
        for variable in variables {
            if let Some(inference) = add_variable_node(store, &asts, &declaring_formal, variable) {
                store.types_mut(variable).type_inference = Some(inference);
                to_infer.push(variable);
            }
        }
    }
    to_infer
}

/// `_addVariableNode`: the type inference of [variable], if it needs one.
fn add_variable_node(
    store: &ElementStore,
    asts: &HashMap<UnitId, Ast<'_>>,
    declaring_formal: &HashMap<FragmentId, FragmentId>,
    variable: ElementId,
) -> Option<PropertyInducingElementTypeInference> {
    let first_fragment = store.element(variable).first_fragment;
    let f = store.fragment(first_fragment);
    if f.has_flag(FragmentFlag::propertyInducingFragment_isOriginGetterSetter) {
        return None;
    }
    if !f.has_flag(FragmentFlag::variableFragment_hasImplicitType) {
        return None;
    }
    Some(type_inference(store, asts, declaring_formal, first_fragment))
}

/// What `_PropertyInducingElementTypeInference.perform` infers the type of
/// the variable whose first fragment is [first_fragment] from.
fn type_inference(
    store: &ElementStore,
    asts: &HashMap<UnitId, Ast<'_>>,
    declaring_formal: &HashMap<FragmentId, FragmentId>,
    first_fragment: FragmentId,
) -> PropertyInducingElementTypeInference {
    use PropertyInducingElementTypeInference::*;
    let f = store.fragment(first_fragment);
    // `case FormalParameterImpl()`.
    if let Some(&formal) = declaring_formal.get(&first_fragment) {
        let formal = store.fragment(formal);
        let node = match asts.get(&formal.unit) {
            Some(ast) if formal.node != NO_NODE => ast.node(formal.node),
            _ => return NoInitializer,
        };
        let (default_clause, regular_without_suffix) = match node {
            AstNodeImpl::RegularFormalParameterImpl(p) => (p.default_clause, p.function_typed_suffix == NO_NODE),
            AstNodeImpl::FieldFormalParameterImpl(p) => (p.default_clause, false),
            AstNodeImpl::SuperFormalParameterImpl(p) => (p.default_clause, false),
            _ => return NoInitializer,
        };
        if default_clause != NO_NODE {
            return Initializer;
        }
        if regular_without_suffix {
            return DeclaringFormalParameter;
        }
        return NoInitializer;
    }
    if f.has_flag(FragmentFlag::fieldFragment_isEnumConstant) {
        return Initializer;
    }
    // `case VariableBindingImpl()`: `node.initializer2 != null`, which the
    // fragment's `hasInitializer` records.
    if f.node != NO_NODE && f.has_flag(FragmentFlag::nonParameterVariableFragment_hasInitializer) {
        return Initializer;
    }
    NoInitializer
}

/// `_InitializerInference.perform`: asks every variable for its type, which
/// runs its inference unless something read the type before.
fn perform(store: &mut ElementStore, to_infer: &[ElementId]) {
    for &variable in to_infer {
        store.property_inducing_type(variable);
    }
}
