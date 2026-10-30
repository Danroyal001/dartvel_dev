// Port of lib/src/dart/element/subtype.dart (`SubtypeHelper`, the subtype
// relation of resources/type-system/subtyping.md), with what it uses of
// type_system.dart: the type operation depth limit (`enterTypeOperation`,
// past which a check answers `false`), `relateTypeParameters`, `isEqualTo`,
// and `FunctionTypeImpl.instantiate`.
//
// Promoted bounds and the unknown inferred type are not part of this crate's
// types yet; their rules come with flow analysis and inference.

use std::rc::Rc;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::class_hierarchy::{from_interface_type, ClassHierarchy};
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore};
use crate::src::dart::element::r#type::{FunctionTypeImpl, TypeImpl, TypeParameterTypeImpl};
use crate::src::dart::element::type_algebra::{substitute, Substitution};
use crate::src::dart::element::type_system::{
    is_future_or, is_null_class, is_object_class, null_none, object_type, other_nullability, sdk_class, with_suffix,
};
use crate::fe_analyzer_shared::types::shared_type::Variance;

/// `TypeSystemImpl._maxTypeOperationDepth`.
pub(crate) const MAX_TYPE_OPERATION_DEPTH: usize = 100;

/// The type system state the relation needs: the store, the class
/// hierarchy, and the operation depth.
pub struct TypeSystem<'a> {
    pub store: &'a mut ElementStore,
    pub hierarchy: &'a mut ClassHierarchy,
    pub(crate) depth: usize,
}

impl<'a> TypeSystem<'a> {
    pub fn new(store: &'a mut ElementStore, hierarchy: &'a mut ClassHierarchy) -> Self {
        TypeSystem { store, hierarchy, depth: 0 }
    }

    /// `isSubtypeOf`: false past the operation depth limit.
    pub fn is_subtype_of(&mut self, t0: &TypeImpl, t1: &TypeImpl) -> bool {
        self.depth += 1;
        let result = if self.depth > MAX_TYPE_OPERATION_DEPTH { false } else { self.subtype(t0, t1) };
        self.depth -= 1;
        result
    }

    /// `isEqualTo`: mutual subtypes.
    pub fn is_equal_to(&mut self, a: &TypeImpl, b: &TypeImpl) -> bool {
        self.is_subtype_of(a, b) && self.is_subtype_of(b, a)
    }

    fn bound_or_object_question(&self, p: ElementId) -> TypeImpl {
        self.store
            .element(p)
            .type_
            .clone()
            .unwrap_or_else(|| object_type(self.store, NullabilitySuffix::question))
    }

    /// Left promoted variable (`X0 & S0` with `S0 <: T1`) or left type
    /// variable bound (`X0` with bound `B0 <: T1`).
    fn left_type_variable(&mut self, p: &TypeParameterTypeImpl, t1: &TypeImpl) -> bool {
        if let Some(s0) = &p.promoted_bound {
            let s0 = (**s0).clone();
            if self.is_subtype_of(&s0, t1) {
                return true;
            }
        }
        let b0 = self.bound_or_object_question(p.element);
        self.is_subtype_of(&b0, t1)
    }

