// Port of lib/src/dart/element/normalize.dart (`NormalizeHelper`): the NORM
// function of the Dart type system, which the class hierarchy applies before
// merging two different instantiations of the same class.
//
// Promoted bounds (`T & S`) are not part of this crate's types yet; they
// come from flow analysis, which linking does not run.

use std::collections::HashSet;
use std::rc::Rc;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::element::{ElementId, ElementStore};
use crate::src::dart::element::r#type::{FunctionTypeImpl, RecordTypeImpl, TypeImpl};
use crate::src::dart::element::type_system::{
    is_future_or, is_null_class, is_nullable, is_object_class, is_top, null_none, other_nullability, sdk_class,
    with_suffix, without_nullability,
};
use crate::src::summary2::type_builder::fresh_type_parameters;

/// `TypeSystemImpl.normalize`.
pub fn normalize(store: &mut ElementStore, t: &TypeImpl) -> TypeImpl {
    NormalizeHelper { store, type_parameters: HashSet::new() }.normalize(t)
}

struct NormalizeHelper<'s> {
    store: &'s mut ElementStore,
    /// `_typeParameters`: the type parameters whose bounds are being
    /// normalized, to stop at a cycle.
    type_parameters: HashSet<ElementId>,
}

impl NormalizeHelper<'_> {
    /// `_normalize`.
    fn normalize(&mut self, t: &TypeImpl) -> TypeImpl {
        let suffix = other_nullability(t);
        match t {
            TypeImpl::Dynamic | TypeImpl::Invalid | TypeImpl::Void => return t.clone(),
            TypeImpl::Never(NullabilitySuffix::none) => return t.clone(),
            TypeImpl::Interface(i) if suffix == NullabilitySuffix::none && i.type_arguments.is_empty() => {
                return t.clone();
            }
            _ => {}
        }
        if suffix == NullabilitySuffix::none && is_future_or(self.store, t) {
            return self.future_or(t);
        }
        if suffix == NullabilitySuffix::question {
            return self.nullability_question(t);
        }
        match t {
            TypeImpl::TypeParameter(p) => match &p.promoted_bound {
                Some(promoted_bound) => {
                    let s = self.normalize(promoted_bound);
                    self.type_parameter_type_promoted(p.element, s)
                }
                None => self.type_parameter_type(p.element, t),
            },
            TypeImpl::Interface(i) => {
                let arguments = i.type_arguments.iter().map(|a| self.normalize(a)).collect();
                TypeImpl::interface(i.element, arguments, NullabilitySuffix::none)
            }
            TypeImpl::Record(r) => {
                let positional = r.positional_fields.iter().map(|f| self.normalize(f)).collect();
                let named = r.named_fields.iter().map(|(n, f)| (n.clone(), self.normalize(f))).collect();
                TypeImpl::Record(Rc::new(RecordTypeImpl::new(positional, named, NullabilitySuffix::none)))
            }
            TypeImpl::Function(f) => self.function_type(f),
            _ => t.clone(),
        }
    }

    /// `_functionType`.
    fn function_type(&mut self, f: &FunctionTypeImpl) -> TypeImpl {
        let fresh = fresh_type_parameters(self.store, f);
        for &p in &fresh.type_parameters {
            if let Some(bound) = self.store.element(p).type_.clone() {
                let n = self.normalize(&bound);
                self.store.elements[p as usize].type_ = Some(n);
            }
        }
        let formal_parameters = fresh
            .formal_parameters
            .iter()
            .map(|p| {
                let t = self.normalize(&p.type_);
                p.copy_with(Some(t), None)
            })
            .collect();
        let return_type = self.normalize(&fresh.return_type);
        TypeImpl::Function(Rc::new(FunctionTypeImpl::new(
            fresh.type_parameters.clone(),
            formal_parameters,
            return_type,
            NullabilitySuffix::none,
        )))
    }

    /// `_futureOr`.
    fn future_or(&mut self, t: &TypeImpl) -> TypeImpl {
        let s = self.normalize(&t.as_interface().unwrap().type_arguments[0]);
        let s_suffix = other_nullability(&s);
        if is_top(self.store, &s) {
            return s;
        }
        if is_object_class(self.store, &s) && s_suffix == NullabilitySuffix::none {
            return s;
        }
        let future = sdk_class(self.store, "dart:async", "Future").expect("dart:async declares Future");
        if matches!(s, TypeImpl::Never(NullabilitySuffix::none)) {
            return TypeImpl::interface(future, vec![TypeImpl::Never(NullabilitySuffix::none)], NullabilitySuffix::none);
        }
        if s_suffix == NullabilitySuffix::none && is_null_class(self.store, &s) {
            return TypeImpl::interface(future, vec![null_none(self.store)], NullabilitySuffix::question);
        }
        let future_or = t.as_interface().unwrap().element;
        TypeImpl::interface(future_or, vec![s], NullabilitySuffix::none)
    }

    /// `_nullabilityQuestion`.
    fn nullability_question(&mut self, t: &TypeImpl) -> TypeImpl {
        let t_none = without_nullability(t);
        let s = self.normalize(&t_none);
        let s_suffix = other_nullability(&s);
        if is_top(self.store, &s) {
            return s;
        }
        if matches!(s, TypeImpl::Never(NullabilitySuffix::none)) {
            return null_none(self.store);
        }
        if s_suffix == NullabilitySuffix::none && is_null_class(self.store, &s) {
            return null_none(self.store);
        }
        if s_suffix == NullabilitySuffix::none && is_future_or(self.store, &s) {
            let r = &s.as_interface().unwrap().type_arguments[0];
            if is_nullable(self.store, r) {
                return s;
            }
        }
        with_suffix(&s, NullabilitySuffix::question)
    }

    /// `_typeParameterType`, for a type parameter type with no promoted
    /// bound.
    fn type_parameter_type(&mut self, element: ElementId, t: &TypeImpl) -> TypeImpl {
        let Some(bound) = self.store.element(element).type_.clone() else {
            return t.clone();
        };
        if !self.type_parameters.insert(element) {
            return t.clone();
        }
        let s = self.normalize(&bound);
        self.type_parameters.remove(&element);
        if matches!(s, TypeImpl::Never(NullabilitySuffix::none)) {
            return TypeImpl::Never(NullabilitySuffix::none);
        }
        t.clone()
    }

    /// `_typeParameterType_promoted`: NORM(X & T), with S = NORM(T).
    fn type_parameter_type_promoted(&mut self, x: ElementId, s: TypeImpl) -> TypeImpl {
        if matches!(s, TypeImpl::Never(NullabilitySuffix::none)) {
            return TypeImpl::Never(NullabilitySuffix::none);
        }
        if is_top(self.store, &s) {
            return TypeImpl::type_parameter(x, NullabilitySuffix::none);
        }
        if let TypeImpl::TypeParameter(p) = &s {
            if p.nullability_suffix == NullabilitySuffix::none && p.element == x {
                return TypeImpl::type_parameter(x, NullabilitySuffix::none);
            }
        }
        if other_nullability(&s) == NullabilitySuffix::none && is_object_class(self.store, &s) {
            if let Some(b) = self.store.element(x).type_.clone() {
                let b_norm = self.normalize(&b);
                if other_nullability(&b_norm) == NullabilitySuffix::none && is_object_class(self.store, &b_norm) {
                    return TypeImpl::type_parameter(x, NullabilitySuffix::none);
                }
            }
        }
        TypeImpl::promoted_type_parameter(x, NullabilitySuffix::none, s)
    }
}
