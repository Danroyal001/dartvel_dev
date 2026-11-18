// Port of the part of lib/src/dart/resolver/type_property_resolver.dart
// (`TypePropertyResolver.resolve` for a read, `hasRead` without `hasWrite`)
// that finds the getter or method a receiver of a static type has under a
// name: `dynamic` and invalid receivers have only `Object`'s members; a
// receiver that may be null finds `Object`'s member, else an applicable
// extension's (and fails otherwise: upstream recovers through the bound's
// interface after reporting); any other receiver finds its bound's
// interface member (stopping there when the interface has a setter of the
// name, or for `call` of `Function`), else, but for a function's `call`, a
// `Never` receiver and a record field, an applicable extension's member,
// else `Object`'s.
//
// The interface lookup is inheritance_manager3.rs's `get_member`, the
// extension lookup extension_member_resolver.rs's `find_extension`. Not
// ported: `super` receivers, writes, the recovery lookups (static members,
// the bound's interface after a nullable receiver fails, private members of
// other libraries), `new`, and diagnostics.

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::element::{ElementId, ElementKind};
use crate::src::dart::element::inheritance_manager3::{Member, MethodLookup, get_member, has_setter};
use crate::src::dart::element::r#type::TypeImpl;
use crate::src::dart::element::subtype::TypeSystem;
use crate::src::dart::element::type_system::{
    is_dynamic_bounded, is_invalid_bounded, is_non_nullable, object_type, resolve_to_bound,
};
use crate::src::dart::resolver::extension_member_resolver::{ExtensionResolution, find_extension};

/// What [resolve] finds for a read of a name.
#[derive(Clone, Debug)]
pub enum PropertyLookup {
    /// The getter or method: of the interface, of `Object` or of an
    /// extension.
    Member(Member),
    /// The receiver is bounded by `dynamic` or invalid and the name is not
    /// one of `Object`'s members: resolved without a member.
    DynamicBounded,
    /// The receiver's bound is `Never` (non-nullable): resolved without a
    /// member.
    Never,
    /// Nothing found: `LookupOutcome.notFound` (or an ambiguity of
    /// extensions, which upstream reports).
    NotFound,
    /// What is not ported: a conflict of interface members, `call` of a
    /// function or of `Function`, a record field.
    Unresolved,
}

/// The receiver context of a lookup: the extensions accessible in the file
/// and the library's `inference-using-bounds` feature.
pub struct ExtensionScope<'e> {
    pub extensions: &'e [ElementId],
    pub inference_using_bounds: bool,
}

/// `TypePropertyResolver.resolve(receiverType: receiver, name: name,
/// hasRead: true, hasWrite: false)` for a receiver that is an expression.
pub fn resolve(system: &mut TypeSystem<'_>, scope: &ExtensionScope<'_>, receiver: &TypeImpl, name: &str) -> PropertyLookup {
    if is_dynamic_bounded(system.store, receiver) || is_invalid_bounded(system.store, receiver) {
        return match lookup_object(system, name) {
            Some(member) => PropertyLookup::Member(member),
            None => PropertyLookup::DynamicBounded,
        };
    }
    if may_be_null(system, receiver) {
        if let Some(member) = lookup_object(system, name) {
            return PropertyLookup::Member(member);
        }
        return lookup_extension(system, scope, receiver, name).unwrap_or(PropertyLookup::NotFound);
    }
    let bound = resolve_to_bound(system.store, receiver);
    match &bound {
        TypeImpl::Interface(interface) => {
            let interface = interface.clone();
            match get_member(system, &interface, name) {
                MethodLookup::Found(member) => return PropertyLookup::Member(member),
                MethodLookup::Ambiguous => return PropertyLookup::Unresolved,
                MethodLookup::NotFound => {}
            }
            // `_lookupInterfaceType` reads the setter when the getter is
            // missing: the basename is then the interface's.
            if has_setter(system.store, &interface, name) {
                return PropertyLookup::NotFound;
            }
            if name == "call" && system.store.is_dart_core_class(interface.element, "Function") {
                return PropertyLookup::Unresolved;
            }
        }
        TypeImpl::Function(_) if name == "call" => return PropertyLookup::Unresolved,
        TypeImpl::Never(_) => return PropertyLookup::Never,
        TypeImpl::Record(record) => {
            let positional = name
                .strip_prefix('$')
                .and_then(|n| n.parse::<usize>().ok())
                .is_some_and(|n| n >= 1 && n <= record.positional_fields.len() && !name[1..].starts_with('0'));
            if positional || record.named_fields.iter().any(|(field, _)| &**field == name) {
                return PropertyLookup::Unresolved;
            }
        }
        _ => {}
    }
    if let Some(found) = lookup_extension(system, scope, receiver, name) {
        return found;
    }
    match lookup_object(system, name) {
        Some(member) => PropertyLookup::Member(member),
        None => PropertyLookup::NotFound,
    }
}

/// Whether `resolve` treats a receiver of [type_] as nullable: an extension
/// type when it is marked so, any other type when it is potentially
/// nullable.
pub fn may_be_null(system: &TypeSystem<'_>, type_: &TypeImpl) -> bool {
    match type_.as_interface() {
        Some(i) if system.store.element(i.element).kind == ElementKind::EXTENSION_TYPE => {
            i.nullability_suffix == NullabilitySuffix::question
        }
        _ => !is_non_nullable(system.store, type_),
    }
}

/// `_lookupInterfaceType(typeProvider.objectType)`: `Object`'s member [name].
fn lookup_object(system: &mut TypeSystem<'_>, name: &str) -> Option<Member> {
    let object = object_type(system.store, NullabilitySuffix::none);
    let interface = object.as_interface()?.clone();
    match get_member(system, &interface, name) {
        MethodLookup::Found(member) => Some(member),
        _ => None,
    }
}

/// `_lookupExtension`: `None` when no extension has the basename, else what
/// the most specific one gives a read (nothing when it has only a setter, or
/// when the extensions are ambiguous).
fn lookup_extension(
    system: &mut TypeSystem<'_>,
    scope: &ExtensionScope<'_>,
    receiver: &TypeImpl,
    name: &str,
) -> Option<PropertyLookup> {
    match find_extension(system, scope.extensions, receiver, name, scope.inference_using_bounds) {
        ExtensionResolution::None => None,
        ExtensionResolution::Ambiguous => Some(PropertyLookup::NotFound),
        ExtensionResolution::Single { getter: Some(member), .. } => Some(PropertyLookup::Member(member)),
        ExtensionResolution::Single { getter: None, .. } => Some(PropertyLookup::NotFound),
    }
}
