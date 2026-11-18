// Port of lib/src/dart/element/least_greatest_closure.dart:
// `LeastGreatestClosureHelper`, a `ReplacementVisitor` that replaces the
// type parameters being eliminated with the top or the bottom type by
// variance, and a generic function type whose bounds mention one of them
// with `Function` or `Never`; with `TypeSystemImpl.greatestClosure` and
// `leastClosure`, which run it.
//
// Not ported: `PatternGreatestClosureHelper` (patterns only).

use std::rc::Rc;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::element::{ElementId, ElementStore};
use crate::src::dart::element::r#type::{FunctionTypeImpl, RecordTypeImpl, TypeImpl};
use crate::src::dart::element::type_algebra::unite_nullabilities;
use crate::src::dart::element::type_system::{object_type, other_nullability, sdk_class, with_suffix};

/// `TypeSystemImpl.greatestClosure`.
pub fn greatest_closure(store: &mut ElementStore, t: &TypeImpl, targets: &[ElementId]) -> TypeImpl {
    Closure::new(store, targets, false).eliminate(t)
}

/// `TypeSystemImpl.leastClosure`.
pub fn least_closure(store: &mut ElementStore, t: &TypeImpl, targets: &[ElementId]) -> TypeImpl {
    Closure::new(store, targets, true).eliminate(t)
}

/// `TypeImpl.referencesAny`.
pub fn references_any(store: &ElementStore, t: &TypeImpl, parameters: &[ElementId]) -> bool {
    match t {
        TypeImpl::TypeParameter(p) => parameters.contains(&p.element),
        TypeImpl::Interface(i) => i.type_arguments.iter().any(|a| references_any(store, a, parameters)),
        TypeImpl::Record(r) => {
            r.positional_fields.iter().any(|f| references_any(store, f, parameters))
                || r.named_fields.iter().any(|(_, f)| references_any(store, f, parameters))
        }
        TypeImpl::Function(f) => {
            f.type_parameters.iter().any(|&e| {
                let bound = store.element(e).type_.as_ref();
                let default = store.types(e).and_then(|t| t.default_type.as_ref());
                bound.is_some_and(|b| references_any(store, b, parameters))
                    || default.is_some_and(|d| references_any(store, d, parameters))
            }) || f.formal_parameters.iter().any(|p| references_any(store, &p.type_, parameters))
                || references_any(store, &f.return_type, parameters)
        }
        _ => false,
    }
}

struct Closure<'a> {
    store: &'a mut ElementStore,
    targets: &'a [ElementId],
    top: TypeImpl,
    top_function: TypeImpl,
    bottom: TypeImpl,
    is_least_closure: bool,
    is_covariant: bool,
}

impl<'a> Closure<'a> {
    fn new(store: &'a mut ElementStore, targets: &'a [ElementId], is_least_closure: bool) -> Self {
        let function = sdk_class(store, "dart:core", "Function").expect("dart:core declares Function");
        Closure {
            top: object_type(store, NullabilitySuffix::question),
            top_function: TypeImpl::interface(function, Vec::new(), NullabilitySuffix::none),
            bottom: TypeImpl::Never(NullabilitySuffix::none),
            store,
            targets,
            is_least_closure,
            is_covariant: true,
        }
    }

    fn eliminate(&mut self, t: &TypeImpl) -> TypeImpl {
        self.is_covariant = true;
        self.visit(t).unwrap_or_else(|| t.clone())
    }

    /// Whether the bottom type replaces: covariant in the least closure,
    /// contravariant in the greatest.
    fn to_bottom(&self) -> bool {
        self.is_least_closure == self.is_covariant
    }

    fn visit(&mut self, t: &TypeImpl) -> Option<TypeImpl> {
        match t {
            TypeImpl::TypeParameter(p) if self.targets.contains(&p.element) => {
                let replacement = if self.to_bottom() { &self.bottom } else { &self.top };
                let suffix = unite_nullabilities(other_nullability(replacement), p.nullability_suffix);
                Some(with_suffix(replacement, suffix))
            }
            TypeImpl::Interface(i) => {
                let first = self.store.element(i.element).first_fragment;
                let parameters = self.store.fragment(first).type_parameters.len();
                if parameters != i.type_arguments.len() {
                    return None;
                }
                let arguments = self.visit_list(&i.type_arguments)?;
                Some(TypeImpl::interface(i.element, arguments, i.nullability_suffix))
            }
            TypeImpl::Record(r) => {
                let positional = self.visit_list(&r.positional_fields);
                let mut named: Option<Vec<(Rc<str>, TypeImpl)>> = None;
                for (n, (name, field)) in r.named_fields.iter().enumerate() {
                    if let Some(new_field) = self.visit(field) {
                        named.get_or_insert_with(|| r.named_fields.clone())[n] = (name.clone(), new_field);
                    }
                }
                if positional.is_none() && named.is_none() {
                    return None;
                }
                Some(TypeImpl::Record(Rc::new(RecordTypeImpl::new(
                    positional.unwrap_or_else(|| r.positional_fields.clone()),
                    named.unwrap_or_else(|| r.named_fields.clone()),
                    r.nullability_suffix,
                ))))
            }
            TypeImpl::Function(f) => {
                let bound_mentions_target = f.type_parameters.iter().any(|&e| {
                    let bound = self.store.element(e).type_.clone();
                    bound.is_some_and(|b| references_any(self.store, &b, self.targets))
                });
                if bound_mentions_target {
                    return Some(if self.to_bottom() { self.bottom.clone() } else { self.top_function.clone() });
                }
                // `ReplacementVisitor.visitFunctionType`; no bound changes,
                // since none mentions a target.
                let return_type = self.visit(&f.return_type);
                self.is_covariant = !self.is_covariant;
                let mut parameters = None;
                for (n, p) in f.formal_parameters.iter().enumerate() {
                    if let Some(t) = self.visit(&p.type_) {
                        parameters.get_or_insert_with(|| f.formal_parameters.clone())[n] = p.copy_with(Some(t), None);
                    }
                }
                self.is_covariant = !self.is_covariant;
                if return_type.is_none() && parameters.is_none() {
                    return None;
                }
                Some(TypeImpl::Function(Rc::new(FunctionTypeImpl {
                    type_parameters: f.type_parameters.clone(),
                    formal_parameters: parameters.unwrap_or_else(|| f.formal_parameters.clone()),
                    return_type: return_type.unwrap_or_else(|| f.return_type.clone()),
                    nullability_suffix: f.nullability_suffix,
                })))
            }
            _ => None,
        }
    }

    fn visit_list(&mut self, types: &[TypeImpl]) -> Option<Vec<TypeImpl>> {
        let mut result: Option<Vec<TypeImpl>> = None;
        for (n, t) in types.iter().enumerate() {
            if let Some(new_type) = self.visit(t) {
                result.get_or_insert_with(|| types.to_vec())[n] = new_type;
            }
        }
        result
    }
}
