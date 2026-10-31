// Port of lib/src/dart/element/generic_inferrer.dart (`GenericInferrer`),
// with what its final choice uses: _fe_analyzer_shared's `chooseTypes`,
// `inferTypeParameterFromAll`, `chooseTypeFromConstraint` and
// `mergeInConstraintsFromBound` (type_analyzer_operations.dart), and
// `TypeSystemImpl.instantiateTypeFormalsToBounds`, `getFreeParameters`,
// `demoteType`, `matchSupertypeConstraints` and
// `gatherMixinSupertypeConstraintsForInference` (type_system.dart).
//
// Not ported: downwards and horizontal inference (`choosePreliminaryTypes`,
// argument constraints, generic function instantiation), which only
// expression inference uses, and error reporting: inference here runs
// without a diagnostic reporter, as the linker's does.

use std::rc::Rc;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::fe_analyzer_shared::types::shared_type::Variance;
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore, FragmentFlag};
use crate::src::dart::element::r#type::{type_equals, FunctionTypeImpl, TypeImpl};
use crate::src::dart::element::subtype::TypeSystem;
use crate::src::dart::element::type_algebra::{substitute, Substitution};
use crate::src::dart::element::type_constraint_gatherer::{MergedTypeConstraint, TypeConstraintGatherer};
use crate::src::dart::element::type_schema_elimination::{greatest_closure_of_schema, least_closure_of_schema};

/// `GenericInferrer`.
pub struct GenericInferrer<'s, 'a> {
    pub ts: &'s mut TypeSystem<'a>,
    type_formals: Vec<ElementId>,
    /// `_constraints`: the constraints each match added, per type formal.
    constraints: Vec<Vec<MergedTypeConstraint>>,
    inference_using_bounds: bool,
}

impl<'s, 'a> GenericInferrer<'s, 'a> {
    pub fn new(ts: &'s mut TypeSystem<'a>, type_formals: Vec<ElementId>, inference_using_bounds: bool) -> Self {
        let constraints = type_formals.iter().map(|_| Vec::new()).collect();
        GenericInferrer { ts, type_formals, constraints, inference_using_bounds }
    }

    /// `constrainReturnType`: [declared] is a subtype of [context].
    pub fn constrain_return_type(&mut self, declared: &TypeImpl, context: &TypeImpl) {
        self.try_match_subtype_of(declared, context, true);
    }

    /// `_tryMatchSubtypeOf`. `_typesInferredSoFar` is all `_` until a
    /// preliminary phase fixes some, and none runs here.
    fn try_match_subtype_of(&mut self, t1: &TypeImpl, t2: &TypeImpl, covariant: bool) -> bool {
        let mut gatherer = TypeConstraintGatherer::new(self.ts, self.type_formals.clone(), self.inference_using_bounds);
        let success = gatherer.perform_subtype_constraint_generation(t1, t2, !covariant);
        if success {
            let constraints = gatherer.compute_constraints();
            for (n, (_, constraint)) in constraints.into_iter().enumerate() {
                if !constraint.is_empty() {
                    self.constraints[n].push(constraint);
                }
            }
        }
        success
    }

    /// `chooseFinalTypes`.
    pub fn choose_final_types(&mut self) -> Vec<TypeImpl> {
        self.try_choose_final_types(false).expect("error recovery always chooses")
    }