    /// `_isSubtypeOf`.
    fn subtype(&mut self, t0: &TypeImpl, t1: &TypeImpl) -> bool {
        // `_` is treated as a top and a bottom type during inference.
        if matches!(t0, TypeImpl::Unknown) || matches!(t1, TypeImpl::Unknown) {
            return true;
        }
        if matches!(t0, TypeImpl::Invalid) || matches!(t1, TypeImpl::Invalid) {
            return true;
        }
        let t1_suffix = other_nullability(t1);
        let t0_suffix = other_nullability(t0);
        let store = &*self.store;

        // Right top.
        if matches!(t1, TypeImpl::Dynamic | TypeImpl::Void)
            || (t1_suffix == NullabilitySuffix::question && is_object_class(store, t1))
        {
            return true;
        }
        // Left top.
        if matches!(t0, TypeImpl::Dynamic | TypeImpl::Void) {
            let oq = object_type(store, NullabilitySuffix::question);
            if self.is_subtype_of(&oq, t1) {
                return true;
            }
        }
        // Left bottom.
        if matches!(t0, TypeImpl::Never(NullabilitySuffix::none)) {
            return true;
        }
        // Right Object.
        if t1_suffix == NullabilitySuffix::none && is_object_class(self.store, t1) {
            if t0_suffix == NullabilitySuffix::none {
                if let TypeImpl::TypeParameter(p) = t0 {
                    let b = match &p.promoted_bound {
                        Some(s) => (**s).clone(),
                        None => self.bound_or_object_question(p.element),
                    };
                    let on = object_type(self.store, NullabilitySuffix::none);
                    return self.is_subtype_of(&b, &on);
                }
                if is_future_or(self.store, t0) {
                    let a = t0.as_interface().unwrap().type_arguments[0].clone();
                    return self.is_subtype_of(&a, t1);
                }
            }
            if (t0_suffix == NullabilitySuffix::none && is_null_class(self.store, t0))
                || matches!(t0, TypeImpl::Dynamic | TypeImpl::Void)
                || t0_suffix == NullabilitySuffix::question
            {
                return false;
            }
            if let TypeImpl::Interface(i) = t0 {
                if self.store.element(i.element).kind == ElementKind::EXTENSION_TYPE {
                    for interface in self.interfaces_of(i.element, &i.type_arguments) {
                        if self.is_subtype_of(&interface, t1) {
                            return true;
                        }
                    }
                    return false;
                }
            }
            return true;
        }
        // Left Null.
        if t0_suffix == NullabilitySuffix::none && is_null_class(self.store, t0) {
            if t1_suffix == NullabilitySuffix::none && is_future_or(self.store, t1) {
                let s = t1.as_interface().unwrap().type_arguments[0].clone();
                let nn = null_none(self.store);
                return self.is_subtype_of(&nn, &s);
            }
            if (t1_suffix == NullabilitySuffix::none && is_null_class(self.store, t1))
                || t1_suffix == NullabilitySuffix::question
            {
                return true;
            }
            return false;
        }
        // Left FutureOr.
        if t0_suffix == NullabilitySuffix::none && is_future_or(self.store, t0) {
            let s0 = t0.as_interface().unwrap().type_arguments[0].clone();
            if self.is_subtype_of(&s0, t1) {
                let future = sdk_class(self.store, "dart:async", "Future").expect("dart:async declares Future");
                let future_s0 = TypeImpl::interface(future, vec![s0], NullabilitySuffix::none);
                return self.is_subtype_of(&future_s0, t1);
            }
            return false;
        }
        // Left nullable.
        if t0_suffix == NullabilitySuffix::question {
            let s0 = with_suffix(t0, NullabilitySuffix::none);
            let nn = null_none(self.store);
            return self.is_subtype_of(&s0, t1) && self.is_subtype_of(&nn, t1);
        }
        // Type variable reflexivity.
        if let (TypeImpl::TypeParameter(a), TypeImpl::TypeParameter(b)) = (t0, t1) {
            if b.promoted_bound.is_none() && a.element == b.element {
                return true;
            }
        }
        // Right promoted variable: `T0 <: X1 & S1` iff `T0 <: X1` and `T0 <: S1`.
        if let TypeImpl::TypeParameter(b) = t1 {
            if let Some(s1) = &b.promoted_bound {
                let x1 = TypeImpl::type_parameter(b.element, b.nullability_suffix);
                let s1 = (**s1).clone();
                return self.is_subtype_of(t0, &x1) && self.is_subtype_of(t0, &s1);
            }
        }
        // Right FutureOr.
        if t1_suffix == NullabilitySuffix::none && is_future_or(self.store, t1) {
            let s1 = t1.as_interface().unwrap().type_arguments[0].clone();
            let future = sdk_class(self.store, "dart:async", "Future").expect("dart:async declares Future");
            let future_s1 = TypeImpl::interface(future, vec![s1.clone()], NullabilitySuffix::none);
            if self.is_subtype_of(t0, &future_s1) || self.is_subtype_of(t0, &s1) {
                return true;
            }
            if let TypeImpl::TypeParameter(p) = t0 {
                if self.left_type_variable(p, t1) {
                    return true;
                }
            }
            return false;
        }
        // Right nullable.
        if t1_suffix == NullabilitySuffix::question {
            let s1 = with_suffix(t1, NullabilitySuffix::none);
            if self.is_subtype_of(t0, &s1) {
                return true;
            }
            let nn = null_none(self.store);
            if self.is_subtype_of(t0, &nn) {
                return true;
            }
            if let TypeImpl::TypeParameter(p) = t0 {
                if self.left_type_variable(p, t1) {
                    return true;
                }
            }
            return false;
        }
        match (t0, t1) {
            (TypeImpl::Interface(_), TypeImpl::Interface(_)) => self.interface_subtype(t0, t1),
            (TypeImpl::TypeParameter(p), _) => self.left_type_variable(p, t1),
            (TypeImpl::Function(f), TypeImpl::Function(g)) => self.function_subtype(f, g),
            (TypeImpl::Function(_), TypeImpl::Interface(i)) => self.store.is_dart_core_class(i.element, "Function"),
            (TypeImpl::Record(a), TypeImpl::Record(b)) => {
                if a.positional_fields.len() != b.positional_fields.len() || a.named_fields.len() != b.named_fields.len() {
                    return false;
                }
                for (x, y) in a.positional_fields.iter().zip(&b.positional_fields) {
                    if !self.is_subtype_of(x, y) {
                        return false;
                    }
                }
                for ((n1, x), (n2, y)) in a.named_fields.iter().zip(&b.named_fields) {
                    if n1 != n2 || !self.is_subtype_of(x, y) {
                        return false;
                    }
                }
                true
            }
            (TypeImpl::Record(_), TypeImpl::Interface(i)) => self.store.is_dart_core_class(i.element, "Record"),
            _ => false,
        }
    }

