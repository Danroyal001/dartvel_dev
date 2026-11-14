// Port of lib/src/dart/element/type_constraint_gatherer.dart
// (`TypeConstraintGatherer`) with the generic algorithm it inherits from
// _fe_analyzer_shared's type_analyzer_operations.dart
// (`TypeConstraintGenerator.performSubtypeConstraintGenerationInternal` and
// its helpers) and the constraints of type_constraint.dart
// (`GeneratedTypeConstraint`, `MergedTypeConstraint`), specialized to the
// analyzer's types: the subtype match `P <: Q` with respect to the type
// parameters `L`, which records `_ <: X <: Q` and `P <: X <: _`
// constraints, rewinding them when a match fails.
//
// Not ported: structural context schemas (invocation and member lookup
// contexts, which only expression inference makes), constraint origins
// (error messages) and the data for testing.

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::class_hierarchy::from_interface_type;
use crate::src::dart::element::element::{ElementId, ElementKind};
use crate::src::dart::element::least_greatest_closure::{greatest_closure, least_closure};
use crate::src::dart::element::r#type::{type_equals, FunctionTypeImpl, TypeImpl};
use crate::src::dart::element::subtype::{instantiate, TypeSystem};
use crate::src::dart::element::type_algebra::substitute;
use crate::fe_analyzer_shared::types::shared_type::Variance;
use crate::src::dart::element::type_system::{
    future_type, is_bottom, is_function_class, is_future_or, is_non_nullable, is_null_class, is_nullable,
    is_record_class, null_none, object_type, other_nullability, without_nullability,
};

/// `GeneratedTypeConstraint`: `X <: constraint` (upper) or
/// `constraint <: X` (lower).
#[derive(Clone, Debug)]
pub struct GeneratedTypeConstraint {
    pub type_parameter: ElementId,
    pub constraint: TypeImpl,
    pub is_upper: bool,
}

/// `MergedTypeConstraint`: `lower <: X <: upper`.
#[derive(Clone, Debug)]
pub struct MergedTypeConstraint {
    pub lower: TypeImpl,
    pub upper: TypeImpl,
}

impl MergedTypeConstraint {
    /// `_ <: X <: _`.
    pub fn unknown() -> Self {
        MergedTypeConstraint { lower: TypeImpl::Unknown, upper: TypeImpl::Unknown }
    }

    /// `isEmpty`.
    pub fn is_empty(&self) -> bool {
        matches!(self.lower, TypeImpl::Unknown) && matches!(self.upper, TypeImpl::Unknown)
    }

    /// `isSatisfiedBy`.
    pub fn is_satisfied_by(&self, ts: &mut TypeSystem<'_>, t: &TypeImpl) -> bool {
        ts.is_subtype_of(t, &self.upper) && ts.is_subtype_of(&self.lower, t)
    }

    /// `mergeIn`: the upper meets, the lower joins.
    pub fn merge_in(&mut self, ts: &mut TypeSystem<'_>, constraint: &GeneratedTypeConstraint) {
        if constraint.is_upper {
            self.upper = ts.greatest_lower_bound(&self.upper, &constraint.constraint);
        } else {
            self.lower = ts.least_upper_bound(&self.lower, &constraint.constraint);
        }
    }
}

/// `TypeConstraintGatherer`.
pub struct TypeConstraintGatherer<'s, 'a> {
    pub ts: &'s mut TypeSystem<'a>,
    /// `typeParametersToConstrain`.
    type_parameters: Vec<ElementId>,
    constraints: Vec<GeneratedTypeConstraint>,
    inference_using_bounds: bool,
}

/// The declaration a type is an instance of, as
/// `matchTypeDeclarationTypeInternal` sees it.
struct TypeDeclarationMatch {
    is_extension_type: bool,
    declaration: ElementId,
    type_arguments: Vec<TypeImpl>,
}

impl<'s, 'a> TypeConstraintGatherer<'s, 'a> {
    pub fn new(ts: &'s mut TypeSystem<'a>, type_parameters: Vec<ElementId>, inference_using_bounds: bool) -> Self {
        TypeConstraintGatherer { ts, type_parameters, constraints: Vec::new(), inference_using_bounds }
    }

    /// `currentState`.
    fn state(&self) -> usize {
        self.constraints.len()
    }

    /// `restoreState`.
    fn restore(&mut self, state: usize) {
        self.constraints.truncate(state);
    }