    /// `tryChooseFinalTypes`.
    pub fn try_choose_final_types(&mut self, fail_at_error: bool) -> Option<Vec<TypeImpl>> {
        let mut phase_constraints: Vec<MergedTypeConstraint> =
            (0..self.type_formals.len()).map(|n| self.squash_constraints(n)).collect();
        let inferred = self.choose_types(&mut phase_constraints);

        let mut known_types: Vec<(ElementId, TypeImpl)> = Vec::new();
        for n in 0..self.type_formals.len() {
            let parameter = self.type_formals[n];
            let t = inferred[n].clone();
            let mut success = self.constraints[n].clone().iter().all(|c| c.is_satisfied_by(self.ts, &t));
            if success {
                let has_name = self.ts.store.element(parameter).name.is_some();
                if let (true, Some(bound)) = (has_name, self.ts.store.element(parameter).type_.clone()) {
                    let substitution = Substitution::from_pairs(self.type_formals.clone(), inferred.clone());
                    let extends = substitute(self.ts.store, &substitution, &bound);
                    let constraint = MergedTypeConstraint { lower: TypeImpl::Unknown, upper: extends };
                    success = constraint.is_satisfied_by(self.ts, &t);
                    self.constraints[n].push(constraint);
                }
            }
            if !success {
                if fail_at_error {
                    return None;
                }
                if self.ts.store.element(parameter).name.is_none() {
                    return None;
                }
                // Heuristic: even if we failed, keep the erroneous type.
            }
            if is_known(&t) {
                known_types.push((parameter, t));
            }
        }

        let (mut result, has_error) = instantiate_type_formals_to_bounds(self.ts.store, &self.type_formals, &known_types);
        if has_error {
            if fail_at_error {
                return None;
            }
            if self.ts.store.element(self.type_formals[0]).name.is_none() {
                return None;
            }
        }
        for t in &mut result {
            *t = demote_type(t);
        }
        Some(result)
    }

    /// `_squashConstraints`: LUB of the lowers, GLB of the uppers.
    fn squash_constraints(&mut self, n: usize) -> MergedTypeConstraint {
        let mut lower = TypeImpl::Unknown;
        let mut upper = TypeImpl::Unknown;
        for constraint in self.constraints[n].clone() {
            upper = self.ts.greatest_lower_bound(&upper, &constraint.upper);
            lower = self.ts.least_upper_bound(&lower, &constraint.lower);
        }
        MergedTypeConstraint { lower, upper }
    }

    /// `chooseTypes` with `preliminary: false` and no previously inferred
    /// types.
    fn choose_types(&mut self, constraints: &mut [MergedTypeConstraint]) -> Vec<TypeImpl> {
        let formals = self.type_formals.clone();
        let mut inferred = vec![TypeImpl::Unknown; formals.len()];
        for n in 0..formals.len() {
            let parameter = formals[n];
            let bound = self.ts.store.element(parameter).type_.clone();
            // `isBoundOmitted`: no bound.
            let extends_constraint = bound.as_ref().map(|b| {
                let substitution = Substitution::from_pairs(formals.clone(), inferred.clone());
                substitute(self.ts.store, &substitution, b)
            });
            let is_contravariant = self.ts.store.variance(parameter) == Variance::contravariant;
            inferred[n] = self.infer_type_parameter_from_all(n, constraints, extends_constraint, is_contravariant);
        }
        inferred
    }

    /// `inferTypeParameterFromAll`.
    fn infer_type_parameter_from_all(
        &mut self,
        n: usize,
        constraints: &mut [MergedTypeConstraint],
        extends_constraint: Option<TypeImpl>,
        is_contravariant: bool,
    ) -> TypeImpl {
        let parameter = self.type_formals[n];
        let bound = self.ts.store.element(parameter).type_.clone();
        if let (true, false, Some(bound)) =
            (self.inference_using_bounds, matches!(constraints[n].lower, TypeImpl::Unknown), bound)
        {
            let lower = constraints[n].lower.clone();
            let from_bound = self.merge_in_constraints_from_bound(n, &lower, &bound, constraints);
            let mut constraint = constraints[n].clone();
            constraint.upper = self.ts.greatest_lower_bound(&constraint.upper, &from_bound.upper);
            constraint.lower = self.ts.least_upper_bound(&constraint.lower, &from_bound.lower);
            constraints[n] = constraint;
        }
        let mut constraint = constraints[n].clone();
        if let Some(extends) = extends_constraint {
            constraint.upper = self.ts.greatest_lower_bound(&constraint.upper, &extends);
        }
        choose_type_from_constraint(self.ts.store, &constraint, true, is_contravariant)
    }

