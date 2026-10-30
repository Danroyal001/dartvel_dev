// Port of the parts of lib/src/dart/element/type_system.dart (`TypeSystemImpl`)
// and type_provider.dart that the linker's type algorithms use: the classes
// of `dart:core` and `dart:async` they name (`Object`, `Null`, `Future`,
// `FutureOr`), and the predicates `isTop`, `isObject`, `isNullable`.
//
// Upstream's unknown inferred type (`_`) is not a `TypeImpl` here; the
// algorithms that need it are ported with it.

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
        TypeImpl::Dynamic | TypeImpl::Invalid | TypeImpl::Void => true,
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
        TypeImpl::Dynamic | TypeImpl::Invalid | TypeImpl::Void => true,
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
        TypeImpl::Dynamic | TypeImpl::Invalid | TypeImpl::Void => NullabilitySuffix::none,
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
        TypeImpl::Dynamic | TypeImpl::Invalid | TypeImpl::Void => t.clone(),
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
        TypeImpl::TypeParameter(p) => TypeImpl::type_parameter(p.element, suffix),
        TypeImpl::Builder(_) => panic!("a TypeBuilder has no nullability outside linking"),
    }
}
