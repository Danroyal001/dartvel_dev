// Port of the parts of lib/src/dart/resolver/applicable_extensions.dart that
// find the extensions applicable to a receiver for an instance member:
// `havingMemberWithBaseName` (the extensions with an instance member of a
// basename, with its getter and setter) and `applicableTo` (those whose
// extended type the receiver's type matches, with their type parameters
// inferred from it).
//
// Not ported: static members (`havingStaticMemberWithName`), private names
// of other libraries (`havingPrivateMemberOfOtherLibraryWithBaseName`; the
// callers do not look up private names), `applicableTo` of extensions
// without a member (used by completion), and the inference log.

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::element::{ElementId, ElementStore, NO_ELEMENT};
use crate::src::dart::element::generic_inferrer::GenericInferrer;
use crate::src::dart::element::inheritance_manager3::Member;
use crate::src::dart::element::r#type::TypeImpl;
use crate::src::dart::element::subtype::TypeSystem;
use crate::src::dart::element::type_algebra::{Substitution, substitute};
use crate::src::dart::element::type_system::without_builders;

/// `_NotInstantiatedExtensionWithMember`: an extension with its instance
/// getter (or method) and setter of one basename.
#[derive(Clone, Debug)]
pub struct ExtensionWithMember {
    pub extension: ElementId,
    pub getter: Option<ElementId>,
    pub setter: Option<ElementId>,
}

/// `InstantiatedExtensionWithMember`: an applicable extension with the type
/// arguments inferred for it.
#[derive(Clone, Debug)]
pub struct InstantiatedExtensionWithMember {
    pub candidate: ExtensionWithMember,
    pub substitution: Substitution,
    pub extended_type: TypeImpl,
}

impl InstantiatedExtensionWithMember {
    pub fn extension(&self) -> ElementId {
        self.candidate.extension
    }

    /// `getter`: the getter or method, substituted.
    pub fn getter(&self) -> Option<Member> {
        self.candidate.getter.map(|element| Member {
            element,
            substitution: self.substitution.clone(),
            combined: None,
        })
    }
}

/// The type parameters an extension declares.
pub fn extension_type_parameters(store: &ElementStore, extension: ElementId) -> Vec<ElementId> {
    let first = store.element(extension).first_fragment;
    store.fragment(first).type_parameters.iter().map(|&f| store.fragment(f).element).collect()
}

/// `extendedType` of [extension]: `dynamic` when it has none.
pub fn extended_type(store: &ElementStore, extension: ElementId) -> TypeImpl {
    store.element(extension).type_.as_ref().map_or(TypeImpl::Dynamic, |t| without_builders(store, t))
}

fn is_instance(store: &ElementStore, element: ElementId) -> bool {
    !store.fragment(store.element(element).first_fragment).is_static()
}

/// `getMethod(name)` of [extension] (`unary-` for unary minus).
pub fn extension_method(store: &ElementStore, extension: ElementId, name: &str) -> Option<ElementId> {
    store.element(extension).members.as_deref()?.methods.iter().copied().find(|&method| {
        store.fragment(store.element(method).first_fragment).method_lookup_name().as_deref() == Some(name)
    })
}

/// `getGetter(name)` of [extension].
pub fn extension_getter(store: &ElementStore, extension: ElementId, name: &str) -> Option<ElementId> {
    store.element(extension).members.as_deref()?.getters.iter().copied().find(|&g| store.element(g).name.as_deref() == Some(name))
}

/// `havingMemberWithBaseName` (`addIfHasMemberWithBaseName` for each): for
/// `[]` the methods `[]` and `[]=`; otherwise the getter and setter of an
/// instance field [name] (each getter or setter has one), then an instance
/// method [name], as two candidates.
pub fn having_member_with_base_name(store: &ElementStore, extensions: &[ElementId], name: &str) -> Vec<ExtensionWithMember> {
    let mut result = Vec::new();
    for &extension in extensions {
        if name == "[]" {
            let getter = extension_method(store, extension, "[]");
            let setter = extension_method(store, extension, "[]=");
            if getter.is_some() || setter.is_some() {
                result.push(ExtensionWithMember { extension, getter, setter });
            }
            continue;
        }
        let Some(members) = store.element(extension).members.as_deref() else {
            continue;
        };
        let field = members.fields.iter().copied().find(|&f| store.element(f).name.as_deref() == Some(name));
        if let Some(field) = field {
            if is_instance(store, field) {
                let e = store.element(field);
                let as_option = |id: ElementId| (id != NO_ELEMENT).then_some(id);
                let (getter, setter) = (as_option(e.getter), as_option(e.setter));
                if getter.is_some() || setter.is_some() {
                    result.push(ExtensionWithMember { extension, getter, setter });
                }
            }
        }
        if let Some(method) = extension_method(store, extension, name) {
            if is_instance(store, method) {
                result.push(ExtensionWithMember { extension, getter: Some(method), setter: None });
            }
        }
    }
    result
}

/// `applicableTo`: the [candidates] whose extended type, with fresh copies
/// of the extension's type parameters inferred from [target] (the target is
/// a subtype of it, `constrainArgument`), is a supertype of [target]; none
/// for `Never`.
pub fn applicable_to(
    system: &mut TypeSystem<'_>,
    candidates: Vec<ExtensionWithMember>,
    target: &TypeImpl,
    inference_using_bounds: bool,
) -> Vec<InstantiatedExtensionWithMember> {
    if matches!(target, TypeImpl::Never(NullabilitySuffix::none)) {
        return Vec::new();
    }
    let mut instantiated = Vec::new();
    for candidate in candidates {
        let extension = candidate.extension;
        let type_parameters = extension_type_parameters(system.store, extension);
        let declared = extended_type(system.store, extension);
        let substitution = if type_parameters.is_empty() {
            Substitution::from_pairs(Vec::new(), Vec::new())
        } else {
            // `getFreshTypeParameters`.
            let fresh: Vec<ElementId> =
                type_parameters.iter().map(|&p| system.store.fresh_copy_type_parameter(p)).collect();
            let to_fresh = Substitution::from_pairs(
                type_parameters.clone(),
                fresh.iter().map(|&f| TypeImpl::type_parameter(f, NullabilitySuffix::none)).collect(),
            );
            for (i, &p) in type_parameters.iter().enumerate() {
                if let Some(bound) = system.store.element(p).type_.clone() {
                    let bound = without_builders(system.store, &bound);
                    let fresh_bound = substitute(system.store, &to_fresh, &bound);
                    system.store.elements[fresh[i] as usize].type_ = Some(fresh_bound);
                }
            }
            let raw_extended = substitute(system.store, &to_fresh, &declared);
            let mut inferrer = GenericInferrer::new(system, fresh, inference_using_bounds);
            inferrer.constrain_argument(target, &raw_extended);
            let Some(inferred) = inferrer.try_choose_final_types(true) else {
                continue;
            };
            Substitution::from_pairs(type_parameters, inferred)
        };
        let extended = substitute(system.store, &substitution, &declared);
        if !system.is_subtype_of(target, &extended) {
            continue;
        }
        instantiated.push(InstantiatedExtensionWithMember { candidate, substitution, extended_type: extended });
    }
    instantiated
}
