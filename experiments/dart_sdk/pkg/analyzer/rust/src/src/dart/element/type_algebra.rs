// Port of lib/src/dart/element/type_algebra.dart: `Substitution.fromPairs2`
// (a map from type parameters to types), `substituteType` through
// `_TopSubstitutor`, `_FreshTypeParametersSubstitutor` and
// `_TypeSubstitutor`, `replaceTypeParameters` and `uniteNullabilities`.
//
// The substitutors' environments are a stack: the top-level one holds the
// substitution, and each generic function type pushes one that maps its
// type parameters to fresh copies. A type that the substitution does not
// change comes back as the same object, which upstream checks with each
// environment's use counter; so does this port.
//
// Not ported: `Substitution.fromMap` combinations (`andThen`, `combine`),
// `fromInterfaceType`, `upperBound`/variance-directed lookups (only the
// inference visitors use them), aliases (`_mapAlias`) and
// `UnknownInferredType`.

use std::rc::Rc;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::element::{ElementId, ElementStore};
use crate::src::dart::element::r#type::{FormalParameter, FunctionTypeImpl, InterfaceTypeImpl, RecordTypeImpl, TypeImpl};
use crate::src::summary2::type_builder::{FunctionTypeBuilder, NamedTypeBuilder, TypeBuilder};

/// `Substitution.fromPairs2`: [parameters] map to [arguments], position by
/// position.
#[derive(Clone, Debug, Default)]
pub struct Substitution {
    pub map: Vec<(ElementId, TypeImpl)>,
}

impl Substitution {
    pub fn from_pairs(parameters: Vec<ElementId>, arguments: Vec<TypeImpl>) -> Substitution {
        assert_eq!(parameters.len(), arguments.len());
        Substitution {
            map: parameters.into_iter().zip(arguments).collect(),
        }
    }

    fn get_substitute(&self, parameter: ElementId) -> Option<&TypeImpl> {
        self.map.iter().find(|(p, _)| *p == parameter).map(|(_, t)| t)
    }
}

/// `Substitution.substituteType`.
pub fn substitute(store: &mut ElementStore, substitution: &Substitution, type_: &TypeImpl) -> TypeImpl {
    let mut substitutor = Substitutor {
        store,
        environments: vec![Environment {
            map: substitution.map.clone(),
            use_counter: 0,
        }],
    };
    substitutor.visit(type_)
}

/// `replaceTypeParameters`: [type_] with its type parameters replaced by
/// [new_type_parameters].
pub fn replace_type_parameters(
    store: &mut ElementStore,
    type_: &FunctionTypeImpl,
    new_type_parameters: Vec<ElementId>,
) -> FunctionTypeImpl {
    assert_eq!(new_type_parameters.len(), type_.type_parameters.len());
    if new_type_parameters.is_empty() {
        return type_.clone();
    }
    let arguments = new_type_parameters
        .iter()
        .map(|e| TypeImpl::type_parameter(*e, NullabilitySuffix::none))
        .collect();
    let substitution = Substitution::from_pairs(type_.type_parameters.clone(), arguments);
    let formal_parameters = type_
        .formal_parameters
        .iter()
        .map(|p| {
            let t = substitute(store, &substitution, &p.type_);
            p.copy_with(Some(t), None)
        })
        .collect();
    let return_type = substitute(store, &substitution, &type_.return_type);
    FunctionTypeImpl::new(new_type_parameters, formal_parameters, return_type, type_.nullability_suffix)
}

/// `uniteNullabilities`.
pub fn unite_nullabilities(a: NullabilitySuffix, b: NullabilitySuffix) -> NullabilitySuffix {
    if a == NullabilitySuffix::question || b == NullabilitySuffix::question {
        NullabilitySuffix::question
    } else {
        NullabilitySuffix::none
    }
}

/// One substitutor environment: `_TopSubstitutor` (the first) or a
/// `_FreshTypeParametersSubstitutor`.
struct Environment {
    map: Vec<(ElementId, TypeImpl)>,
    /// `useCounter`.
    use_counter: u32,
}

struct Substitutor<'a> {
    store: &'a mut ElementStore,
    environments: Vec<Environment>,
}