    fn add_lower(&mut self, parameter: ElementId, lower: TypeImpl) {
        self.constraints.push(GeneratedTypeConstraint { type_parameter: parameter, constraint: lower, is_upper: false });
    }

    fn add_upper(&mut self, parameter: ElementId, upper: TypeImpl) {
        self.constraints.push(GeneratedTypeConstraint { type_parameter: parameter, constraint: upper, is_upper: true });
    }

    /// `computeConstraints`: one merged constraint per type parameter, in
    /// the order of the type parameters.
    pub fn compute_constraints(&mut self) -> Vec<(ElementId, MergedTypeConstraint)> {
        let mut result: Vec<(ElementId, MergedTypeConstraint)> =
            self.type_parameters.iter().map(|&p| (p, MergedTypeConstraint::unknown())).collect();
        for constraint in std::mem::take(&mut self.constraints) {
            let entry = result.iter_mut().find(|(p, _)| *p == constraint.type_parameter).unwrap();
            entry.1.merge_in(self.ts, &constraint);
        }
        result
    }

    /// `eliminateTypeParametersInGeneratedConstraints`.
    fn eliminate_type_parameters(&mut self, eliminator: &[ElementId], start: usize) {
        let constraints = self.constraints.split_off(start);
        for constraint in constraints {
            if constraint.is_upper {
                let t = least_closure(self.ts.store, &constraint.constraint, eliminator);
                self.add_upper(constraint.type_parameter, t);
            } else {
                let t = greatest_closure(self.ts.store, &constraint.constraint, eliminator);
                self.add_lower(constraint.type_parameter, t);
            }
        }
    }

    fn is_question(t: &TypeImpl) -> bool {
        other_nullability(t) == NullabilitySuffix::question
    }

    /// `matchTypeDeclarationTypeInternal`.
    fn match_type_declaration(&self, t: &TypeImpl) -> Option<TypeDeclarationMatch> {
        let i = t.as_interface()?;
        let store = &*self.ts.store;
        let is_extension_type = store.element(i.element).kind == ElementKind::EXTENSION_TYPE;
        if !is_extension_type && (is_null_class(store, t) || is_future_or(store, t)) {
            return None;
        }
        Some(TypeDeclarationMatch { is_extension_type, declaration: i.element, type_arguments: i.type_arguments.clone() })
    }

    /// `performSubtypeConstraintGenerationInternal`.
    pub fn perform_subtype_constraint_generation(&mut self, p: &TypeImpl, q: &TypeImpl, left_schema: bool) -> bool {
        if matches!(p, TypeImpl::Unknown) || matches!(q, TypeImpl::Unknown) {
            return true;
        }
        // `P` is a type variable `X` in `L`: `_ <: X <: Q`.
        if let TypeImpl::TypeParameter(pp) = p {
            if !Self::is_question(p) && self.type_parameters.contains(&pp.element) {
                self.add_upper(pp.element, q.clone());
                return true;
            }
        }
        // `Q` is a type variable `X` in `L`: `P <: X <: _`.
        if let TypeImpl::TypeParameter(qp) = q {
            if !Self::is_question(q) && self.type_parameters.contains(&qp.element) {
                let within_bound = !self.inference_using_bounds
                    || match self.ts.store.element(qp.element).type_.clone() {
                        None => true,
                        Some(bound) => {
                            let closure = greatest_closure(self.ts.store, &bound, &self.type_parameters.clone());
                            self.ts.is_subtype_of(p, &closure)
                        }
                    };
                if within_bound {
                    self.add_lower(qp.element, p.clone());
                    return true;
                }
            }
        }
        if type_equals(self.ts.store, p, q) {
            return true;
        }

        if self.right_future_or(p, q, left_schema)
            || self.right_nullable(p, q, left_schema)
            || self.left_future_or(p, q, left_schema)
            || self.left_nullable(p, q, left_schema)
        {
            return true;
        }

        let store = &*self.ts.store;
        if matches!(q, TypeImpl::Dynamic | TypeImpl::Void)
            || type_equals(store, q, &object_type(store, NullabilitySuffix::question))
        {
            return true;
        }
        if is_bottom(store, p) {
            return true;
        }
        if type_equals(store, q, &object_type(store, NullabilitySuffix::none)) {
            return is_non_nullable(store, p);
        }
        if is_null_class(store, p) {
            return is_nullable(store, q);
        }
        // `P` is a type variable with bound `B` (or `X & B`): match `B`.
        if let TypeImpl::TypeParameter(pp) = p {
            if pp.nullability_suffix == NullabilitySuffix::none {
                let bound = match &pp.promoted_bound {
                    Some(b) => Some((**b).clone()),
                    None => store.element(pp.element).type_.clone(),
                };
                if let Some(bound) = bound {
                    if self.perform_subtype_constraint_generation(&bound, q, left_schema) {
                        return true;
                    }
                }
            }
        }

        if let Some(result) = self.type_declaration_types(p, q, left_schema) {
            return result;
        }

        if is_function_class(self.ts.store, q) && matches!(p, TypeImpl::Function(_)) {
            return true;
        }
        if let (TypeImpl::Function(f), TypeImpl::Function(g)) = (p, q) {
            let (f, g) = (f.clone(), g.clone());
            let matched = if f.type_parameters.is_empty() && g.type_parameters.is_empty() {
                self.non_generic_function_types(&f, &g, left_schema)
            } else {
                self.generic_function_types(&f, &g, left_schema)
            };
            if matched {
                return true;
            }
        }
        if is_record_class(self.ts.store, q) && matches!(p, TypeImpl::Record(_)) {
            return true;
        }
        if let (TypeImpl::Record(a), TypeImpl::Record(b)) = (p, q) {
            if a.positional_fields.len() != b.positional_fields.len() || a.named_fields.len() != b.named_fields.len() {
                return false;
            }
            let state = self.state();
            for (x, y) in a.positional_fields.iter().zip(&b.positional_fields) {
                if !self.perform_subtype_constraint_generation(x, y, left_schema) {
                    self.restore(state);
                    return false;
                }
            }
            for ((xn, x), (yn, y)) in a.named_fields.iter().zip(&b.named_fields) {
                if xn != yn || !self.perform_subtype_constraint_generation(x, y, left_schema) {
                    self.restore(state);
                    return false;
                }
            }
            return true;
        }
        false
    }

