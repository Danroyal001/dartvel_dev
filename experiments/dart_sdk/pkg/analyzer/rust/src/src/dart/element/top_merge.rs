// Port of lib/src/dart/element/top_merge.dart (`TopMergeHelper`): NNBD_TOP_MERGE,
// which the class hierarchy uses to merge two instantiations of the same
// class whose NORMs differ. Where upstream throws `_TopMergeStateError`
// (incompatible types), this returns `Err` with the reason, which the
// class hierarchy records as an error as upstream's catch does.
//
// The formal parameters of this crate's function types carry no
// `isCovariant` flag yet, so every parameter is merged as a non-covariant
// one; the covariant case needs the subtype relation and comes with it.

use std::rc::Rc;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::element::{ElementId, ElementStore};
use crate::src::dart::element::r#type::{FormalParameter, FunctionTypeImpl, RecordTypeImpl, TypeImpl};
use crate::src::dart::element::type_algebra::{substitute, Substitution};
use crate::src::dart::element::type_system::{is_object_class, object_type, other_nullability, with_suffix, without_nullability};
use crate::src::generated::utilities_dart::ParameterKind;

/// `TypeSystemImpl.topMerge`.
pub fn top_merge(store: &mut ElementStore, t: &TypeImpl, s: &TypeImpl) -> Result<TypeImpl, &'static str> {
    let t_suffix = other_nullability(t);
    let s_suffix = other_nullability(s);
    let t_object_question = t_suffix == NullabilitySuffix::question && is_object_class(store, t);
    let s_object_question = s_suffix == NullabilitySuffix::question && is_object_class(store, s);
    if t_object_question && s_object_question {
        return Ok(t.clone());
    }
    let t_dynamic = matches!(t, TypeImpl::Dynamic);
    let s_dynamic = matches!(s, TypeImpl::Dynamic);
    if t_dynamic && s_dynamic {
        return Ok(TypeImpl::Dynamic);
    }
    if matches!(t, TypeImpl::Invalid) || matches!(s, TypeImpl::Invalid) {
        return Ok(TypeImpl::Invalid);
    }
    if matches!(t, TypeImpl::Never(NullabilitySuffix::none)) && matches!(s, TypeImpl::Never(NullabilitySuffix::none)) {
        return Ok(TypeImpl::Never(NullabilitySuffix::none));
    }
    let t_void = matches!(t, TypeImpl::Void);
    let s_void = matches!(s, TypeImpl::Void);
    if t_void && s_void {
        return Ok(TypeImpl::Void);
    }
    if (t_object_question && s_void) || (t_void && s_object_question) {
        return Ok(object_type(store, NullabilitySuffix::question));
    }
    if (t_dynamic && s_void) || (t_void && s_dynamic) {
        return Ok(object_type(store, NullabilitySuffix::question));
    }
    if t_object_question && s_dynamic {
        return Ok(t.clone());
    }
    if t_dynamic && s_object_question {
        return Ok(s.clone());
    }
    let t_question = t_suffix == NullabilitySuffix::question;
    let s_question = s_suffix == NullabilitySuffix::question;
    if t_question && s_question {
        let r = top_merge(store, &without_nullability(t), &without_nullability(s))?;
        return Ok(with_suffix(&r, NullabilitySuffix::question));
    } else if t_question || s_question {
        return Err("different nullabilities");
    }
    match (t, s) {
        (TypeImpl::Interface(a), TypeImpl::Interface(b)) => {
            if a.element != b.element {
                return Err("Different class elements");
            }
            if a.type_arguments.is_empty() {
                return Ok(t.clone());
            }
            let mut arguments = Vec::with_capacity(a.type_arguments.len());
            for (x, y) in a.type_arguments.iter().zip(&b.type_arguments) {
                arguments.push(top_merge(store, x, y)?);
            }
            Ok(TypeImpl::interface(a.element, arguments, NullabilitySuffix::none))
        }
        (TypeImpl::Function(a), TypeImpl::Function(b)) => function_types(store, a, b),
        (TypeImpl::Record(a), TypeImpl::Record(b)) => record_types(store, a, b),
        (TypeImpl::TypeParameter(a), TypeImpl::TypeParameter(b)) => {
            if a.element == b.element {
                Ok(t.clone())
            } else {
                Err("Not the same type parameters")
            }
        }
        _ => Err("Unexpected pair"),
    }
}

/// `_parameterKind`.
fn parameter_kind(t: &FormalParameter, s: &FormalParameter) -> Option<ParameterKind> {
    if t.is_required_positional() && s.is_required_positional() {
        Some(ParameterKind::REQUIRED)
    } else if t.is_optional_positional() && s.is_optional_positional() {
        Some(ParameterKind::POSITIONAL)
    } else if t.is_required_named() && s.is_required_named() {
        Some(ParameterKind::NAMED_REQUIRED)
    } else if t.kind == ParameterKind::NAMED && s.kind == ParameterKind::NAMED {
        Some(ParameterKind::NAMED)
    } else {
        None
    }
}

