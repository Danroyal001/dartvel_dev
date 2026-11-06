// Port of the parts of lib/src/dart/element/type_system.dart (`TypeSystemImpl`)
// and type_provider.dart that the linker's type algorithms use: the classes
// of `dart:core` and `dart:async` they name (`Object`, `Null`, `Future`,
// `FutureOr`), and the predicates `isTop`, `isObject`, `isNullable`,
// `isNonNullable` and `isBottom`.

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore};
use crate::src::dart::element::r#type::TypeImpl;

/// A class of a `dart:` library, by library URI and name.
pub fn sdk_class(store: &ElementStore, library_uri: &str, name: &str) -> Option<ElementId> {
    let library = store.libraries.iter().position(|l| &*l.uri == library_uri)?;
    store.libraries[library]
        .classes
        .iter()
        .copied()
        .find(|&c| store.element(c).name.as_deref() == Some(name))
}

/// Whether [element] is the class [name] of the `dart:` library [library_uri].
pub fn is_sdk_class(store: &ElementStore, element: ElementId, library_uri: &str, name: &str) -> bool {
    let e = store.element(element);
    e.kind == ElementKind::CLASS
        && e.name.as_deref() == Some(name)
        && (e.library as usize) < store.libraries.len()
        && &*store.libraries[e.library as usize].uri == library_uri
}

/// `isDartAsyncFutureOr`.
pub fn is_future_or(store: &ElementStore, t: &TypeImpl) -> bool {
    t.as_interface().is_some_and(|i| is_sdk_class(store, i.element, "dart:async", "FutureOr"))
}

/// `isDartCoreObject`.
pub fn is_object_class(store: &ElementStore, t: &TypeImpl) -> bool {
    t.as_interface().is_some_and(|i| store.is_dart_core_class(i.element, "Object"))
}

/// `isDartCoreNull`.
pub fn is_null_class(store: &ElementStore, t: &TypeImpl) -> bool {
    t.as_interface().is_some_and(|i| store.is_dart_core_null(i.element))
}

/// `typeSystem.nullNone`: `Null`.
pub fn null_none(store: &ElementStore) -> TypeImpl {
    let null = sdk_class(store, "dart:core", "Null").expect("dart:core declares Null");
    TypeImpl::interface(null, Vec::new(), NullabilitySuffix::none)
}

/// `typeSystem.objectNone` and `objectQuestion`.
pub fn object_type(store: &ElementStore, suffix: NullabilitySuffix) -> TypeImpl {
    let object = sdk_class(store, "dart:core", "Object").expect("dart:core declares Object");
    TypeImpl::interface(object, Vec::new(), suffix)
}

/// `TypeSystemImpl.isTop`.
pub fn is_top(store: &ElementStore, t: &TypeImpl) -> bool {
    match t {
        TypeImpl::Dynamic | TypeImpl::Invalid | TypeImpl::Void | TypeImpl::Unknown => true,
        _ => {
            let suffix = match t {
                TypeImpl::Builder(_) => return false,
                other => other_nullability(other),
            };
            if suffix == NullabilitySuffix::question {
                let none = without_nullability(t);
                return is_top(store, &none) || is_object(store, &none);
            }
            if is_future_or(store, t) {
                let argument = &t.as_interface().unwrap().type_arguments[0];
                return is_top(store, argument);
            }
            false
        }
    }
}

/// `TypeSystemImpl.isObject`.
pub fn is_object(store: &ElementStore, t: &TypeImpl) -> bool {
    if other_nullability(t) != NullabilitySuffix::none {
        return false;
    }
    if is_object_class(store, t) {
        return true;
    }
    if is_future_or(store, t) {
        return is_object(store, &t.as_interface().unwrap().type_arguments[0]);
    }
    false
}

/// `TypeSystemImpl.isNullable`.
pub fn is_nullable(store: &ElementStore, t: &TypeImpl) -> bool {
    match t {
        TypeImpl::Dynamic | TypeImpl::Invalid | TypeImpl::Void | TypeImpl::Unknown => true,
        _ if is_null_class(store, t) => true,
        _ if other_nullability(t) == NullabilitySuffix::question => true,
        TypeImpl::Interface(i) if is_future_or(store, t) => is_nullable(store, &i.type_arguments[0]),
        _ => false,
    }
}

