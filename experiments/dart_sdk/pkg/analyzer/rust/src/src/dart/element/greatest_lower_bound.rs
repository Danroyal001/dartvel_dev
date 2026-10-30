// Port of lib/src/dart/element/greatest_lower_bound.dart:
// `GreatestLowerBoundHelper`, DOWN(T1, T2) of
// resources/type-system/upper-lower-bounds.md, as methods of the
// `TypeSystem` with `TypeSystemImpl.greatestLowerBound`.
//
// DOWN has no depth guard of its own; a LUB it calls past the type
// operation depth limit fails up to the outermost LUB, which is why the
// inner functions return `Result`.

use std::rc::Rc;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::r#type::{FunctionTypeImpl, RecordTypeImpl, TypeImpl};
use crate::src::dart::element::subtype::{instantiate, TypeSystem};
use crate::src::dart::element::least_upper_bound::DepthExceeded;
use crate::src::dart::element::type_schema_elimination::greatest_closure_of_schema;
use crate::src::dart::element::type_system::{
    compare_names, future_or_type, future_type, is_bottom, is_dart_core_null, is_future, is_future_or, is_more_bottom,
    is_more_top, is_non_nullable, is_null, is_object, is_top, null_none, other_nullability, promote_to_non_null,
    with_suffix, without_nullability,
};
use crate::src::generated::utilities_dart::ParameterKind;

const NEVER: TypeImpl = TypeImpl::Never(NullabilitySuffix::none);