/// `_functionTypes`.
fn function_types(store: &mut ElementStore, t: &FunctionTypeImpl, s: &FunctionTypeImpl) -> Result<TypeImpl, &'static str> {
    if t.type_parameters.len() != s.type_parameters.len() {
        return Err("Different number of type parameters");
    }
    let mut substitutions: Option<(Substitution, Substitution)> = None;
    let mut r_type_parameters = Vec::new();
    if !t.type_parameters.is_empty() {
        let (parameters, a, b) =
            type_parameters(store, &t.type_parameters, &s.type_parameters)?.ok_or("Unable to merge type parameters")?;
        r_type_parameters = parameters;
        substitutions = Some((a, b));
    }
    let merge = |store: &mut ElementStore, x: &TypeImpl, y: &TypeImpl| -> Result<TypeImpl, &'static str> {
        match &substitutions {
            Some((a, b)) => {
                let x = substitute(store, a, x);
                let y = substitute(store, b, y);
                top_merge(store, &x, &y)
            }
            None => top_merge(store, x, y),
        }
    };
    let r_return_type = merge(store, &t.return_type, &s.return_type)?;
    if t.formal_parameters.len() != s.formal_parameters.len() {
        return Err("Different number of formal parameters");
    }
    let mut r_parameters = Vec::with_capacity(t.formal_parameters.len());
    for (tp, sp) in t.formal_parameters.iter().zip(&s.formal_parameters) {
        let kind = parameter_kind(tp, sp).ok_or("Different formal parameter kinds")?;
        if tp.is_named() && tp.name != sp.name {
            return Err("Different named parameter names");
        }
        let r_type = merge(store, &tp.type_, &sp.type_)?;
        r_parameters.push(tp.copy_with(Some(r_type), Some(kind)));
    }
    Ok(TypeImpl::Function(Rc::new(FunctionTypeImpl::new(
        r_type_parameters,
        r_parameters,
        r_return_type,
        NullabilitySuffix::none,
    ))))
}

/// `_recordTypes`.
fn record_types(store: &mut ElementStore, a: &RecordTypeImpl, b: &RecordTypeImpl) -> Result<TypeImpl, &'static str> {
    if a.positional_fields.len() != b.positional_fields.len() {
        return Err("Different number of position fields");
    }
    let mut positional = Vec::with_capacity(a.positional_fields.len());
    for (x, y) in a.positional_fields.iter().zip(&b.positional_fields) {
        positional.push(top_merge(store, x, y)?);
    }
    if a.named_fields.len() != b.named_fields.len() {
        return Err("Different number of named fields");
    }
    let mut named = Vec::with_capacity(a.named_fields.len());
    for ((n1, x), (n2, y)) in a.named_fields.iter().zip(&b.named_fields) {
        if n1 != n2 {
            return Err("Different named field names");
        }
        named.push((n1.clone(), top_merge(store, x, y)?));
    }
    Ok(TypeImpl::Record(Rc::new(RecordTypeImpl::new(positional, named, NullabilitySuffix::none))))
}

/// `_typeParameters`: fresh type parameters, with the substitutions from
/// each side, and the bounds merged. `Ok(None)` when they cannot merge.
fn type_parameters(
    store: &mut ElementStore,
    a: &[ElementId],
    b: &[ElementId],
) -> Result<Option<(Vec<ElementId>, Substitution, Substitution)>, &'static str> {
    if a.len() != b.len() {
        return Ok(None);
    }
    let fresh: Vec<ElementId> = a.iter().map(|&p| store.fresh_copy_type_parameter(p)).collect();
    let types: Vec<TypeImpl> = fresh.iter().map(|&p| TypeImpl::type_parameter(p, NullabilitySuffix::none)).collect();
    let a_substitution = Substitution::from_pairs(a.to_vec(), types.clone());
    let b_substitution = Substitution::from_pairs(b.to_vec(), types);
    for i in 0..a.len() {
        let a_bound = store.element(a[i]).type_.clone();
        let b_bound = store.element(b[i]).type_.clone();
        match (a_bound, b_bound) {
            (None, None) => {}
            (Some(x), Some(y)) => {
                let x = substitute(store, &a_substitution, &x);
                let y = substitute(store, &b_substitution, &y);
                let merged = top_merge(store, &x, &y)?;
                store.elements[fresh[i] as usize].type_ = Some(merged);
            }
            _ => return Ok(None),
        }
    }
    Ok(Some((fresh, a_substitution, b_substitution)))
}
