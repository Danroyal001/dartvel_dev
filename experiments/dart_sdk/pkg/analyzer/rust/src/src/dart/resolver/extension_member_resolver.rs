// Port of the parts of lib/src/dart/resolver/extension_member_resolver.dart
// that resolve an instance member through extensions: `findExtension` (the
// most specific accessible extension applicable to a type that has a member
// of a basename, `_chooseMostSpecific` and `_isMoreSpecific`),
// `getOverrideMember` (a member of the extension an explicit override names)
// and the type arguments `resolveOverride` gives an override
// (`_inferTypeArguments`).
//
// Not ported: static members (`findStaticExtension`), private names of other
// libraries, the receiver context of an override
// (`computeOverrideReceiverContextType`), the checks and diagnostics of
// `resolveOverride` (invalid contexts, argument counts, bounds, assignability)
// and of ambiguities, and marking extensions used.

use crate::src::dart::ast::ast_store::NodeId;
use crate::src::dart::element::element::{ElementId, ElementStore};
use crate::src::dart::element::generic_inferrer::{GenericInferrer, instantiate_type_formals_to_bounds};
use crate::src::dart::element::inheritance_manager3::Member;
use crate::src::dart::element::r#type::TypeImpl;
use crate::src::dart::element::subtype::TypeSystem;
use crate::src::dart::element::type_algebra::{Substitution, substitute};
use crate::src::dart::resolver::applicable_extensions::{
    InstantiatedExtensionWithMember, applicable_to, extended_type, extension_getter, extension_method,
    extension_type_parameters, having_member_with_base_name,
};

/// What `findExtension` returns.
#[derive(Clone, Debug)]
pub enum ExtensionResolution {
    /// `ExtensionResolutionError.none`.
    None,
    /// `ExtensionResolutionError.ambiguous`.
    Ambiguous,
    /// `SingleExtensionResolutionResult`: the getter (or method), substituted,
    /// and whether there is a setter.
    Single { getter: Option<Member>, has_setter: bool },
}

/// `findExtension`: the most specific of the [extensions] accessible in the
/// file that are applicable to [type_] and have an instance member with the
/// basename [name].
pub fn find_extension(
    system: &mut TypeSystem<'_>,
    extensions: &[ElementId],
    type_: &TypeImpl,
    name: &str,
    inference_using_bounds: bool,
) -> ExtensionResolution {
    let candidates = having_member_with_base_name(system.store, extensions, name);
    if candidates.is_empty() {
        return ExtensionResolution::None;
    }
    let applicable = applicable_to(system, candidates, type_, inference_using_bounds);
    let single = |e: &InstantiatedExtensionWithMember| ExtensionResolution::Single {
        getter: e.getter(),
        has_setter: e.candidate.setter.is_some(),
    };
    match applicable.len() {
        0 => ExtensionResolution::None,
        1 => single(&applicable[0]),
        _ => {
            let most_specific = choose_most_specific(system, applicable);
            if most_specific.len() == 1 { single(&most_specific[0]) } else { ExtensionResolution::Ambiguous }
        }
    }
}

/// `_chooseMostSpecific`: the most specific extension, or, when that is
/// ambiguous, the extensions none of which is more specific than another.
fn choose_most_specific(
    system: &mut TypeSystem<'_>,
    extensions: Vec<InstantiatedExtensionWithMember>,
) -> Vec<InstantiatedExtensionWithMember> {
    let mut best_so_far: Option<InstantiatedExtensionWithMember> = None;
    let mut none_more_specific: Vec<InstantiatedExtensionWithMember> = Vec::new();
    for candidate in extensions {
        if !none_more_specific.is_empty() {
            let mut is_most_specific = true;
            let mut has_more_specific = false;
            for other in &none_more_specific {
                if !is_more_specific(system, &candidate, other) {
                    is_most_specific = false;
                }
                if is_more_specific(system, other, &candidate) {
                    has_more_specific = true;
                }
            }
            if is_most_specific {
                best_so_far = Some(candidate);
                none_more_specific.clear();
            } else if !has_more_specific {
                none_more_specific.push(candidate);
            }
        } else if let Some(best) = best_so_far.take() {
            if is_more_specific(system, &best, &candidate) {
                best_so_far = Some(best);
            } else if is_more_specific(system, &candidate, &best) {
                best_so_far = Some(candidate);
            } else {
                none_more_specific.push(best);
                none_more_specific.push(candidate);
            }
        } else {
            best_so_far = Some(candidate);
        }
    }
    match best_so_far {
        Some(best) => vec![best],
        None => none_more_specific,
    }
}

