// Port of lib/src/dart/element/least_upper_bound.dart: `LeastUpperBoundHelper`,
// UP(T1, T2) of resources/type-system/upper-lower-bounds.md, and
// `InterfaceLeastUpperBoundHelper`, the classic algorithm for two interface
// types neither of which is a subtype of the other (the superinterface
// shared at the unique greatest depth from `Object`); as methods of the
// `TypeSystem` with `TypeSystemImpl.leastUpperBound`.
//
// Upstream throws `TypeOperationDepthLimitExceeded` past the type operation
// depth limit and the outermost UP catches it and answers `Object?`; here
// it is the `Err` of `lub`.

use std::rc::Rc;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::fe_analyzer_shared::types::shared_type::Variance;
use crate::src::dart::element::class_hierarchy::from_interface_type;
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore, FragmentFlag};
use crate::src::dart::element::greatest_lower_bound::fresh_elements;
use crate::src::dart::element::least_greatest_closure::greatest_closure;
use crate::src::dart::element::r#type::{type_equals, FunctionTypeImpl, InterfaceTypeImpl, RecordTypeImpl, TypeImpl};
use crate::src::dart::element::subtype::{instantiate, TypeSystem, MAX_TYPE_OPERATION_DEPTH};
use crate::src::dart::element::type_algebra::substitute;
use crate::src::dart::element::type_system::{
    compare_names, future_or_type, is_bottom, is_function_class, is_future, is_future_or, is_more_bottom, is_more_top,
    is_non_nullable, is_null, is_nullable, is_object, is_record_class, is_top, object_type, other_nullability,
    sdk_class, with_suffix, without_nullability,
};
use crate::src::generated::utilities_dart::ParameterKind;

/// `TypeOperationDepthLimitExceeded`.
#[derive(Debug, Clone, Copy)]
pub struct DepthExceeded;