/// The nullability suffix of a type that is not a builder.
pub fn other_nullability(t: &TypeImpl) -> NullabilitySuffix {
    match t {
        // `DynamicTypeImpl`, `InvalidTypeImpl` and `VoidTypeImpl` report `none`.
        TypeImpl::Dynamic | TypeImpl::Invalid | TypeImpl::Void | TypeImpl::Unknown => NullabilitySuffix::none,
        TypeImpl::Never(s) => *s,
        TypeImpl::Interface(i) => i.nullability_suffix,
        TypeImpl::Function(f) => f.nullability_suffix,
        TypeImpl::Record(r) => r.nullability_suffix,
        TypeImpl::TypeParameter(p) => p.nullability_suffix,
        TypeImpl::Builder(_) => panic!("a TypeBuilder has no nullability outside linking"),
    }
}

/// `withNullability(NullabilitySuffix.none)` of a type that is not a builder.
pub fn without_nullability(t: &TypeImpl) -> TypeImpl {
    with_suffix(t, NullabilitySuffix::none)
}

/// `withNullability` of a type that is not a builder.
pub fn with_suffix(t: &TypeImpl, suffix: NullabilitySuffix) -> TypeImpl {
    use std::rc::Rc;
    match t {
        TypeImpl::Dynamic | TypeImpl::Invalid | TypeImpl::Void | TypeImpl::Unknown => t.clone(),
        TypeImpl::Never(_) => TypeImpl::Never(suffix),
        TypeImpl::Interface(i) => TypeImpl::interface(i.element, i.type_arguments.clone(), suffix),
        TypeImpl::Function(f) => {
            let mut f = (**f).clone();
            f.nullability_suffix = suffix;
            TypeImpl::Function(Rc::new(f))
        }
        TypeImpl::Record(r) => {
            let mut r = (**r).clone();
            r.nullability_suffix = suffix;
            TypeImpl::Record(Rc::new(r))
        }
        TypeImpl::TypeParameter(p) => TypeImpl::TypeParameter(crate::src::dart::element::r#type::TypeParameterTypeImpl {
            nullability_suffix: suffix,
            ..p.clone()
        }),
        TypeImpl::Builder(_) => panic!("a TypeBuilder has no nullability outside linking"),
    }
}

/// `typeProvider.futureType`: `Future<argument>`.
pub fn future_type(store: &ElementStore, argument: TypeImpl) -> TypeImpl {
    let future = sdk_class(store, "dart:async", "Future").expect("dart:async declares Future");
    TypeImpl::interface(future, vec![argument], NullabilitySuffix::none)
}

/// `TypeImpl.isBottom`: `Never`, or a non-nullable type parameter whose
/// bound is bottom, following bounds that are type parameters once each.
pub fn is_bottom(store: &ElementStore, t: &TypeImpl) -> bool {
    match t {
        TypeImpl::Never(suffix) => *suffix != NullabilitySuffix::question,
        TypeImpl::TypeParameter(p) => {
            let mut seen = Vec::new();
            let mut p = p.clone();
            while !seen.contains(&p.element) {
                seen.push(p.element);
                if p.nullability_suffix == NullabilitySuffix::question {
                    return false;
                }
                // `bound`: the promoted bound, else the declared one.
                let bound = match &p.promoted_bound {
                    Some(b) => Some((**b).clone()),
                    None => store.element(p.element).type_.clone(),
                };
                match bound {
                    Some(TypeImpl::TypeParameter(bound)) => p = bound,
                    Some(bound) => return is_bottom(store, &bound),
                    None => return false,
                }
            }
            // A cycle of bounds.
            false
        }
        _ => false,
    }
}

/// `TypeSystemImpl.isNonNullable`.
pub fn is_non_nullable(store: &ElementStore, t: &TypeImpl) -> bool {
    non_nullable(store, t, &mut Vec::new())
}