/// `_isMoreSpecific`: [e1] is not from a platform library where [e2] is, and
/// its instantiated extended type is a subtype of [e2]'s and not the reverse,
/// or else its instantiate-to-bounds extended type is.
fn is_more_specific(
    system: &mut TypeSystem<'_>,
    e1: &InstantiatedExtensionWithMember,
    e2: &InstantiatedExtensionWithMember,
) -> bool {
    let e1_is_in_sdk = system.store.is_in_sdk(e1.extension());
    let e2_is_in_sdk = system.store.is_in_sdk(e2.extension());
    if e1_is_in_sdk && !e2_is_in_sdk {
        return false;
    } else if !e1_is_in_sdk && e2_is_in_sdk {
        return true;
    }
    if !system.is_subtype_of(&e1.extended_type, &e2.extended_type) {
        return false;
    }
    if !system.is_subtype_of(&e2.extended_type, &e1.extended_type) {
        return true;
    }
    let bound1 = instantiate_to_bounds(system.store, e1.extension());
    let bound2 = instantiate_to_bounds(system.store, e2.extension());
    system.is_subtype_of(&bound1, &bound2) && !system.is_subtype_of(&bound2, &bound1)
}

/// `_instantiateToBounds`: the extended type of [extension] with its type
/// parameters instantiated to their bounds.
fn instantiate_to_bounds(store: &mut ElementStore, extension: ElementId) -> TypeImpl {
    let type_parameters = extension_type_parameters(store, extension);
    let (arguments, _) = instantiate_type_formals_to_bounds(store, &type_parameters, &[]);
    let declared = extended_type(store, extension);
    substitute(store, &Substitution::from_pairs(type_parameters, arguments), &declared)
}

/// `_inferTypeArguments` of an override of [extension] whose argument has
/// type [receiver]: the type arguments written ([written], when the override
/// has them; `dynamic` for each when their number is wrong), or those
/// inferred from [receiver] (`chooseFinalTypes`, which recovers from errors).
pub fn override_type_arguments(
    system: &mut TypeSystem<'_>,
    extension: ElementId,
    written: Option<Vec<TypeImpl>>,
    receiver: &TypeImpl,
    inference_using_bounds: bool,
) -> Vec<TypeImpl> {
    let type_parameters = extension_type_parameters(system.store, extension);
    match written {
        Some(arguments) if arguments.len() == type_parameters.len() => arguments,
        Some(_) => vec![TypeImpl::Dynamic; type_parameters.len()],
        None => {
            let declared = extended_type(system.store, extension);
            let mut inferrer = GenericInferrer::new(system, type_parameters, inference_using_bounds);
            inferrer.constrain_argument(receiver, &declared);
            inferrer.choose_final_types()
        }
    }
}

/// `getOverrideMember(node, name).getter2` of an override of [extension]
/// with [type_arguments]: for `[]` the method `[]`, otherwise the getter
/// [name] or else the method [name] (static members too), substituted.
pub fn override_member(store: &ElementStore, extension: ElementId, type_arguments: &[TypeImpl], name: &str) -> Option<Member> {
    let element = if name == "[]" {
        extension_method(store, extension, "[]")
    } else {
        extension_getter(store, extension, name).or_else(|| extension_method(store, extension, name))
    }?;
    Some(Member {
        element,
        substitution: Substitution::from_pairs(extension_type_parameters(store, extension), type_arguments.to_vec()),
        combined: None,
    })
}

/// An explicit extension override `E(x)`, `E<T>(x)` or `p.E(x)` with one
/// positional argument, as `ScopeAnalyzer._visitScopeInvocation` makes it an
/// `ExtensionOverride2` when the called name finds an extension.
#[derive(Clone, Debug)]
pub struct ExtensionOverride {
    pub extension: ElementId,
    /// The types of the type arguments written, when there are some.
    pub type_arguments: Option<Vec<TypeImpl>>,
    /// The argument: the receiver of the members accessed through it.
    pub argument: NodeId,
}