    /// `performSubtypeConstraintGenerationForRightFutureOr`.
    fn right_future_or(&mut self, p: &TypeImpl, q: &TypeImpl, left_schema: bool) -> bool {
        if !is_future_or(self.ts.store, q) || Self::is_question(q) {
            return false;
        }
        let q0 = q.as_interface().unwrap().type_arguments[0].clone();
        let state = self.state();
        if is_future_or(self.ts.store, p) && !Self::is_question(p) {
            let p0 = p.as_interface().unwrap().type_arguments[0].clone();
            if self.perform_subtype_constraint_generation(&p0, &q0, left_schema) {
                return true;
            }
        }
        let future_q0 = future_type(self.ts.store, q0.clone());
        let is_match_with_future = self.perform_subtype_constraint_generation(p, &future_q0, left_schema);
        let match_with_future_adds_constraints = self.state() != state;
        if is_match_with_future && match_with_future_adds_constraints {
            return true;
        }
        if self.perform_subtype_constraint_generation(p, &q0, left_schema) {
            return true;
        }
        is_match_with_future && !match_with_future_adds_constraints
    }

    /// `performSubtypeConstraintGenerationForRightNullableType`.
    fn right_nullable(&mut self, p: &TypeImpl, q: &TypeImpl, left_schema: bool) -> bool {
        if !Self::is_question(q) {
            return false;
        }
        let q0 = without_nullability(q);
        let state = self.state();
        if Self::is_question(p) {
            let p0 = without_nullability(p);
            if self.perform_subtype_constraint_generation(&p0, &q0, left_schema) {
                return true;
            }
        }
        if matches!(p, TypeImpl::Dynamic | TypeImpl::Void) {
            let object_none = object_type(self.ts.store, NullabilitySuffix::none);
            if self.perform_subtype_constraint_generation(&object_none, &q0, left_schema) {
                return true;
            }
        }
        let p_matches_q0 = self.perform_subtype_constraint_generation(p, &q0, left_schema);
        if p_matches_q0 && state != self.state() {
            return true;
        }
        let null = null_none(self.ts.store);
        if self.perform_subtype_constraint_generation(p, &null, left_schema) {
            return true;
        }
        p_matches_q0
    }