/// `_isNonNullable`.
fn non_nullable(store: &ElementStore, t: &TypeImpl, visited: &mut Vec<ElementId>) -> bool {
    match t {
        TypeImpl::Dynamic | TypeImpl::Invalid | TypeImpl::Unknown | TypeImpl::Void => return false,
        _ if is_null_class(store, t) => return false,
        TypeImpl::TypeParameter(p) if p.promoted_bound.is_some() => {
            return non_nullable(store, p.promoted_bound.as_ref().unwrap(), visited);
        }
        TypeImpl::Builder(_) => return false,
        _ => {}
    }
    if other_nullability(t) == NullabilitySuffix::question {
        return false;
    }
    match t {
        TypeImpl::Interface(i) => {
            if is_future_or(store, t) {
                return non_nullable(store, &i.type_arguments[0], visited);
            }
            if store.element(i.element).kind == ElementKind::EXTENSION_TYPE {
                return store.types(i.element).is_some_and(|ty| !ty.interfaces.is_empty());
            }
            true
        }
        TypeImpl::TypeParameter(p) => {
            let Some(bound) = store.element(p.element).type_.clone() else {
                return false;
            };
            if visited.contains(&p.element) {
                return false;
            }
            visited.push(p.element);
            non_nullable(store, &bound, visited)
        }
        _ => true,
    }
}

/// `typeProvider.futureOrType`: `FutureOr<argument>`.
pub fn future_or_type(store: &ElementStore, argument: TypeImpl) -> TypeImpl {
    let future_or = sdk_class(store, "dart:async", "FutureOr").expect("dart:async declares FutureOr");
    TypeImpl::interface(future_or, vec![argument], NullabilitySuffix::none)
}

/// `isDartAsyncFuture`.
pub fn is_future(store: &ElementStore, t: &TypeImpl) -> bool {
    t.as_interface().is_some_and(|i| is_sdk_class(store, i.element, "dart:async", "Future"))
}

/// `isDartCoreFunction`.
pub fn is_function_class(store: &ElementStore, t: &TypeImpl) -> bool {
    t.as_interface().is_some_and(|i| store.is_dart_core_class(i.element, "Function"))
}

/// `isDartCoreRecord`.
pub fn is_record_class(store: &ElementStore, t: &TypeImpl) -> bool {
    t.as_interface().is_some_and(|i| store.is_dart_core_class(i.element, "Record"))
}

/// `isDartCoreNull`, which `Never?` is too.
pub fn is_dart_core_null(store: &ElementStore, t: &TypeImpl) -> bool {
    matches!(t, TypeImpl::Never(NullabilitySuffix::question)) || is_null_class(store, t)
}

/// `TypeSystemImpl.isNull`.
pub fn is_null(store: &ElementStore, t: &TypeImpl) -> bool {
    if is_dart_core_null(store, t) {
        return true;
    }
    if other_nullability(t) == NullabilitySuffix::question {
        return is_bottom(store, &without_nullability(t));
    }
    false
}

/// `TypeSystemImpl.isMoreTop`.
pub fn is_more_top(store: &ElementStore, t: &TypeImpl, s: &TypeImpl) -> bool {
    let (t_nullability, s_nullability) = (other_nullability(t), other_nullability(s));
    if matches!(t, TypeImpl::Void) {
        return true;
    }
    if matches!(s, TypeImpl::Void) {
        return false;
    }
    if matches!(t, TypeImpl::Dynamic | TypeImpl::Invalid) {
        return true;
    }
    if matches!(s, TypeImpl::Dynamic | TypeImpl::Invalid) {
        return false;
    }
    if t_nullability == NullabilitySuffix::none && is_object_class(store, t) {
        return true;
    }
    if s_nullability == NullabilitySuffix::none && is_object_class(store, s) {
        return false;
    }
    if t_nullability == NullabilitySuffix::question && s_nullability == NullabilitySuffix::question {
        return is_more_top(store, &without_nullability(t), &without_nullability(s));
    }
    if s_nullability == NullabilitySuffix::question {
        return true;
    }
    if t_nullability == NullabilitySuffix::question {
        return false;
    }
    if is_future_or(store, t) && is_future_or(store, s) {
        let t2 = &t.as_interface().unwrap().type_arguments[0];
        let s2 = &s.as_interface().unwrap().type_arguments[0];
        return is_more_top(store, t2, s2);
    }
    false
}

