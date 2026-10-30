// Port of lib/src/dart/element/type.dart: the `DartType` classes
// (`DynamicTypeImpl`, `VoidTypeImpl`, `InvalidTypeImpl`, `NeverTypeImpl`,
// `InterfaceTypeImpl`, `FunctionTypeImpl`, `RecordTypeImpl`,
// `TypeParameterTypeImpl`), with what linking needs of them: nullability,
// `withNullability`, `==`, and the queries on interface types
// (`isDartCoreObject`, `isValidSuperinterface`, ...).
//
// A type is a `TypeImpl` value: the classes with no state are variants of
// their own, and the others hold their data behind an `Rc`, as upstream's
// immutable objects are shared. Elements are named by their ids in the
// `ElementStore`. While a library cycle is linked, a type can also be a
// `TypeBuilder` of the linker (upstream's builders implement `TypeImpl`),
// named by its id in the store's `type_builders`.
//
// Not ported: the alias information (`alias`, `InstantiatedTypeAliasElement`),
// which only `getDisplayString(preferTypeAlias: true)` reads, the promoted
// bound of type parameter types, which flow analysis creates, `FutureOrTypeImpl`
// as a class of its own (it is an interface type whose element is `FutureOr`),
// and the members that look up members of types.

use std::rc::Rc;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore};
use crate::src::generated::utilities_dart::ParameterKind;

/// The id of a `TypeBuilder` in `ElementStore::type_builders`.
pub type BuilderId = u32;

/// `TypeImpl` and its subclasses.
#[derive(Clone, Debug)]
pub enum TypeImpl {
    /// `DynamicTypeImpl.instance`.
    Dynamic,
    /// `VoidTypeImpl.instance`.
    Void,
    /// `InvalidTypeImpl.instance`.
    Invalid,
    /// `NeverTypeImpl`, with its nullability.
    Never(NullabilitySuffix),
    Interface(Rc<InterfaceTypeImpl>),
    Function(Rc<FunctionTypeImpl>),
    Record(Rc<RecordTypeImpl>),
    TypeParameter(TypeParameterTypeImpl),
    /// A `TypeBuilder` (`NamedTypeBuilder`, `FunctionTypeBuilder` or
    /// `RecordTypeBuilder`), while linking.
    Builder(BuilderId),
}

/// `InterfaceTypeImpl`.
#[derive(Clone, Debug)]
pub struct InterfaceTypeImpl {
    pub element: ElementId,
    pub type_arguments: Vec<TypeImpl>,
    pub nullability_suffix: NullabilitySuffix,
}

/// A formal parameter of a `FunctionTypeImpl`: what of a
/// `FormalParameterElement` a function type reads (name, type, kind).
#[derive(Clone, Debug)]
pub struct FormalParameter {
    pub name: Option<Rc<str>>,
    pub type_: TypeImpl,
    pub kind: ParameterKind,
}

impl FormalParameter {
    pub fn is_named(&self) -> bool {
        matches!(self.kind, ParameterKind::NAMED | ParameterKind::NAMED_REQUIRED)
    }

    pub fn is_positional(&self) -> bool {
        !self.is_named()
    }

    pub fn is_optional(&self) -> bool {
        matches!(self.kind, ParameterKind::POSITIONAL | ParameterKind::NAMED)
    }

    pub fn is_required_positional(&self) -> bool {
        self.kind == ParameterKind::REQUIRED
    }

    pub fn is_optional_positional(&self) -> bool {
        self.kind == ParameterKind::POSITIONAL
    }

    pub fn is_required_named(&self) -> bool {
        self.kind == ParameterKind::NAMED_REQUIRED
    }

    /// `copyWith(type:, kind:)`.
    pub fn copy_with(&self, type_: Option<TypeImpl>, kind: Option<ParameterKind>) -> FormalParameter {
        FormalParameter {
            name: self.name.clone(),
            type_: type_.unwrap_or_else(|| self.type_.clone()),
            kind: kind.unwrap_or(self.kind),
        }
    }
}

/// `FunctionTypeImpl`. The named parameters follow the positional ones,
/// sorted by name, as the factory constructor sorts them.
#[derive(Clone, Debug)]
pub struct FunctionTypeImpl {
    pub type_parameters: Vec<ElementId>,
    /// `parameters`.
    pub formal_parameters: Vec<FormalParameter>,
    pub return_type: TypeImpl,
    pub nullability_suffix: NullabilitySuffix,
}

impl FunctionTypeImpl {
    /// The `FunctionTypeImpl` factory: sorts the named parameters by name
    /// when they are not sorted.
    pub fn new(
        type_parameters: Vec<ElementId>,
        mut formal_parameters: Vec<FormalParameter>,
        return_type: TypeImpl,
        nullability_suffix: NullabilitySuffix,
    ) -> FunctionTypeImpl {
        let mut first_named = None;
        let mut sorted = true;
        let mut last_name: &str = "";
        for (i, parameter) in formal_parameters.iter().enumerate() {
            if parameter.is_named() {
                first_named.get_or_insert(i);
                let name = parameter.name.as_deref().unwrap_or("");
                if compare_strings(last_name, name) == std::cmp::Ordering::Greater {
                    sorted = false;
                    break;
                }
                last_name = name;
            }
        }
        if !sorted {
            let first = first_named.unwrap();
            formal_parameters[first..].sort_by(|a, b| {
                compare_strings(a.name.as_deref().unwrap_or(""), b.name.as_deref().unwrap_or(""))
            });
        }
        FunctionTypeImpl {
            type_parameters,
            formal_parameters,
            return_type,
            nullability_suffix,
        }
    }
}