    /// `mergeInConstraintsFromBound`: matches [lower] against the bound of
    /// type formal [n], merging what that adds into [constraints].
    fn merge_in_constraints_from_bound(
        &mut self,
        n: usize,
        lower: &TypeImpl,
        bound: &TypeImpl,
        constraints: &mut [MergedTypeConstraint],
    ) -> MergedTypeConstraint {
        let mut gatherer = TypeConstraintGatherer::new(self.ts, self.type_formals.clone(), self.inference_using_bounds);
        gatherer.perform_subtype_constraint_generation(lower, bound, true);
        let per_variable = gatherer.compute_constraints();
        for (m, (_, constraint)) in per_variable.iter().enumerate() {
            if !constraint.is_empty() {
                let upper = self.ts.greatest_lower_bound(&constraints[m].upper, &constraint.upper);
                let lower = self.ts.least_upper_bound(&constraints[m].lower, &constraint.lower);
                constraints[m] = MergedTypeConstraint { lower, upper };
            }
        }
        per_variable[n].1.clone()
    }
}

/// `chooseTypeFromConstraint`.
pub fn choose_type_from_constraint(
    store: &ElementStore,
    constraint: &MergedTypeConstraint,
    grounded: bool,
    is_contravariant: bool,
) -> TypeImpl {
    let (lower, upper) = (&constraint.lower, &constraint.upper);
    let from_lower = || if grounded { least_closure_of_schema(store, lower) } else { lower.clone() };
    let from_upper = || if grounded { greatest_closure_of_schema(store, upper) } else { upper.clone() };
    if !is_contravariant {
        if is_known(lower) {
            return lower.clone();
        }
        if is_known(upper) {
            return upper.clone();
        }
        if !matches!(lower, TypeImpl::Unknown) {
            return from_lower();
        }
        if !matches!(upper, TypeImpl::Unknown) {
            return from_upper();
        }
        lower.clone()
    } else {
        if is_known(upper) {
            return upper.clone();
        }
        if is_known(lower) {
            return lower.clone();
        }
        if !matches!(upper, TypeImpl::Unknown) {
            return from_upper();
        }
        if !matches!(lower, TypeImpl::Unknown) {
            return from_lower();
        }
        upper.clone()
    }
}

/// `UnknownInferredType.isKnown`: no `_` anywhere in [t].
pub fn is_known(t: &TypeImpl) -> bool {
    !is_unknown(t)
}

/// `UnknownInferredType.isUnknown`.
fn is_unknown(t: &TypeImpl) -> bool {
    match t {
        TypeImpl::Unknown => true,
        TypeImpl::Interface(i) => i.type_arguments.iter().any(is_unknown),
        // Bounds of generic function types never hold `_` here.
        TypeImpl::Function(f) => is_unknown(&f.return_type) || f.formal_parameters.iter().any(|p| is_unknown(&p.type_)),
        TypeImpl::Record(r) => r.positional_fields.iter().any(is_unknown) || r.named_fields.iter().any(|(_, f)| is_unknown(f)),
        _ => false,
    }
}

/// `demoteType` (`DemotionVisitor`): promoted type variables lose their
/// promoted bounds.
pub fn demote_type(t: &TypeImpl) -> TypeImpl {
    demote(t).unwrap_or_else(|| t.clone())
}