impl TypeSystem<'_> {
    /// `TypeSystemImpl.leastUpperBound`.
    pub fn least_upper_bound(&mut self, t1: &TypeImpl, t2: &TypeImpl) -> TypeImpl {
        match self.lub(t1, t2) {
            Ok(t) => t,
            Err(_) => object_type(self.store, NullabilitySuffix::question),
        }
    }

    /// `getLeastUpperBound`: the depth guard around `_computeLeastUpperBound`.
    pub(crate) fn lub(&mut self, t1: &TypeImpl, t2: &TypeImpl) -> Result<TypeImpl, DepthExceeded> {
        self.depth += 1;
        let is_outermost = self.depth == 1;
        let result =
            if self.depth > MAX_TYPE_OPERATION_DEPTH { Err(DepthExceeded) } else { self.compute_lub(t1, t2) };
        self.depth -= 1;
        match result {
            Err(_) if is_outermost => Ok(object_type(self.store, NullabilitySuffix::question)),
            other => other,
        }
    }

    /// `_computeLeastUpperBound`.
    fn compute_lub(&mut self, t1: &TypeImpl, t2: &TypeImpl) -> Result<TypeImpl, DepthExceeded> {
        if matches!(t1, TypeImpl::Unknown) {
            return Ok(t2.clone());
        }
        if matches!(t2, TypeImpl::Unknown) {
            return Ok(t1.clone());
        }
        let store = &*self.store;

        let (t1_is_top, t2_is_top) = (is_top(store, t1), is_top(store, t2));
        if t1_is_top && t2_is_top {
            return Ok(if is_more_top(store, t1, t2) { t1.clone() } else { t2.clone() });
        }
        if t1_is_top {
            return Ok(t1.clone());
        }
        if t2_is_top {
            return Ok(t2.clone());
        }

        let (t1_is_bottom, t2_is_bottom) = (is_bottom(store, t1), is_bottom(store, t2));
        if t1_is_bottom && t2_is_bottom {
            return Ok(if is_more_bottom(store, t1, t2) { t2.clone() } else { t1.clone() });
        }
        if t1_is_bottom {
            return Ok(t2.clone());
        }
        if t2_is_bottom {
            return Ok(t1.clone());
        }

        // UP(X1 & B1, T2).
        if let TypeImpl::TypeParameter(p) = t1 {
            if let Some(b1) = &p.promoted_bound {
                let x1 = TypeImpl::type_parameter(p.element, p.nullability_suffix);
                if self.is_subtype_of(&x1, t2) {
                    return Ok(t2.clone());
                }
                if self.is_subtype_of(t2, &x1) {
                    return Ok(x1);
                }
                let b1a = greatest_closure(self.store, b1, &[p.element]);
                return self.lub(&b1a, t2);
            }
        }
        // UP(T1, X2 & B2).
        if let TypeImpl::TypeParameter(p) = t2 {
            if let Some(b2) = &p.promoted_bound {
                let x2 = TypeImpl::type_parameter(p.element, p.nullability_suffix);
                if self.is_subtype_of(t1, &x2) {
                    return Ok(x2);
                }
                if self.is_subtype_of(&x2, t1) {
                    return Ok(t1.clone());
                }
                let b2a = greatest_closure(self.store, b2, &[p.element]);
                return self.lub(t1, &b2a);
            }
        }

        let store = &*self.store;
        let (t1_is_null, t2_is_null) = (is_null(store, t1), is_null(store, t2));
        if t1_is_null && t2_is_null {
            return Ok(if is_more_bottom(store, t1, t2) { t2.clone() } else { t1.clone() });
        }
        if t1_is_null {
            return Ok(if is_nullable(store, t2) { t2.clone() } else { with_suffix(t2, NullabilitySuffix::question) });
        }
        if t2_is_null {
            return Ok(if is_nullable(store, t1) { t1.clone() } else { with_suffix(t1, NullabilitySuffix::question) });
        }

        let (t1_is_object, t2_is_object) = (is_object(store, t1), is_object(store, t2));
        if t1_is_object && t2_is_object {
            return Ok(if is_more_top(store, t1, t2) { t1.clone() } else { t2.clone() });
        }
        if t1_is_object {
            return Ok(if is_non_nullable(store, t2) { t1.clone() } else { with_suffix(t1, NullabilitySuffix::question) });
        }
        if t2_is_object {
            return Ok(if is_non_nullable(store, t1) { t2.clone() } else { with_suffix(t2, NullabilitySuffix::question) });
        }

        if other_nullability(t1) != NullabilitySuffix::none || other_nullability(t2) != NullabilitySuffix::none {
            let s = self.lub(&without_nullability(t1), &without_nullability(t2))?;
            return Ok(with_suffix(&s, NullabilitySuffix::question));
        }

        // UP(X1 extends B1, T2).
        if let TypeImpl::TypeParameter(p) = t1 {
            if self.is_subtype_of(t1, t2) {
                return Ok(t2.clone());
            }
            if self.is_subtype_of(t2, t1) {
                return Ok(t1.clone());
            }
            let bound = self.type_parameter_bound(p.element);
            let closure = greatest_closure(self.store, &bound, &[p.element]);
            return self.lub(&closure, t2);
        }
        // UP(T1, X2 extends B2).
        if let TypeImpl::TypeParameter(p) = t2 {
            if self.is_subtype_of(t1, t2) {
                return Ok(t2.clone());
            }
            if self.is_subtype_of(t2, t1) {
                return Ok(t1.clone());
            }
            let bound = self.type_parameter_bound(p.element);
            let closure = greatest_closure(self.store, &bound, &[p.element]);
            return self.lub(t1, &closure);
        }

        let store = &*self.store;
        if matches!(t1, TypeImpl::Function(_)) && is_function_class(store, t2) {
            return Ok(t2.clone());
        }
        if is_function_class(store, t1) && matches!(t2, TypeImpl::Function(_)) {
            return Ok(t1.clone());
        }
        if let (TypeImpl::Function(f), TypeImpl::Function(g)) = (t1, t2) {
            return self.lub_function_type(f, g);
        }
        let object_none = object_type(store, NullabilitySuffix::none);
        if matches!(t1, TypeImpl::Function(_)) {
            return self.lub(&object_none, t2);
        }
        if matches!(t2, TypeImpl::Function(_)) {
            return self.lub(t1, &object_none);
        }

        if matches!(t1, TypeImpl::Record(_)) && is_record_class(store, t2) {
            return Ok(t2.clone());
        }
        if is_record_class(store, t1) && matches!(t2, TypeImpl::Record(_)) {
            return Ok(t1.clone());
        }
        if let (TypeImpl::Record(a), TypeImpl::Record(b)) = (t1, t2) {
            return self.lub_record_type(a, b);
        }
        if matches!(t1, TypeImpl::Record(_)) {
            return self.lub(&object_none, t2);
        }
        if matches!(t2, TypeImpl::Record(_)) {
            return self.lub(t1, &object_none);
        }

        if let Some(result) = self.lub_future_or(t1, t2)? {
            return Ok(result);
        }

        let (Some(i1), Some(i2)) = (t1.as_interface(), t2.as_interface()) else {
            unreachable!("UP of two interface types: {t1:?}, {t2:?}");
        };
        self.interface_lub(i1, i2)
    }

    /// `_typeParameterBound` of an unpromoted type parameter.
    fn type_parameter_bound(&self, element: ElementId) -> TypeImpl {
        self.store
            .element(element)
            .type_
            .clone()
            .unwrap_or_else(|| object_type(self.store, NullabilitySuffix::question))
    }

    /// `_functionType`.
    fn lub_function_type(&mut self, f: &FunctionTypeImpl, g: &FunctionTypeImpl) -> Result<TypeImpl, DepthExceeded> {
        let function = sdk_class(self.store, "dart:core", "Function").expect("dart:core declares Function");
        let function_none = TypeImpl::interface(function, Vec::new(), NullabilitySuffix::none);
        if f.type_parameters.len() != g.type_parameters.len() {
            return Ok(function_none);
        }
        let Some(fresh) = self.relate_type_parameters(&f.type_parameters, &g.type_parameters) else {
            return Ok(function_none);
        };
        let f = instantiate(self.store, f, &fresh);
        let g = instantiate(self.store, g, &fresh);
        let (fp, gp) = (&f.formal_parameters, &g.formal_parameters);
        let mut parameters = Vec::new();
        let (mut fi, mut gi) = (0, 0);
        while fi < fp.len() && gi < gp.len() {
            let (a, b) = (&fp[fi], &gp[gi]);
            if a.is_required_positional() {
                if !b.is_required_positional() {
                    break;
                }
                fi += 1;
                gi += 1;
                let t = self.glb(&a.type_, &b.type_)?;
                parameters.push(a.copy_with(Some(t), None));
            } else if a.is_optional_positional() {
                if !b.is_optional_positional() {
                    break;
                }
                fi += 1;
                gi += 1;
                let t = self.glb(&a.type_, &b.type_)?;
                parameters.push(a.copy_with(Some(t), None));
            } else {
                if !b.is_named() {
                    break;
                }
                let (Some(a_name), Some(b_name)) = (&a.name, &b.name) else {
                    return Ok(function_none);
                };
                match compare_names(a_name, b_name) {
                    std::cmp::Ordering::Equal => {
                        fi += 1;
                        gi += 1;
                        let t = self.glb(&a.type_, &b.type_)?;
                        let kind = if a.is_required_named() || b.is_required_named() {
                            ParameterKind::NAMED_REQUIRED
                        } else {
                            ParameterKind::NAMED
                        };
                        parameters.push(a.copy_with(Some(t), Some(kind)));
                    }
                    std::cmp::Ordering::Less => {
                        if a.is_required_named() {
                            return Ok(function_none);
                        }
                        fi += 1;
                    }
                    std::cmp::Ordering::Greater => {
                        if b.is_required_named() {
                            return Ok(function_none);
                        }
                        gi += 1;
                    }
                }
            }
        }
        // `isRequired`: required positional or required named.
        if fp[fi..].iter().chain(gp[gi..].iter()).any(|p| !p.is_optional()) {
            return Ok(function_none);
        }
        let return_type = self.lub(&f.return_type, &g.return_type)?;
        Ok(TypeImpl::Function(Rc::new(FunctionTypeImpl::new(
            fresh_elements(&fresh),
            parameters,
            return_type,
            NullabilitySuffix::none,
        ))))
    }

    /// `_futureOr`.
    fn lub_future_or(&mut self, t1: &TypeImpl, t2: &TypeImpl) -> Result<Option<TypeImpl>, DepthExceeded> {
        let store = &*self.store;
        let argument = |t: &TypeImpl| t.as_interface().unwrap().type_arguments[0].clone();
        let t1_future_or = is_future_or(store, t1).then(|| argument(t1));
        let t1_future = is_future(store, t1).then(|| argument(t1));
        let t2_future_or = is_future_or(store, t2).then(|| argument(t2));
        let t2_future = is_future(store, t2).then(|| argument(t2));
        let pair = match (t1_future_or, t1_future, t2_future_or, t2_future) {
            (Some(a), _, Some(b), _) => (a, b),
            (_, Some(a), Some(b), _) => (a, b),
            (Some(a), _, _, Some(b)) => (a, b),
            (_, _, Some(b), _) => (t1.clone(), b),
            (Some(a), _, _, _) => (a, t2.clone()),
            _ => return Ok(None),
        };
        let t3 = self.lub(&pair.0, &pair.1)?;
        Ok(Some(future_or_type(self.store, t3)))
    }

    /// `_recordType`.
    fn lub_record_type(&mut self, a: &RecordTypeImpl, b: &RecordTypeImpl) -> Result<TypeImpl, DepthExceeded> {
        let record = sdk_class(self.store, "dart:core", "Record").expect("dart:core declares Record");
        let record_type = TypeImpl::interface(record, Vec::new(), NullabilitySuffix::none);
        if a.positional_fields.len() != b.positional_fields.len() || a.named_fields.len() != b.named_fields.len() {
            return Ok(record_type);
        }
        let mut positional = Vec::with_capacity(a.positional_fields.len());
        for (x, y) in a.positional_fields.iter().zip(&b.positional_fields) {
            positional.push(self.lub(x, y)?);
        }
        let mut named = Vec::with_capacity(a.named_fields.len());
        for ((xn, x), (yn, y)) in a.named_fields.iter().zip(&b.named_fields) {
            if xn != yn {
                return Ok(record_type);
            }
            named.push((xn.clone(), self.lub(x, y)?));
        }
        Ok(TypeImpl::Record(Rc::new(RecordTypeImpl::new(positional, named, NullabilitySuffix::none))))
    }

    /// `InterfaceLeastUpperBoundHelper.compute`.
    fn interface_lub(&mut self, type1: &InterfaceTypeImpl, type2: &InterfaceTypeImpl) -> Result<TypeImpl, DepthExceeded> {
        let nullability = if type1.nullability_suffix == NullabilitySuffix::question
            || type2.nullability_suffix == NullabilitySuffix::question
        {
            NullabilitySuffix::question
        } else {
            NullabilitySuffix::none
        };
        let t1 = TypeImpl::interface(type1.element, type1.type_arguments.clone(), NullabilitySuffix::none);
        let t2 = TypeImpl::interface(type2.element, type2.type_arguments.clone(), NullabilitySuffix::none);
        if self.is_subtype_of(&t1, &t2) {
            return Ok(with_suffix(&t2, nullability));
        }
        if self.is_subtype_of(&t2, &t1) {
            return Ok(with_suffix(&t1, nullability));
        }
        if type1.element == type2.element {
            let first = self.store.element(type1.element).first_fragment;
            let parameters: Vec<ElementId> =
                self.store.fragment(first).type_parameters.iter().map(|&f| self.store.fragment(f).element).collect();
            let mut arguments = Vec::with_capacity(parameters.len());
            for (n, &parameter) in parameters.iter().enumerate() {
                let (a1, a2) = (&type1.type_arguments[n], &type2.type_arguments[n]);
                match self.store.variance(parameter) {
                    Variance::covariant => arguments.push(self.lub(a1, a2)?),
                    Variance::contravariant => arguments.push(self.glb(a1, a2)?),
                    Variance::invariant => {
                        if !self.is_subtype_of(a1, a2) || !self.is_subtype_of(a2, a1) {
                            let result = self.classic_lub(&t1, &t2);
                            return Ok(with_suffix(&result, nullability));
                        }
                        arguments.push(a1.clone());
                    }
                    other => panic!("StateError: unknown variance {other:?} for bounds calculation"),
                }
            }
            return Ok(TypeImpl::interface(type1.element, arguments, nullability));
        }
        let result = self.classic_lub(&t1, &t2);
        Ok(if nullability != NullabilitySuffix::none { with_suffix(&result, nullability) } else { result })
    }

    /// `_computeLeastUpperBound`: the shared superinterface at the unique
    /// greatest depth.
    fn classic_lub(&mut self, i: &TypeImpl, j: &TypeImpl) -> TypeImpl {
        let mut si = superinterface_set(self.store, i);
        let mut sj = superinterface_set(self.store, j);
        add_to_set(self.store, &mut si, i.clone());
        add_to_set(self.store, &mut sj, j.clone());
        let s: Vec<TypeImpl> =
            si.into_iter().filter(|t| sj.iter().any(|u| type_equals(self.store, t, u))).collect();
        type_at_max_unique_depth(self.store, s)
    }
}