/// `TypeSystemImpl.isMoreBottom`.
pub fn is_more_bottom(store: &ElementStore, t: &TypeImpl, s: &TypeImpl) -> bool {
    let (t_nullability, s_nullability) = (other_nullability(t), other_nullability(s));
    if matches!(t, TypeImpl::Never(NullabilitySuffix::none)) {
        return true;
    }
    if matches!(s, TypeImpl::Never(NullabilitySuffix::none)) {
        return false;
    }
    if t_nullability == NullabilitySuffix::none && is_dart_core_null(store, t) {
        return true;
    }
    if s_nullability == NullabilitySuffix::none && is_dart_core_null(store, s) {
        return false;
    }
    if t_nullability == NullabilitySuffix::question && s_nullability == NullabilitySuffix::question {
        return is_more_bottom(store, &without_nullability(t), &without_nullability(s));
    }
    if s_nullability == NullabilitySuffix::question {
        return true;
    }
    if t_nullability == NullabilitySuffix::question {
        return false;
    }
    if let (TypeImpl::TypeParameter(tp), TypeImpl::TypeParameter(sp)) = (t, s) {
        match (&tp.promoted_bound, &sp.promoted_bound) {
            (Some(a), Some(b)) => return is_more_bottom(store, a, b),
            (Some(_), None) => return true,
            (None, Some(_)) => return false,
            (None, None) => {}
        }
        let t_bound = store.element(tp.element).type_.clone().unwrap_or(TypeImpl::Dynamic);
        let s_bound = store.element(sp.element).type_.clone().unwrap_or(TypeImpl::Dynamic);
        return is_more_bottom(store, &t_bound, &s_bound);
    }
    false
}

/// `TypeSystemImpl.promoteToNonNull`.
pub fn promote_to_non_null(store: &ElementStore, t: &TypeImpl) -> TypeImpl {
    if is_dart_core_null(store, t) {
        return TypeImpl::Never(NullabilitySuffix::none);
    }
    if let TypeImpl::TypeParameter(p) = t {
        if let Some(promoted_bound) = &p.promoted_bound {
            let promoted_bound = promote_to_non_null(store, promoted_bound);
            return TypeImpl::promoted_type_parameter(p.element, NullabilitySuffix::none, promoted_bound);
        }
        // `identical(promotedBound, element.bound)`: the bound unchanged by
        // promotion means no promoted bound.
        return match store.element(p.element).type_.clone() {
            Some(bound) => {
                let promoted = promote_to_non_null(store, &bound);
                if promotion_is_identity(&bound, &promoted) {
                    TypeImpl::type_parameter(p.element, NullabilitySuffix::none)
                } else {
                    TypeImpl::promoted_type_parameter(p.element, NullabilitySuffix::none, promoted)
                }
            }
            None => TypeImpl::promoted_type_parameter(
                p.element,
                NullabilitySuffix::none,
                object_type(store, NullabilitySuffix::none),
            ),
        };
    }
    without_nullability(t)
}

/// Whether `promoteToNonNull` returned its argument itself: upstream's
/// `withNullability` returns `this` when the nullability does not change,
/// and a type parameter type is always rebuilt.
fn promotion_is_identity(before: &TypeImpl, after: &TypeImpl) -> bool {
    use std::rc::Rc;
    match (before, after) {
        (TypeImpl::Interface(a), TypeImpl::Interface(b)) => Rc::ptr_eq(a, b),
        (TypeImpl::Function(a), TypeImpl::Function(b)) => Rc::ptr_eq(a, b),
        (TypeImpl::Record(a), TypeImpl::Record(b)) => Rc::ptr_eq(a, b),
        (TypeImpl::TypeParameter(_), _) => false,
        (TypeImpl::Never(a), TypeImpl::Never(b)) => a == b,
        (TypeImpl::Dynamic, TypeImpl::Dynamic)
        | (TypeImpl::Void, TypeImpl::Void)
        | (TypeImpl::Invalid, TypeImpl::Invalid)
        | (TypeImpl::Unknown, TypeImpl::Unknown) => true,
        _ => false,
    }
}

/// `String.compareTo` of parameter names.
pub fn compare_names(a: &str, b: &str) -> std::cmp::Ordering {
    crate::src::dart::element::r#type::compare_strings(a, b)
}