fn demote(t: &TypeImpl) -> Option<TypeImpl> {
    match t {
        TypeImpl::TypeParameter(p) => {
            p.promoted_bound.as_ref()?;
            Some(TypeImpl::type_parameter(p.element, p.nullability_suffix))
        }
        TypeImpl::Interface(i) => {
            let arguments = demote_list(&i.type_arguments)?;
            Some(TypeImpl::interface(i.element, arguments, i.nullability_suffix))
        }
        TypeImpl::Record(r) => {
            let positional = demote_list(&r.positional_fields);
            let named_types: Vec<TypeImpl> = r.named_fields.iter().map(|(_, f)| f.clone()).collect();
            let named = demote_list(&named_types);
            if positional.is_none() && named.is_none() {
                return None;
            }
            let named = named
                .map(|types| r.named_fields.iter().zip(types).map(|((name, _), t)| (name.clone(), t)).collect())
                .unwrap_or_else(|| r.named_fields.clone());
            Some(TypeImpl::Record(Rc::new(crate::src::dart::element::r#type::RecordTypeImpl::new(
                positional.unwrap_or_else(|| r.positional_fields.clone()),
                named,
                r.nullability_suffix,
            ))))
        }
        TypeImpl::Function(f) => {
            let return_type = demote(&f.return_type);
            let parameter_types: Vec<TypeImpl> = f.formal_parameters.iter().map(|p| p.type_.clone()).collect();
            let parameters = demote_list(&parameter_types);
            if return_type.is_none() && parameters.is_none() {
                return None;
            }
            let formal_parameters = match parameters {
                Some(types) => f.formal_parameters.iter().zip(types).map(|(p, t)| p.copy_with(Some(t), None)).collect(),
                None => f.formal_parameters.clone(),
            };
            Some(TypeImpl::Function(Rc::new(FunctionTypeImpl {
                type_parameters: f.type_parameters.clone(),
                formal_parameters,
                return_type: return_type.unwrap_or_else(|| f.return_type.clone()),
                nullability_suffix: f.nullability_suffix,
            })))
        }
        _ => None,
    }
}

fn demote_list(types: &[TypeImpl]) -> Option<Vec<TypeImpl>> {
    let mut result: Option<Vec<TypeImpl>> = None;
    for (n, t) in types.iter().enumerate() {
        if let Some(new_type) = demote(t) {
            result.get_or_insert_with(|| types.to_vec())[n] = new_type;
        }
    }
    result
}

/// `getFreeParameters` with `candidates`: the type parameters among
/// [candidates] that [t] mentions outside the generic function types that
/// bind them, in the order met; `None` when there are none.
pub fn free_parameters(t: &TypeImpl, candidates: &[ElementId]) -> Option<Vec<ElementId>> {
    fn append(t: &TypeImpl, candidates: &[ElementId], bound: &mut Vec<ElementId>, out: &mut Vec<ElementId>) {
        match t {
            TypeImpl::TypeParameter(p) => {
                if candidates.contains(&p.element) && !bound.contains(&p.element) {
                    out.push(p.element);
                }
            }
            TypeImpl::Function(f) => {
                let depth = bound.len();
                bound.extend(&f.type_parameters);
                append(&f.return_type, candidates, bound, out);
                for p in &f.formal_parameters {
                    append(&p.type_, candidates, bound, out);
                }
                bound.truncate(depth);
            }
            TypeImpl::Interface(i) => i.type_arguments.iter().for_each(|a| append(a, candidates, bound, out)),
            TypeImpl::Record(r) => {
                r.positional_fields.iter().for_each(|f| append(f, candidates, bound, out));
                r.named_fields.iter().for_each(|(_, f)| append(f, candidates, bound, out));
            }
            _ => {}
        }
    }
    let mut out = Vec::new();
    append(t, candidates, &mut Vec::new(), &mut out);
    (!out.is_empty()).then_some(out)
}