/// Adds [t] to [set] unless an equal type is there; whether it was added.
fn add_to_set(store: &ElementStore, set: &mut Vec<TypeImpl>, t: TypeImpl) -> bool {
    if set.iter().any(|u| type_equals(store, u, &t)) {
        return false;
    }
    set.push(t);
    true
}

/// The interfaces, mixins, superclass constraints and superclass of the
/// interface type [t], substituted with its type arguments.
fn super_relations(store: &mut ElementStore, t: &InterfaceTypeImpl) -> Vec<TypeImpl> {
    let substitution = from_interface_type(store, t.element, &t.type_arguments);
    let kind = store.element(t.element).kind;
    let types = store.types(t.element).cloned().unwrap_or_default();
    let mut raw = Vec::new();
    raw.extend(types.interfaces);
    raw.extend(types.mixins);
    if kind == ElementKind::MIXIN {
        raw.extend(types.superclass_constraints);
    }
    if matches!(kind, ElementKind::CLASS | ElementKind::ENUM) {
        raw.extend(store.element(t.element).type_.clone());
    }
    raw.iter().map(|r| substitute(store, &substitution, r)).collect()
}

/// `computeSuperinterfaceSet`.
fn superinterface_set(store: &mut ElementStore, t: &TypeImpl) -> Vec<TypeImpl> {
    let mut set = Vec::new();
    add_superinterfaces(store, &mut set, t);
    set
}

