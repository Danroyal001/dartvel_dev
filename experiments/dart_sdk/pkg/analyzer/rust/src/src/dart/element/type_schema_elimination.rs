// Port of lib/src/dart/element/type_schema_elimination.dart:
// `TypeSchemaEliminationVisitor`, which replaces the unknown type `_` with
// the top or the bottom type by variance; with
// `TypeSystemImpl.greatestClosureOfSchema` and `leastClosureOfSchema`.

use std::rc::Rc;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::element::ElementStore;
use crate::src::dart::element::r#type::{FunctionTypeImpl, RecordTypeImpl, TypeImpl};
use crate::src::dart::element::type_system::object_type;

/// `greatestClosureOfSchema`: covariant `_` becomes `Object?`,
/// contravariant `_` becomes `Never`.
pub fn greatest_closure_of_schema(store: &ElementStore, schema: &TypeImpl) -> TypeImpl {
    run(store, schema, false)
}

/// `leastClosureOfSchema`: covariant `_` becomes `Never`, contravariant
/// `_` becomes `Object?`.
pub fn least_closure_of_schema(store: &ElementStore, schema: &TypeImpl) -> TypeImpl {
    run(store, schema, true)
}

fn run(store: &ElementStore, schema: &TypeImpl, is_least_closure: bool) -> TypeImpl {
    let mut visitor = Eliminator {
        top: object_type(store, NullabilitySuffix::question),
        is_least_closure,
    };
    visitor.visit(schema).unwrap_or_else(|| schema.clone())
}

struct Eliminator {
    top: TypeImpl,
    is_least_closure: bool,
}

impl Eliminator {
    fn visit(&mut self, t: &TypeImpl) -> Option<TypeImpl> {
        match t {
            TypeImpl::Unknown => Some(if self.is_least_closure {
                TypeImpl::Never(NullabilitySuffix::none)
            } else {
                self.top.clone()
            }),
            TypeImpl::Interface(i) => {
                let arguments = self.visit_list(&i.type_arguments)?;
                Some(TypeImpl::interface(i.element, arguments, i.nullability_suffix))
            }
            TypeImpl::TypeParameter(p) => {
                let promoted_bound = p.promoted_bound.as_ref()?;
                let new_bound = self.visit(promoted_bound)?;
                Some(TypeImpl::promoted_type_parameter(p.element, p.nullability_suffix, new_bound))
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
                // Inference never puts `_` in a type parameter bound.
                let return_type = self.visit(&f.return_type);
                self.is_least_closure = !self.is_least_closure;
                let mut parameters = None;
                for (n, p) in f.formal_parameters.iter().enumerate() {
                    if let Some(t) = self.visit(&p.type_) {
                        parameters.get_or_insert_with(|| f.formal_parameters.clone())[n] = p.copy_with(Some(t), None);
                    }
                }
                self.is_least_closure = !self.is_least_closure;
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