    /// `performSubtypeConstraintGenerationForLeftFutureOr`.
    fn left_future_or(&mut self, p: &TypeImpl, q: &TypeImpl, left_schema: bool) -> bool {
        if !is_future_or(self.ts.store, p) || Self::is_question(p) {
            return false;
        }
        let p0 = p.as_interface().unwrap().type_arguments[0].clone();
        let state = self.state();
        let future_p0 = future_type(self.ts.store, p0.clone());
        if self.perform_subtype_constraint_generation(&future_p0, q, left_schema)
            && self.perform_subtype_constraint_generation(&p0, q, left_schema)
        {
            return true;
        }
        self.restore(state);
        false
    }

    /// `performSubtypeConstraintGenerationForLeftNullableType`.
    fn left_nullable(&mut self, p: &TypeImpl, q: &TypeImpl, left_schema: bool) -> bool {
        if !Self::is_question(p) {
            return false;
        }
        let p0 = without_nullability(p);
        let state = self.state();
        let null = null_none(self.ts.store);
        if self.perform_subtype_constraint_generation(&p0, q, left_schema)
            && self.perform_subtype_constraint_generation(&null, q, left_schema)
        {
            return true;
        }
        self.restore(state);
        false
    }

    /// `performSubtypeConstraintGenerationForTypeDeclarationTypes`.
    fn type_declaration_types(&mut self, p: &TypeImpl, q: &TypeImpl, left_schema: bool) -> Option<bool> {
        let (pm, qm) = (self.match_type_declaration(p)?, self.match_type_declaration(q)?);
        if pm.is_extension_type == qm.is_extension_type && pm.declaration == qm.declaration {
            return Some(self.interface_type_arguments(pm.declaration, &pm.type_arguments, &qm.type_arguments, left_schema));
        }
        Some(self.interface_types(p, q, left_schema))
    }

    /// `_interfaceTypeArguments`.
    fn interface_type_arguments(
        &mut self,
        declaration: ElementId,
        p_arguments: &[TypeImpl],
        q_arguments: &[TypeImpl],
        left_schema: bool,
    ) -> bool {
        let state = self.state();
        let first = self.ts.store.element(declaration).first_fragment;
        let parameters: Vec<ElementId> =
            self.ts.store.fragment(first).type_parameters.iter().map(|&f| self.ts.store.fragment(f).element).collect();
        for (n, (m, k)) in p_arguments.iter().zip(q_arguments).enumerate() {
            let variance = parameters.get(n).map(|&p| self.ts.store.variance(p)).unwrap_or(Variance::covariant);
            if matches!(variance, Variance::covariant | Variance::invariant)
                && !self.perform_subtype_constraint_generation(m, k, left_schema)
            {
                self.restore(state);
                return false;
            }
            if matches!(variance, Variance::contravariant | Variance::invariant)
                && !self.perform_subtype_constraint_generation(k, m, !left_schema)
            {
                self.restore(state);
                return false;
            }
        }
        true
    }

    /// `_interfaceTypes`.
    fn interface_types(&mut self, p: &TypeImpl, q: &TypeImpl, left_schema: bool) -> bool {
        if Self::is_question(p) || Self::is_question(q) {
            return false;
        }
        let (Some(pi), Some(qm)) = (p.as_interface().cloned(), self.match_type_declaration(q)) else {
            return false;
        };
        // `getTypeArgumentsAsInstanceOf`.
        let supertypes = self.ts.hierarchy.implemented_interfaces(self.ts.store, pi.element);
        let Some(interface) = supertypes.iter().find(|t| t.as_interface().is_some_and(|i| i.element == qm.declaration))
        else {
            return false;
        };
        let substitution = from_interface_type(self.ts.store, pi.element, &pi.type_arguments);
        let instance = substitute(self.ts.store, &substitution, interface);
        let arguments = instance.as_interface().unwrap().type_arguments.clone();
        self.interface_type_arguments(qm.declaration, &arguments, &qm.type_arguments, left_schema)
    }