/// `RecordTypeImpl`; the named fields are sorted by name.
#[derive(Clone, Debug)]
pub struct RecordTypeImpl {
    pub positional_fields: Vec<TypeImpl>,
    pub named_fields: Vec<(Rc<str>, TypeImpl)>,
    pub nullability_suffix: NullabilitySuffix,
}

impl RecordTypeImpl {
    pub fn new(
        positional_fields: Vec<TypeImpl>,
        mut named_fields: Vec<(Rc<str>, TypeImpl)>,
        nullability_suffix: NullabilitySuffix,
    ) -> RecordTypeImpl {
        // `_sortNamedFields`.
        let sorted = named_fields
            .windows(2)
            .all(|w| compare_strings(&w[0].0, &w[1].0) != std::cmp::Ordering::Greater);
        if !sorted {
            named_fields.sort_by(|a, b| compare_strings(&a.0, &b.0));
        }
        RecordTypeImpl {
            positional_fields,
            named_fields,
            nullability_suffix,
        }
    }
}

/// `TypeParameterTypeImpl`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct TypeParameterTypeImpl {
    pub element: ElementId,
    pub nullability_suffix: NullabilitySuffix,
}

/// `String.compareTo`: by UTF-16 code units.
pub fn compare_strings(a: &str, b: &str) -> std::cmp::Ordering {
    a.encode_utf16().cmp(b.encode_utf16())
}

impl TypeImpl {
    pub fn interface(element: ElementId, type_arguments: Vec<TypeImpl>, nullability_suffix: NullabilitySuffix) -> TypeImpl {
        TypeImpl::Interface(Rc::new(InterfaceTypeImpl {
            element,
            type_arguments,
            nullability_suffix,
        }))
    }

    pub fn type_parameter(element: ElementId, nullability_suffix: NullabilitySuffix) -> TypeImpl {
        TypeImpl::TypeParameter(TypeParameterTypeImpl {
            element,
            nullability_suffix,
        })
    }

    pub fn as_interface(&self) -> Option<&Rc<InterfaceTypeImpl>> {
        match self {
            TypeImpl::Interface(t) => Some(t),
            _ => None,
        }
    }

    pub fn is_builder(&self) -> bool {
        matches!(self, TypeImpl::Builder(_))
    }

    /// `nullabilitySuffix`.
    pub fn nullability_suffix(&self, store: &ElementStore) -> NullabilitySuffix {
        match self {
            TypeImpl::Dynamic | TypeImpl::Void | TypeImpl::Invalid => NullabilitySuffix::none,
            TypeImpl::Never(n) => *n,
            TypeImpl::Interface(t) => t.nullability_suffix,
            TypeImpl::Function(t) => t.nullability_suffix,
            TypeImpl::Record(t) => t.nullability_suffix,
            TypeImpl::TypeParameter(t) => t.nullability_suffix,
            TypeImpl::Builder(id) => store.type_builders[*id as usize].nullability_suffix(),
        }
    }

    /// `withNullability`.
    pub fn with_nullability(&self, store: &mut ElementStore, nullability_suffix: NullabilitySuffix) -> TypeImpl {
        match self {
            TypeImpl::Dynamic | TypeImpl::Void | TypeImpl::Invalid => self.clone(),
            TypeImpl::Never(_) => TypeImpl::Never(match nullability_suffix {
                NullabilitySuffix::question | NullabilitySuffix::star => NullabilitySuffix::question,
                NullabilitySuffix::none => NullabilitySuffix::none,
            }),
            TypeImpl::Interface(t) => {
                if t.nullability_suffix == nullability_suffix || store.is_dart_core_null(t.element) {
                    return self.clone();
                }
                TypeImpl::interface(t.element, t.type_arguments.clone(), nullability_suffix)
            }
            TypeImpl::Function(t) => {
                if t.nullability_suffix == nullability_suffix {
                    return self.clone();
                }
                TypeImpl::Function(Rc::new(FunctionTypeImpl {
                    type_parameters: t.type_parameters.clone(),
                    formal_parameters: t.formal_parameters.clone(),
                    return_type: t.return_type.clone(),
                    nullability_suffix,
                }))
            }
            TypeImpl::Record(t) => {
                if t.nullability_suffix == nullability_suffix {
                    return self.clone();
                }
                TypeImpl::Record(Rc::new(RecordTypeImpl {
                    positional_fields: t.positional_fields.clone(),
                    named_fields: t.named_fields.clone(),
                    nullability_suffix,
                }))
            }
            TypeImpl::TypeParameter(t) => {
                if t.nullability_suffix == nullability_suffix {
                    return self.clone();
                }
                TypeImpl::type_parameter(t.element, nullability_suffix)
            }
            TypeImpl::Builder(id) => crate::src::summary2::type_builder::with_nullability(store, *id, nullability_suffix),
        }
    }