    /// The interfaces of an extension type's element, substituted
    /// (`InterfaceType.interfaces`).
    fn interfaces_of(&mut self, element: ElementId, arguments: &[TypeImpl]) -> Vec<TypeImpl> {
        let raw = self.store.types(element).map(|t| t.interfaces.clone()).unwrap_or_default();
        let substitution = from_interface_type(self.store, element, arguments);
        raw.iter().map(|t| substitute(self.store, &substitution, t)).collect()
    }

    /// `_interfaceArguments`.
    fn interface_arguments(&mut self, element: ElementId, sub: &[TypeImpl], sup: &[TypeImpl]) -> bool {
        let first = self.store.element(element).first_fragment;
        let parameters: Vec<ElementId> =
            self.store.fragment(first).type_parameters.iter().map(|&f| self.store.fragment(f).element).collect();
        for i in 0..sub.len().min(sup.len()).min(parameters.len()) {
            let variance = self.store.variance(parameters[i]);
            let ok = if variance.is_covariant() {
                self.is_subtype_of(&sub[i], &sup[i])
            } else if variance.is_contravariant() {
                self.is_subtype_of(&sup[i], &sub[i])
            } else if variance == Variance::invariant {
                self.is_subtype_of(&sub[i], &sup[i]) && self.is_subtype_of(&sup[i], &sub[i])
            } else {
                panic!("StateError: unknown variance for subtype checking");
            };
            if !ok {
                return false;
            }
        }
        true
    }

    /// `_isInterfaceSubtypeOf`.
    fn interface_subtype(&mut self, t0: &TypeImpl, t1: &TypeImpl) -> bool {
        let (sub, sup) = (t0.as_interface().unwrap().clone(), t1.as_interface().unwrap().clone());
        if Rc::ptr_eq(&sub, &sup) || self.store.is_dart_core_class(sup.element, "Object") {
            return true;
        }
        if self.store.is_dart_core_class(sub.element, "Object") {
            return false;
        }
        if sub.element == sup.element {
            return self.interface_arguments(sup.element, &sub.type_arguments, &sup.type_arguments);
        }
        if self.store.is_dart_core_class(sub.element, "Function") || self.store.is_dart_core_class(sup.element, "Function") {
            return false;
        }
        let all = self.hierarchy.implemented_interfaces(self.store, sub.element);
        for interface in all {
            let i = interface.as_interface().unwrap().clone();
            if i.element == sup.element {
                let substitution = from_interface_type(self.store, sub.element, &sub.type_arguments);
                let substituted = substitute(self.store, &substitution, &interface);
                let args = substituted.as_interface().unwrap().type_arguments.clone();
                return self.interface_arguments(sup.element, &args, &sup.type_arguments);
            }
        }
        false
    }