/// `_addSuperinterfaces`.
fn add_superinterfaces(store: &mut ElementStore, set: &mut Vec<TypeImpl>, t: &TypeImpl) {
    let Some(i) = t.as_interface().cloned() else { return };
    let object_none = i.nullability_suffix == NullabilitySuffix::none && store.is_dart_core_class(i.element, "Object");
    if object_none || store.is_dart_core_null(i.element) {
        add_to_set(store, set, object_type(store, NullabilitySuffix::question));
        return;
    }
    if store.element(i.element).kind == ElementKind::EXTENSION_TYPE {
        add_to_set(store, set, object_type(store, NullabilitySuffix::question));
    }
    // Upstream visits interfaces, mixins, constraints, then the superclass.
    for s in super_relations(store, &i) {
        if add_to_set(store, set, s.clone()) {
            add_superinterfaces(store, set, &s);
        }
    }
}

/// `_computeTypeAtMaxUniqueDepth`.
fn type_at_max_unique_depth(store: &ElementStore, types: Vec<TypeImpl>) -> TypeImpl {
    let depths: Vec<usize> = types.iter().map(|t| longest_path_to_object(store, t, &mut Vec::new())).collect();
    let max_depth = depths.iter().copied().max().unwrap_or(0);
    for depth in (0..=max_depth).rev() {
        let at: Vec<usize> = (0..depths.len()).filter(|&m| depths[m] == depth).collect();
        if at.len() == 1 {
            return types[at[0]].clone();
        }
    }
    panic!("StateError: Empty path: {types:?}")
}