impl Substitutor<'_> {
    fn counter(&self) -> u32 {
        self.environments.last().unwrap().use_counter
    }

    /// `getSubstitute` with `bumpCountersUntil`: every environment from the
    /// innermost out to the one that maps [parameter] counts a use.
    fn get_substitute(&mut self, parameter: ElementId) -> Option<TypeImpl> {
        for i in (0..self.environments.len()).rev() {
            let found = self.environments[i].map.iter().find(|(p, _)| *p == parameter).map(|(_, t)| t.clone());
            if let Some(replacement) = found {
                for environment in &mut self.environments[i..] {
                    environment.use_counter += 1;
                }
                return Some(replacement);
            }
        }
        None
    }

    /// `newInnerEnvironment().freshTypeParameters(elements)`: pushes the
    /// environment and returns the fresh copies, whose bounds are the
    /// originals' substituted in it.
    fn push_fresh(&mut self, elements: &[ElementId]) -> Vec<ElementId> {
        let mut fresh = Vec::with_capacity(elements.len());
        let mut map = Vec::with_capacity(elements.len());
        for &element in elements {
            let copy = self.store.fresh_copy_type_parameter(element);
            map.push((element, TypeImpl::type_parameter(copy, NullabilitySuffix::none)));
            fresh.push(copy);
        }
        self.environments.push(Environment { map, use_counter: 0 });
        for (i, &element) in elements.iter().enumerate() {
            if let Some(bound) = self.store.element(element).type_.clone() {
                let substituted = self.visit(&bound);
                self.store.elements[fresh[i] as usize].type_ = Some(substituted);
            }
        }
        fresh
    }

    fn map_list(&mut self, types: &[TypeImpl]) -> Vec<TypeImpl> {
        types.iter().map(|t| self.visit(t)).collect()
    }

    fn map_parameters(&mut self, parameters: &[FormalParameter]) -> Vec<FormalParameter> {
        parameters
            .iter()
            .map(|p| {
                let t = self.visit(&p.type_);
                p.copy_with(Some(t), None)
            })
            .collect()
    }

    fn visit(&mut self, type_: &TypeImpl) -> TypeImpl {
        match type_ {
            TypeImpl::Dynamic | TypeImpl::Void | TypeImpl::Invalid | TypeImpl::Never(_) => type_.clone(),
            TypeImpl::Interface(t) => {
                if t.type_arguments.is_empty() {
                    return type_.clone();
                }
                let before = self.counter();
                let type_arguments = self.map_list(&t.type_arguments);
                if self.counter() == before {
                    return type_.clone();
                }
                TypeImpl::Interface(Rc::new(InterfaceTypeImpl {
                    element: t.element,
                    type_arguments,
                    nullability_suffix: t.nullability_suffix,
                }))
            }
            TypeImpl::TypeParameter(t) => {
                let Some(argument) = self.get_substitute(t.element) else {
                    return type_.clone();
                };
                let nullability =
                    unite_nullabilities(t.nullability_suffix, argument.nullability_suffix(self.store));
                argument.with_nullability(self.store, nullability)
            }
            TypeImpl::Record(t) => {
                let before = self.counter();
                let positional = self.map_list(&t.positional_fields);
                let named = t
                    .named_fields
                    .iter()
                    .map(|(name, field)| (name.clone(), self.visit(field)))
                    .collect();
                if self.counter() == before {
                    return type_.clone();
                }
                TypeImpl::Record(Rc::new(RecordTypeImpl::new(positional, named, t.nullability_suffix)))
            }
            TypeImpl::Function(t) => {
                let before = self.counter();
                let pushed = !t.type_parameters.is_empty();
                let type_parameters = if pushed {
                    self.push_fresh(&t.type_parameters)
                } else {
                    Vec::new()
                };
                let formal_parameters = self.map_parameters(&t.formal_parameters);
                let return_type = self.visit(&t.return_type);
                if pushed {
                    self.environments.pop();
                }
                if self.counter() == before {
                    return type_.clone();
                }
                TypeImpl::Function(Rc::new(FunctionTypeImpl::new(
                    type_parameters,
                    formal_parameters,
                    return_type,
                    t.nullability_suffix,
                )))
            }
            TypeImpl::Builder(id) => self.visit_builder(*id, type_),
        }
    }

    fn visit_builder(&mut self, id: u32, type_: &TypeImpl) -> TypeImpl {
        let builder = self.store.type_builders[id as usize].clone();
        let new_builder = match builder {
            TypeBuilder::Named(b) => {
                if b.arguments.is_empty() {
                    return type_.clone();
                }
                let before = self.counter();
                let arguments = self.map_list(&b.arguments);
                if self.counter() == before {
                    return type_.clone();
                }
                TypeBuilder::Named(NamedTypeBuilder {
                    element: b.element,
                    arguments,
                    nullability_suffix: b.nullability_suffix,
                    node: None,
                    type_: None,
                })
            }
            TypeBuilder::Function(b) => {
                let before = self.counter();
                let pushed = !b.type_parameters.is_empty();
                let type_parameters = if pushed {
                    self.push_fresh(&b.type_parameters)
                } else {
                    Vec::new()
                };
                let formal_parameters = self.map_parameters(&b.formal_parameters);
                let return_type = self.visit(&b.return_type);
                if pushed {
                    self.environments.pop();
                }
                if self.counter() == before {
                    return type_.clone();
                }
                TypeBuilder::Function(FunctionTypeBuilder {
                    type_parameters,
                    formal_parameters,
                    return_type,
                    nullability_suffix: b.nullability_suffix,
                    node: None,
                    type_: None,
                })
            }
            // `visitRecordTypeBuilder`: `throw UnimplementedError()`.
            TypeBuilder::Record(_) => panic!("UnimplementedError: visitRecordTypeBuilder"),
        };
        let new_id = self.store.type_builders.len() as u32;
        self.store.type_builders.push(new_builder);
        TypeImpl::Builder(new_id)
    }
}

impl Substitution {
    /// Whether the substitution maps nothing (`Substitution.empty`).
    pub fn is_empty(&self) -> bool {
        self.map.is_empty()
    }

    /// `getSubstitute` of the top-level substitution.
    pub fn lookup(&self, parameter: ElementId) -> Option<&TypeImpl> {
        self.get_substitute(parameter)
    }
}