    /// `_handleNonGenericFunctionTypes`.
    fn non_generic_function_types(&mut self, p: &FunctionTypeImpl, q: &FunctionTypeImpl, left_schema: bool) -> bool {
        let positional = |f: &FunctionTypeImpl| -> Vec<TypeImpl> {
            f.formal_parameters.iter().filter(|x| x.is_positional()).map(|x| x.type_.clone()).collect()
        };
        let required = |f: &FunctionTypeImpl| f.formal_parameters.iter().filter(|x| x.is_required_positional()).count();
        let named = |f: &FunctionTypeImpl| -> Vec<_> { f.formal_parameters.iter().filter(|x| x.is_named()).cloned().collect() };
        let (p_positional, q_positional) = (positional(p), positional(q));
        let (p_named, q_named) = (named(p), named(q));
        if p_named.is_empty()
            && q_named.is_empty()
            && required(p) <= required(q)
            && p_positional.len() >= q_positional.len()
        {
            let state = self.state();
            if !self.perform_subtype_constraint_generation(&p.return_type, &q.return_type, left_schema) {
                return false;
            }
            for i in 0..q_positional.len() {
                if !self.perform_subtype_constraint_generation(&q_positional[i], &p_positional[i], !left_schema) {
                    self.restore(state);
                    return false;
                }
            }
            return true;
        }
        if p_positional.len() == required(p)
            && q_positional.len() == required(q)
            && required(p) == required(q)
            && !p_named.is_empty()
            && q_named.len() <= p_named.len()
        {
            let state = self.state();
            if !self.perform_subtype_constraint_generation(&p.return_type, &q.return_type, left_schema) {
                return false;
            }
            for i in 0..p_positional.len() {
                if !self.perform_subtype_constraint_generation(&q_positional[i], &p_positional[i], !left_schema) {
                    self.restore(state);
                    return false;
                }
            }
            let (mut i, mut j) = (0, 0);
            loop {
                let comparison = if i >= p_named.len() {
                    if j >= q_named.len() {
                        return true;
                    }
                    std::cmp::Ordering::Greater
                } else if j >= q_named.len() {
                    std::cmp::Ordering::Less
                } else {
                    crate::src::dart::element::type_system::compare_names(
                        p_named[i].name.as_deref().unwrap_or(""),
                        q_named[j].name.as_deref().unwrap_or(""),
                    )
                };
                match comparison {
                    std::cmp::Ordering::Greater => {
                        self.restore(state);
                        return false;
                    }
                    std::cmp::Ordering::Less => {
                        if p_named[i].is_required_named() {
                            self.restore(state);
                            return false;
                        }
                        i += 1;
                    }
                    std::cmp::Ordering::Equal => {
                        if !self.perform_subtype_constraint_generation(&q_named[j].type_, &p_named[i].type_, !left_schema) {
                            self.restore(state);
                            return false;
                        }
                        i += 1;
                        j += 1;
                    }
                }
            }
        }
        false
    }

    /// `_handleGenericFunctionTypes`.
    fn generic_function_types(&mut self, p: &FunctionTypeImpl, q: &FunctionTypeImpl, left_schema: bool) -> bool {
        if p.type_parameters.len() != q.type_parameters.len() {
            return false;
        }
        let state = self.state();
        let object_q = object_type(self.ts.store, NullabilitySuffix::question);
        let bound = |ts: &TypeSystem<'_>, e: ElementId| ts.store.element(e).type_.clone().unwrap_or_else(|| object_q.clone());
        let mut is_match = true;
        for i in 0..p.type_parameters.len() {
            if !is_match {
                break;
            }
            let (pb, qb) = (bound(self.ts, p.type_parameters[i]), bound(self.ts, q.type_parameters[i]));
            is_match = self.perform_subtype_constraint_generation(&pb, &qb, left_schema)
                && self.perform_subtype_constraint_generation(&qb, &pb, !left_schema);
        }
        if is_match {
            // `instantiateFunctionTypesAndProvideFreshTypeParameters`: fresh
            // `Z0..Zn` with the bounds of the schema side.
            let source = if left_schema { &p.type_parameters } else { &q.type_parameters };
            let mut fresh = Vec::with_capacity(source.len());
            for (n, &e) in source.iter().enumerate() {
                let library = self.ts.store.element(e).library;
                let z = self.ts.store.add_synthetic_type_parameter(Some(format!("Z{n}").into()), library);
                self.ts.store.elements[z as usize].type_ = self.ts.store.element(e).type_.clone();
                fresh.push(z);
            }
            let arguments: Vec<TypeImpl> = fresh.iter().map(|&z| TypeImpl::type_parameter(z, NullabilitySuffix::none)).collect();
            let p_instantiated = TypeImpl::Function(std::rc::Rc::new(instantiate(self.ts.store, p, &arguments)));
            let q_instantiated = TypeImpl::Function(std::rc::Rc::new(instantiate(self.ts.store, q, &arguments)));
            if self.perform_subtype_constraint_generation(&p_instantiated, &q_instantiated, left_schema) {
                self.eliminate_type_parameters(&fresh, state);
                return true;
            }
        }
        self.restore(state);
        false
    }
}