/// `_computeLongestInheritancePathToObject`, over the declared supertypes.
fn longest_path_to_object(store: &ElementStore, t: &TypeImpl, visited: &mut Vec<ElementId>) -> usize {
    let Some(i) = t.as_interface() else { return 0 };
    let element = i.element;
    if visited.contains(&element) {
        return 0;
    }
    if store.is_dart_core_null(element) {
        return 1;
    }
    let e = store.element(element);
    if e.kind == ElementKind::CLASS && store.is_dart_core_class(element, "Object") {
        return if i.nullability_suffix == NullabilitySuffix::none { 1 } else { 0 };
    }
    let types = store.types(element).cloned().unwrap_or_default();
    if e.kind == ElementKind::EXTENSION_TYPE && types.interfaces.is_empty() {
        return 1;
    }
    let mut longest = 0;
    visited.push(element);
    if e.kind == ElementKind::MIXIN {
        for s in &types.superclass_constraints {
            longest = longest.max(1 + longest_path_to_object(store, s, visited));
        }
    }
    for s in &types.interfaces {
        longest = longest.max(1 + longest_path_to_object(store, s, visited));
    }
    if e.kind == ElementKind::CLASS {
        if let Some(supertype) = e.type_.clone() {
            let mut super_length = longest_path_to_object(store, &supertype, visited);
            for m in &types.mixins {
                super_length = super_length.max(longest_path_to_object(store, m, visited));
                super_length += 1;
            }
            let first = e.first_fragment;
            if !types.mixins.is_empty() && store.fragment(first).has_flag(FragmentFlag::classFragment_isMixinApplication) {
                super_length -= 1;
            }
            longest = longest.max(1 + super_length);
        }
    }
    visited.pop();
    longest
}