    /// `isDartCoreObject`.
    pub fn is_dart_core_object(&self, store: &ElementStore) -> bool {
        match self {
            TypeImpl::Interface(t) => store.is_dart_core_class(t.element, "Object"),
            _ => false,
        }
    }
}

impl InterfaceTypeImpl {
    /// `isValidSuperinterface`: whether this type can be used as an
    /// interface or a mixin.
    pub fn is_valid_superinterface(&self, store: &ElementStore) -> bool {
        let kind = store.element(self.element).kind;
        if kind == ElementKind::ENUM || kind == ElementKind::EXTENSION_TYPE {
            return false;
        }
        if store.is_dart_core_class(self.element, "Function") || store.is_dart_core_null(self.element) {
            return false;
        }
        self.nullability_suffix != NullabilitySuffix::question
    }

    /// `_isValidSuperclass` of types_builder.dart: usable as a class.
    pub fn is_valid_superclass(&self, store: &ElementStore) -> bool {
        store.element(self.element).kind == ElementKind::CLASS && self.is_valid_superinterface(store)
    }
}

/// `==` of the type classes. Two function types are equal when they are
/// equal after their type parameters are related, as
/// `FunctionTypeImpl.relateTypeFormals` and `instantiate` relate them.
pub fn type_equals(store: &ElementStore, a: &TypeImpl, b: &TypeImpl) -> bool {
    equals(store, a, b, &mut Vec::new())
}

fn equals(store: &ElementStore, a: &TypeImpl, b: &TypeImpl, related: &mut Vec<(ElementId, ElementId)>) -> bool {
    match (a, b) {
        (TypeImpl::Dynamic, TypeImpl::Dynamic) | (TypeImpl::Void, TypeImpl::Void) => true,
        (TypeImpl::Invalid, TypeImpl::Invalid) => true,
        (TypeImpl::Never(x), TypeImpl::Never(y)) => x == y,
        (TypeImpl::Interface(x), TypeImpl::Interface(y)) => {
            Rc::ptr_eq(x, y)
                || (x.element == y.element
                    && x.nullability_suffix == y.nullability_suffix
                    && equal_lists(store, &x.type_arguments, &y.type_arguments, related))
        }
        (TypeImpl::TypeParameter(x), TypeImpl::TypeParameter(y)) => {
            if x.nullability_suffix != y.nullability_suffix {
                return false;
            }
            if x.element == y.element {
                return true;
            }
            related.iter().rev().any(|(p, q)| *p == x.element && *q == y.element)
        }
        (TypeImpl::Record(x), TypeImpl::Record(y)) => {
            x.nullability_suffix == y.nullability_suffix
                && equal_lists(store, &x.positional_fields, &y.positional_fields, related)
                && x.named_fields.len() == y.named_fields.len()
                && x.named_fields
                    .iter()
                    .zip(&y.named_fields)
                    .all(|((n1, t1), (n2, t2))| n1 == n2 && equals(store, t1, t2, related))
        }
        (TypeImpl::Function(x), TypeImpl::Function(y)) => {
            if Rc::ptr_eq(x, y) {
                return true;
            }
            if x.nullability_suffix != y.nullability_suffix || x.type_parameters.len() != y.type_parameters.len() {
                return false;
            }
            let mark = related.len();
            for (p, q) in x.type_parameters.iter().zip(&y.type_parameters) {
                related.push((*p, *q));
            }
            // `relateTypeFormals`: the bounds must be equal.
            let mut result = true;
            for (p, q) in x.type_parameters.iter().zip(&y.type_parameters) {
                let pb = store.element(*p).type_.clone().unwrap_or(TypeImpl::Dynamic);
                let qb = store.element(*q).type_.clone().unwrap_or(TypeImpl::Dynamic);
                if !equals(store, &pb, &qb, related) {
                    result = false;
                    break;
                }
            }
            result = result
                && equals(store, &x.return_type, &y.return_type, related)
                && x.formal_parameters.len() == y.formal_parameters.len()
                && x.formal_parameters.iter().zip(&y.formal_parameters).all(|(f, s)| {
                    f.is_positional() == s.is_positional()
                        && f.is_optional() == s.is_optional()
                        && equals(store, &f.type_, &s.type_, related)
                        && (!f.is_named() || f.name == s.name)
                });
            related.truncate(mark);
            result
        }
        (TypeImpl::Builder(x), TypeImpl::Builder(y)) => x == y,
        _ => false,
    }
}

fn equal_lists(store: &ElementStore, a: &[TypeImpl], b: &[TypeImpl], related: &mut Vec<(ElementId, ElementId)>) -> bool {
    a.len() == b.len() && a.iter().zip(b).all(|(x, y)| equals(store, x, y, related))
}