/// `instantiateTypeFormalsToBounds` with `knownTypes`: the defaults, and
/// whether a bound never became ground (`hasError[0]`).
pub fn instantiate_type_formals_to_bounds(
    store: &mut ElementStore,
    type_parameters: &[ElementId],
    known_types: &[(ElementId, TypeImpl)],
) -> (Vec<TypeImpl>, bool) {
    if type_parameters.is_empty() {
        return (Vec::new(), false);
    }
    let mut defaults: Vec<(ElementId, TypeImpl)> = known_types.to_vec();
    let mut partials: Vec<(ElementId, TypeImpl)> = Vec::new();
    for &p in type_parameters {
        if !defaults.iter().any(|(d, _)| *d == p) {
            partials.push((p, store.element(p).type_.clone().unwrap_or(TypeImpl::Dynamic)));
        }
    }
    let mut has_progress = true;
    while has_progress {
        has_progress = false;
        for n in 0..partials.len() {
            let (parameter, value) = partials[n].clone();
            match free_parameters(&value, type_parameters) {
                None => {
                    defaults.push((parameter, value));
                    partials.remove(n);
                    has_progress = true;
                    break;
                }
                Some(free) if free.iter().all(|f| defaults.iter().any(|(d, _)| d == f)) => {
                    let substitution = Substitution { map: defaults.clone() };
                    let t = substitute(store, &substitution, &value);
                    defaults.push((parameter, t));
                    partials.remove(n);
                    has_progress = true;
                    break;
                }
                Some(_) => {}
            }
        }
    }
    let has_error = !partials.is_empty();
    if has_error {
        let mut map = defaults.clone();
        map.extend(partials.iter().map(|(p, _)| (*p, TypeImpl::Dynamic)));
        let substitution = Substitution { map };
        for (parameter, value) in &partials {
            let t = substitute(store, &substitution, value);
            defaults.push((*parameter, t));
        }
    }
    let ordered = type_parameters
        .iter()
        .map(|p| defaults.iter().rev().find(|(d, _)| d == p).unwrap().1.clone())
        .collect();
    (ordered, has_error)
}

/// `TypeSystemImpl.matchSupertypeConstraints`: the arguments for
/// [type_parameters] that make each of [src_types] equal to the
/// corresponding [dest_types], or `None`.
pub fn match_supertype_constraints(
    ts: &mut TypeSystem<'_>,
    type_parameters: &[ElementId],
    src_types: &[TypeImpl],
    dest_types: &[TypeImpl],
    inference_using_bounds: bool,
) -> Option<Vec<TypeImpl>> {
    let mut inferrer = GenericInferrer::new(ts, type_parameters.to_vec(), inference_using_bounds);
    for (src, dest) in src_types.iter().zip(dest_types) {
        inferrer.constrain_return_type(src, dest);
        inferrer.constrain_return_type(dest, src);
    }
    let inferred: Vec<TypeImpl> = inferrer
        .choose_final_types()
        .iter()
        .map(|t| remove_bounds_of_generic_function_types(ts.store, t))
        .collect();
    let substitution = Substitution::from_pairs(type_parameters.to_vec(), inferred.clone());
    for (src, dest) in src_types.iter().zip(dest_types) {
        let src = substitute(ts.store, &substitution, src);
        if !type_equals(ts.store, &src, dest) {
            return None;
        }
    }
    Some(inferred)
}

/// `_removeBoundsOfGenericFunctionTypes`: every bounded type parameter of a
/// generic function type in [t] is replaced by a fresh one bounded by
/// `Never`.
pub fn remove_bounds_of_generic_function_types(store: &mut ElementStore, t: &TypeImpl) -> TypeImpl {
    remove_bounds(store, t).unwrap_or_else(|| t.clone())
}