    /// `relateTypeParameters`: fresh type parameters both function types can
    /// be instantiated with, when the bounds are equal.
    pub fn relate_type_parameters(&mut self, a: &[ElementId], b: &[ElementId]) -> Option<Vec<TypeImpl>> {
        if a.len() != b.len() {
            return None;
        }
        if a.is_empty() {
            return Some(Vec::new());
        }
        let fresh: Vec<ElementId> = a.iter().map(|&p| self.store.fresh_copy_type_parameter(p)).collect();
        let types: Vec<TypeImpl> = fresh.iter().map(|&p| TypeImpl::type_parameter(p, NullabilitySuffix::none)).collect();
        let s1 = Substitution::from_pairs(a.to_vec(), types.clone());
        let s2 = Substitution::from_pairs(b.to_vec(), types.clone());
        for i in 0..a.len() {
            let b1 = self.store.element(a[i]).type_.clone();
            let b2 = self.store.element(b[i]).type_.clone();
            if b1.is_none() && b2.is_none() {
                continue;
            }
            let b1 = substitute(self.store, &s1, &b1.unwrap_or(TypeImpl::Dynamic));
            let b2 = substitute(self.store, &s2, &b2.unwrap_or(TypeImpl::Dynamic));
            if !self.is_equal_to(&b1, &b2) {
                return None;
            }
            if !matches!(b1, TypeImpl::Dynamic) {
                self.store.elements[fresh[i] as usize].type_ = Some(b1);
            }
        }
        Some(types)
    }

    /// `_isFunctionSubtypeOf`.
    fn function_subtype(&mut self, f: &FunctionTypeImpl, g: &FunctionTypeImpl) -> bool {
        let Some(fresh) = self.relate_type_parameters(&f.type_parameters, &g.type_parameters) else {
            return false;
        };
        let f = instantiate(self.store, f, &fresh);
        let g = instantiate(self.store, g, &fresh);
        if !self.is_subtype_of(&f.return_type, &g.return_type) {
            return false;
        }
        let (fp, gp) = (&f.formal_parameters, &g.formal_parameters);
        let (mut fi, mut gi) = (0, 0);
        while fi < fp.len() && gi < gp.len() {
            let (a, b) = (&fp[fi], &gp[gi]);
            if a.is_required_positional() {
                if b.is_required_positional() && self.is_subtype_of(&b.type_, &a.type_) {
                    fi += 1;
                    gi += 1;
                } else {
                    return false;
                }
            } else if a.is_optional_positional() {
                if b.is_positional() && self.is_subtype_of(&b.type_, &a.type_) {
                    fi += 1;
                    gi += 1;
                } else {
                    return false;
                }
            } else if a.is_named() {
                if !b.is_named() {
                    break;
                }
                let (Some(an), Some(bn)) = (&a.name, &b.name) else {
                    return false;
                };
                match crate::src::dart::element::r#type::compare_strings(an, bn) {
                    std::cmp::Ordering::Equal => {
                        if (a.is_required_named() && !b.is_required_named()) || !self.is_subtype_of(&b.type_, &a.type_) {
                            return false;
                        }
                        fi += 1;
                        gi += 1;
                    }
                    std::cmp::Ordering::Less => {
                        if a.is_required_named() {
                            return false;
                        }
                        fi += 1;
                    }
                    std::cmp::Ordering::Greater => return false,
                }
            }
        }
        while fi < fp.len() {
            let a = &fp[fi];
            fi += 1;
            if a.is_required_positional() || a.is_required_named() {
                return false;
            }
        }
        gi >= gp.len()
    }
}

/// `FunctionTypeImpl.instantiate`.
pub fn instantiate(store: &mut ElementStore, f: &FunctionTypeImpl, arguments: &[TypeImpl]) -> FunctionTypeImpl {
    assert_eq!(arguments.len(), f.type_parameters.len());
    if arguments.is_empty() {
        return f.clone();
    }
    let substitution = Substitution::from_pairs(f.type_parameters.clone(), arguments.to_vec());
    let formal_parameters = f
        .formal_parameters
        .iter()
        .map(|p| {
            let t = substitute(store, &substitution, &p.type_);
            p.copy_with(Some(t), None)
        })
        .collect();
    let return_type = substitute(store, &substitution, &f.return_type);
    FunctionTypeImpl::new(Vec::new(), formal_parameters, return_type, f.nullability_suffix)
}