impl TypeSystem<'_> {
    /// `TypeSystemImpl.greatestLowerBound`.
    pub fn greatest_lower_bound(&mut self, t1: &TypeImpl, t2: &TypeImpl) -> TypeImpl {
        // An error can only come from a LUB nested in an outer LUB, and
        // this call has none around it.
        self.glb(t1, t2).unwrap_or_else(|_| unreachable!("the outermost LUB catches the depth limit"))
    }

    /// `getGreatestLowerBound`.
    pub(crate) fn glb(&mut self, t1: &TypeImpl, t2: &TypeImpl) -> Result<TypeImpl, DepthExceeded> {
        if matches!(t1, TypeImpl::Unknown) {
            return Ok(t2.clone());
        }
        if matches!(t2, TypeImpl::Unknown) {
            return Ok(t1.clone());
        }
        let store = &*self.store;

        let (t1_is_top, t2_is_top) = (is_top(store, t1), is_top(store, t2));
        if t1_is_top && t2_is_top {
            return Ok(if is_more_top(store, t2, t1) { t1.clone() } else { t2.clone() });
        }
        if t1_is_top {
            return Ok(t2.clone());
        }
        if t2_is_top {
            return Ok(t1.clone());
        }

        let (t1_is_bottom, t2_is_bottom) = (is_bottom(store, t1), is_bottom(store, t2));
        if t1_is_bottom && t2_is_bottom {
            return Ok(if is_more_bottom(store, t1, t2) { t1.clone() } else { t2.clone() });
        }
        if t1_is_bottom {
            return Ok(t1.clone());
        }
        if t2_is_bottom {
            return Ok(t2.clone());
        }

        let (t1_is_null, t2_is_null) = (is_null(store, t1), is_null(store, t2));
        if t1_is_null && t2_is_null {
            return Ok(if is_more_bottom(store, t1, t2) { t1.clone() } else { t2.clone() });
        }

        let (t1_nullability, t2_nullability) = (other_nullability(t1), other_nullability(t2));
        // DOWN(Null, T2) and DOWN(T1, Null).
        for (null, other, nullability) in [(t1, t2, t1_nullability), (t2, t1, t2_nullability)] {
            if nullability == NullabilitySuffix::none && is_dart_core_null(self.store, null) {
                let null_type = null_none(self.store);
                return Ok(if self.is_subtype_of(&null_type, other) { null_type } else { NEVER });
            }
        }

        let store = &*self.store;
        let (t1_is_object, t2_is_object) = (is_object(store, t1), is_object(store, t2));
        if t1_is_object && t2_is_object {
            return Ok(if is_more_top(store, t2, t1) { t1.clone() } else { t2.clone() });
        }
        // DOWN(T1, T2) where OBJECT(T1), and where OBJECT(T2).
        for (object, other) in [(t1_is_object, t2), (t2_is_object, t1)] {
            if object {
                if is_non_nullable(store, other) {
                    return Ok(other.clone());
                }
                let non_null = promote_to_non_null(store, other);
                if is_non_nullable(store, &non_null) {
                    return Ok(non_null);
                }
                return Ok(NEVER);
            }
        }

        if t1_nullability != NullabilitySuffix::none || t2_nullability != NullabilitySuffix::none {
            let s = self.glb(&without_nullability(t1), &without_nullability(t2))?;
            if t1_nullability == NullabilitySuffix::question && t2_nullability == NullabilitySuffix::question {
                return Ok(with_suffix(&s, NullabilitySuffix::question));
            }
            return Ok(s);
        }

        if let (TypeImpl::Function(f), TypeImpl::Function(g)) = (t1, t2) {
            return self.glb_function_type(f, g);
        }
        if let (TypeImpl::Record(a), TypeImpl::Record(b)) = (t1, t2) {
            return self.glb_record_type(a, b);
        }

        if self.schema_is_subtype_of(t1, t2) {
            return Ok(t1.clone());
        }
        if self.schema_is_subtype_of(t2, t1) {
            return Ok(t2.clone());
        }

        let store = &*self.store;
        if is_future_or(store, t1) {
            let s1 = t1.as_interface().unwrap().type_arguments[0].clone();
            if is_future_or(store, t2) {
                let s2 = t2.as_interface().unwrap().type_arguments[0].clone();
                let s = self.glb(&s1, &s2)?;
                return Ok(future_or_type(self.store, s));
            }
            if is_future(store, t2) {
                let s2 = t2.as_interface().unwrap().type_arguments[0].clone();
                let s = self.glb(&s1, &s2)?;
                return Ok(future_type(self.store, s));
            }
            return self.glb(&s1, t2);
        }
        if is_future_or(store, t2) {
            let s2 = t2.as_interface().unwrap().type_arguments[0].clone();
            if is_future(store, t1) {
                let s1 = t1.as_interface().unwrap().type_arguments[0].clone();
                let s = self.glb(&s1, &s2)?;
                return Ok(future_type(self.store, s));
            }
            return self.glb(t1, &s2);
        }
        Ok(NEVER)
    }

    /// `_isSubtypeOf`: of the greatest closures of the schemas.
    fn schema_is_subtype_of(&mut self, t1: &TypeImpl, t2: &TypeImpl) -> bool {
        let s1 = greatest_closure_of_schema(self.store, t1);
        let s2 = greatest_closure_of_schema(self.store, t2);
        self.is_subtype_of(&s1, &s2)
    }

    /// `_functionType`.
    fn glb_function_type(&mut self, f: &FunctionTypeImpl, g: &FunctionTypeImpl) -> Result<TypeImpl, DepthExceeded> {
        if f.type_parameters.len() != g.type_parameters.len() {
            return Ok(NEVER);
        }
        let Some(fresh) = self.relate_type_parameters(&f.type_parameters, &g.type_parameters) else {
            return Ok(NEVER);
        };
        let f = instantiate(self.store, f, &fresh);
        let g = instantiate(self.store, g, &fresh);
        let (fp, gp) = (&f.formal_parameters, &g.formal_parameters);
        let mut parameters = Vec::new();
        let (mut fi, mut gi) = (0, 0);
        while fi < fp.len() && gi < gp.len() {
            let (a, b) = (&fp[fi], &gp[gi]);
            if a.is_positional() {
                if !b.is_positional() {
                    return Ok(NEVER);
                }
                fi += 1;
                gi += 1;
                let t = self.lub(&a.type_, &b.type_)?;
                let kind = if a.is_optional() || b.is_optional() { ParameterKind::POSITIONAL } else { ParameterKind::REQUIRED };
                parameters.push(a.copy_with(Some(t), Some(kind)));
            } else {
                if !b.is_named() {
                    return Ok(NEVER);
                }
                let (Some(a_name), Some(b_name)) = (&a.name, &b.name) else {
                    return Ok(NEVER);
                };
                match compare_names(a_name, b_name) {
                    std::cmp::Ordering::Equal => {
                        fi += 1;
                        gi += 1;
                        let t = self.lub(&a.type_, &b.type_)?;
                        let kind = if a.is_required_named() && b.is_required_named() {
                            ParameterKind::NAMED_REQUIRED
                        } else {
                            ParameterKind::NAMED
                        };
                        parameters.push(a.copy_with(Some(t), Some(kind)));
                    }
                    std::cmp::Ordering::Less => {
                        fi += 1;
                        parameters.push(a.copy_with(None, Some(ParameterKind::NAMED)));
                    }
                    std::cmp::Ordering::Greater => {
                        gi += 1;
                        parameters.push(b.copy_with(None, Some(ParameterKind::NAMED)));
                    }
                }
            }
        }
        for p in fp[fi..].iter().chain(gp[gi..].iter()) {
            let kind = if p.is_positional() { ParameterKind::POSITIONAL } else { ParameterKind::NAMED };
            parameters.push(p.copy_with(None, Some(kind)));
        }
        let return_type = self.glb(&f.return_type, &g.return_type)?;
        let type_parameters = fresh_elements(&fresh);
        Ok(TypeImpl::Function(Rc::new(FunctionTypeImpl::new(
            type_parameters,
            parameters,
            return_type,
            NullabilitySuffix::none,
        ))))
    }

    /// `_recordType`.
    fn glb_record_type(&mut self, a: &RecordTypeImpl, b: &RecordTypeImpl) -> Result<TypeImpl, DepthExceeded> {
        if a.positional_fields.len() != b.positional_fields.len() || a.named_fields.len() != b.named_fields.len() {
            return Ok(NEVER);
        }
        let mut positional = Vec::with_capacity(a.positional_fields.len());
        for (x, y) in a.positional_fields.iter().zip(&b.positional_fields) {
            positional.push(self.glb(x, y)?);
        }
        let mut named = Vec::with_capacity(a.named_fields.len());
        for ((xn, x), (yn, y)) in a.named_fields.iter().zip(&b.named_fields) {
            if xn != yn {
                return Ok(NEVER);
            }
            named.push((xn.clone(), self.glb(x, y)?));
        }
        Ok(TypeImpl::Record(Rc::new(RecordTypeImpl::new(positional, named, NullabilitySuffix::none))))
    }
}

/// `typeParameters` of the fresh types `relateTypeParameters` made.
pub(crate) fn fresh_elements(fresh: &[TypeImpl]) -> Vec<crate::src::dart::element::element::ElementId> {
    fresh
        .iter()
        .map(|t| match t {
            TypeImpl::TypeParameter(p) => p.element,
            _ => unreachable!("relateTypeParameters makes type parameter types"),
        })
        .collect()
}