fn remove_bounds(store: &mut ElementStore, t: &TypeImpl) -> Option<TypeImpl> {
    match t {
        TypeImpl::Interface(i) => {
            let mut result: Option<Vec<TypeImpl>> = None;
            for (n, a) in i.type_arguments.iter().enumerate() {
                if let Some(new_type) = remove_bounds(store, a) {
                    result.get_or_insert_with(|| i.type_arguments.clone())[n] = new_type;
                }
            }
            Some(TypeImpl::interface(i.element, result?, i.nullability_suffix))
        }
        TypeImpl::Function(f) => {
            // `ReplacementVisitor.visitFunctionType` with
            // `visitTypeParameterBound` answering `Never`.
            let mut new_type_parameters: Option<Vec<ElementId>> = None;
            for (n, &p) in f.type_parameters.iter().enumerate() {
                if store.element(p).type_.is_some() {
                    let fresh = store.fresh_copy_type_parameter(p);
                    store.elements[fresh as usize].type_ = Some(TypeImpl::Never(NullabilitySuffix::none));
                    new_type_parameters.get_or_insert_with(|| f.type_parameters.clone())[n] = fresh;
                }
            }
            let substitution = new_type_parameters.as_ref().map(|new| {
                Substitution::from_pairs(
                    f.type_parameters.clone(),
                    new.iter().map(|&e| TypeImpl::type_parameter(e, NullabilitySuffix::none)).collect(),
                )
            });
            let visit = |store: &mut ElementStore, t: &TypeImpl| -> Option<TypeImpl> {
                let result = remove_bounds(store, t);
                match &substitution {
                    Some(s) => Some(substitute(store, s, result.as_ref().unwrap_or(t))),
                    None => result,
                }
            };
            let return_type = visit(store, &f.return_type);
            let mut parameters = None;
            for (n, p) in f.formal_parameters.iter().enumerate() {
                if let Some(t) = visit(store, &p.type_) {
                    parameters.get_or_insert_with(|| f.formal_parameters.clone())[n] = p.copy_with(Some(t), None);
                }
            }
            // `createFunctionType`: unchanged unless the return type or a
            // parameter changed.
            if return_type.is_none() && parameters.is_none() {
                return None;
            }
            Some(TypeImpl::Function(Rc::new(FunctionTypeImpl {
                type_parameters: new_type_parameters.unwrap_or_else(|| f.type_parameters.clone()),
                formal_parameters: parameters.unwrap_or_else(|| f.formal_parameters.clone()),
                return_type: return_type.unwrap_or_else(|| f.return_type.clone()),
                nullability_suffix: f.nullability_suffix,
            })))
        }
        TypeImpl::Record(r) => {
            let mut positional: Option<Vec<TypeImpl>> = None;
            for (n, field) in r.positional_fields.iter().enumerate() {
                if let Some(new_type) = remove_bounds(store, field) {
                    positional.get_or_insert_with(|| r.positional_fields.clone())[n] = new_type;
                }
            }
            let mut named: Option<Vec<(Rc<str>, TypeImpl)>> = None;
            for (n, (name, field)) in r.named_fields.iter().enumerate() {
                if let Some(new_type) = remove_bounds(store, field) {
                    named.get_or_insert_with(|| r.named_fields.clone())[n] = (name.clone(), new_type);
                }
            }
            if positional.is_none() && named.is_none() {
                return None;
            }
            Some(TypeImpl::Record(Rc::new(crate::src::dart::element::r#type::RecordTypeImpl::new(
                positional.unwrap_or_else(|| r.positional_fields.clone()),
                named.unwrap_or_else(|| r.named_fields.clone()),
                r.nullability_suffix,
            ))))
        }
        _ => None,
    }
}

/// `TypeSystemImpl.gatherMixinSupertypeConstraintsForInference`: the
/// superclass constraints of a mixin, or the supertype and mixins of a
/// class used as a mixin (without the last mixin of a mixin application),
/// keeping the generic ones.
pub fn gather_mixin_supertype_constraints_for_inference(store: &ElementStore, mixin: ElementId) -> Vec<TypeImpl> {
    let element = store.element(mixin);
    let types = store.types(mixin).cloned().unwrap_or_default();
    let candidates: Vec<TypeImpl> = if element.kind == ElementKind::MIXIN {
        types.superclass_constraints
    } else {
        let Some(supertype) = element.type_.clone() else {
            return Vec::new();
        };
        let mut candidates = vec![supertype];
        candidates.extend(types.mixins);
        let first = element.first_fragment;
        if element.kind == ElementKind::CLASS && store.fragment(first).has_flag(FragmentFlag::classFragment_isMixinApplication) {
            candidates.pop();
        }
        candidates
    };
    candidates
        .into_iter()
        .filter(|t| {
            t.as_interface().is_some_and(|i| {
                let first = store.element(i.element).first_fragment;
                !store.fragment(first).type_parameters.is_empty()
            })
        })
        .collect()
}
